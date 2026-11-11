import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/widgets.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:html/dom.dart' as dom;
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

import '../../core/url_tools.dart';
import '../../ui/ad_block.dart';
import '../web_scraper.dart';
import 'cf_session.dart';
import 'generic_site_adapter.dart';
import 'scrape_cache.dart';
import 'site_adapter.dart';

class ScrapeService {
  ScrapeService({http.Client? client}) : _client = client ?? http.Client();

  final http.Client _client;
  final List<SiteAdapter> _adapters = [const GenericSiteAdapter()];

  /// Chapters whose fast-path result was incomplete (lazy readers only put
  /// the first few pages in the HTML). Returned as a last resort but never
  /// written to the disk cache.
  final Set<String> _partialUrls = {};

  /// "13 pages" style hint in server HTML; 0 when absent.
  static int _expectedPageCount(String html) {
    final m = RegExp(r'(\d{1,4})\s*pages\b', caseSensitive: false)
        .firstMatch(html.length > 400000 ? html.substring(0, 400000) : html);
    return m == null ? 0 : (int.tryParse(m.group(1)!) ?? 0);
  }

  /// The real WebView user-agent (see CfSession). It must be identical for the
  /// verification WebView, the headless scraper, HTTP and image downloads,
  /// otherwise Cloudflare's cf_clearance cookie stops being valid.
  static String get mobileUserAgent => CfSession.userAgent;

  void registerAdapter(SiteAdapter adapter) {
    _adapters.insert(0, adapter); // Custom adapters take precedence
  }

  SiteAdapter _adapterFor(String host) {
    for (final a in _adapters) {
      if (a.matches(host)) return a;
    }
    return const GenericSiteAdapter();
  }

  ScrapedChapterResult _needsVerification(String url) => ScrapedChapterResult(
        chapterUrl: url,
        pages: const [],
        needsVerification: true,
        verificationUrl: url,
      );

  /// Scrapes pages from a chapter URL using the multi-tier engine:
  /// 1. Fast path (HTTP GET + DOM parsing + Script extraction)
  /// 2. Rendered path fallback (Headless WebView that waits out Cloudflare
  ///    auto-challenges, then scrolls + reads JS globals)
  /// 3. Series overview auto-detection (resolves chapter list -> chapter 1)
  ///
  /// Results are cached on disk; pass [forceRefresh] to look for new content.
  ///
  /// The user is only asked to verify manually if the headless WebView could
  /// not get past Cloudflare on its own.
  Future<ScrapedChapterResult> scrapeChapter(
    String url, {
    bool forceRefresh = false,
  }) async {
    // Cache-first: a chapter that was scraped (or verified) once is served
    // from disk, so no network, no Cloudflare, no re-verification.
    if (!forceRefresh) {
      final cached = await ScrapeCache.instance.get(url);
      if (cached != null) {
        CfDiag.log('cache hit ${Uri.tryParse(url)?.host} pages=${cached.pages.length}');
        await CfSession.primeAll(url, cached.pages);
        return cached;
      }
    }

    _partialUrls.remove(url);
    final result = await _scrapeChapter(url);
    final isPartial = _partialUrls.remove(url);
    if (result.pages.length >= 2 && !result.needsVerification && !isPartial) {
      await ScrapeCache.instance.put(url, result);
      if (result.chapterUrl != url) {
        await ScrapeCache.instance.put(result.chapterUrl, result);
      }
      // Make cf_clearance + UA available to image downloads.
      await CfSession.primeAll(url, result.pages);
    }
    return result;
  }

  /// Stores a chapter the user just verified by hand, so it is never asked
  /// for again and the reader can continue to the next/previous chapter.
  Future<void> cacheVerified(
    String url, {
    required List<String> pages,
    String? title,
    String? nextUrl,
    String? prevUrl,
    List<ChapterRef> chapters = const [],
  }) async {
    if (pages.length < 2) return;
    final result = ScrapedChapterResult(
      chapterUrl: url,
      pages: pages,
      title: title != null ? UrlTools.cleanTitle(title) : null,
      chapterLabel: UrlTools.chapterLabel(url),
      nextChapterUrl: nextUrl ?? UrlTools.stepChapter(url, 1),
      prevChapterUrl: prevUrl ?? UrlTools.stepChapter(url, -1),
      nextGuessed: nextUrl == null,
      isWebtoon: true,
      availableChapters: chapters,
    );
    await ScrapeCache.instance.put(url, result);
    await CfSession.primeAll(url, pages);
  }

  Future<ScrapedChapterResult> _scrapeChapter(String url) async {
    final uri = Uri.tryParse(url);
    if (uri == null) {
      return ScrapedChapterResult(chapterUrl: url, pages: const []);
    }

    final adapter = _adapterFor(uri.host);
    ScrapedChapterResult? partial;

    // ------------------------------------------------------------- 1. Fast Path
    // Skipped for hosts that already challenged plain HTTP: Dart's HTTP client
    // doesn't look like a browser to Cloudflare, so we go straight to the
    // WebView for those hosts.
    if (!CfSession.webViewOnlyHosts.contains(uri.host)) {
      try {
        final headers = <String, String>{
          'User-Agent': CfSession.userAgent,
          'Accept':
              'text/html,application/xhtml+xml,application/xml;q=0.9,image/avif,image/webp,*/*;q=0.8',
          'Accept-Language': 'en-US,en;q=0.9',
          'Referer': url,
        };
        final cookie = await CfSession.cookieHeader(url);
        if (cookie != null) headers['Cookie'] = cookie;

        final response = await _client
            .get(uri, headers: headers)
            .timeout(const Duration(seconds: 4));
        CfDiag.log(
          'http ${response.statusCode} ${uri.host} '
          'cf-mitigated=${response.headers['cf-mitigated']} '
          'server=${response.headers['server']}',
        );

        if (CfSession.isChallengeResponse(
          response.statusCode,
          response.headers,
          response.body,
        )) {
          // Don't bother the user yet: the WebView can often pass by itself.
          CfSession.webViewOnlyHosts.add(uri.host);
        } else if (response.statusCode == 200 && response.body.isNotEmpty) {
          final doc = dom.Document.html(response.body);
          final result = await adapter.extract(doc, uri);
          if (result.needsVerification) {
            CfSession.webViewOnlyHosts.add(uri.host);
          } else if (result.pages.length >= 2) {
            final expected = _expectedPageCount(response.body);
            if (expected <= result.pages.length) {
              return result; // Fast path succeeded!
            }
            // Lazy reader: the HTML only held the first few pages. Render it
            // in the WebView to get all of them; keep this as a fallback.
            CfDiag.log(
              'fast path incomplete ${uri.host} '
              '${result.pages.length}/$expected -> rendering',
            );
            partial = result;
          } else {
            // Series overview page? Auto-hop to the first available chapter.
            final targetUrl = result.firstChapterUrl ??
                (result.availableChapters.isNotEmpty
                    ? _pickStartingChapter(result.availableChapters, url)?.url
                    : null);

            if (targetUrl != null && targetUrl != url) {
              final chRes = await scrapeChapter(targetUrl);
              if (chRes.pages.length >= 2 || chRes.needsVerification) {
                return chRes.copyWith(
                  availableChapters: result.availableChapters.isNotEmpty
                      ? result.availableChapters
                      : chRes.availableChapters,
                  coverUrl: result.coverUrl ?? chRes.coverUrl,
                );
              }
            }
          }
        } else if (response.statusCode == 403 || response.statusCode == 503) {
          CfSession.webViewOnlyHosts.add(uri.host);
        }
      } catch (_) {
        // Fall through to rendered path
      }
    }

    // --------------------------------- 2. Rendered Path (HeadlessInAppWebView)
    try {
      final rendered = await _scrapeHeadless(url, uri);
      if (rendered.needsVerification) {
        return rendered;
      }
      if (rendered.pages.length >= 2) {
        return rendered;
      }
      final targetUrl = rendered.firstChapterUrl ??
          (rendered.availableChapters.isNotEmpty
              ? _pickStartingChapter(rendered.availableChapters, url)?.url
              : null);

      if (targetUrl != null && targetUrl != url) {
        final chRes = await scrapeChapter(targetUrl);
        if (chRes.pages.length >= 2 || chRes.needsVerification) {
          return chRes.copyWith(
            availableChapters: rendered.availableChapters.isNotEmpty
                ? rendered.availableChapters
                : chRes.availableChapters,
            coverUrl: rendered.coverUrl ?? chRes.coverUrl,
          );
        }
      }
    } catch (e) {
      CfDiag.log('rendered path failed ${uri.host}: $e');
    }

    if (partial != null) {
      _partialUrls.add(url);
      return partial;
    }

    // Fallback: return best effort or stepChapter
    return ScrapedChapterResult(
      chapterUrl: url,
      pages: const [],
      chapterLabel: UrlTools.chapterLabel(url),
      nextChapterUrl: UrlTools.stepChapter(url, 1),
      prevChapterUrl: UrlTools.stepChapter(url, -1),
      nextGuessed: true,
    );
  }

  ChapterRef? _pickStartingChapter(
      List<ChapterRef> chapters, String currentUrl) {
    if (chapters.isEmpty) return null;
    final normCurrent = UrlTools.normalize(currentUrl);

    // Filter out current URL
    final candidates = chapters
        .where((c) => UrlTools.normalize(c.url) != normCurrent)
        .toList();
    if (candidates.isEmpty) return null;

    // Try finding Chapter 1
    final ch1 = candidates.firstWhere(
      (c) => RegExp(r'\b(?:ch(?:apter)?\.?\s*)?0*1\b', caseSensitive: false)
          .hasMatch(c.label),
      orElse: () => candidates.first,
    );
    return ch1;
  }

  Future<ScrapedChapterResult> _scrapeHeadless(String url, Uri uri) async {
    final completer = Completer<ScrapedChapterResult>();
    HeadlessInAppWebView? headless;
    var started = false;
    var challengeSeen = false;
    Timer? quietTimer;

    void finish(ScrapedChapterResult r) {
      if (!completer.isCompleted) completer.complete(r);
      quietTimer?.cancel();
      final h = headless;
      headless = null;
      h?.dispose();
    }

    final settings = CfSession.webViewSettings(
      contentBlockers: buildContentBlockers(),
    );

    /// Reads the current list of page image URLs from the live DOM.
    Future<List<String>> readUrls(InAppWebViewController c) async {
      final res = await c.evaluateJavascript(source: WebScraper.extractImagesJs);
      final out = <String>[];
      if (res is List) {
        for (final p in res) {
          if (p != null && p.toString().isNotEmpty) out.add(p.toString());
        }
      }
      return out;
    }

    /// The page is rendered by JavaScript, often only AFTER onLoadStop
    /// (Next.js / React readers, lazy images). A single immediate read, as
    /// before, saw an empty reader. So: poll, scrolling down step by step,
    /// until the page list stops growing (or reaches the page count the site
    /// announces).
    Future<void> runExtraction(InAppWebViewController c) async {
      final deadline = DateTime.now().add(const Duration(seconds: 18));
      var pages = <String>[];
      var lastCount = -1;
      var stable = 0;
      var bottom = false;
      var expected = 0;
      var stillChallenge = false;
      var challengeAttempts = 0;

      while (DateTime.now().isBefore(deadline) && !completer.isCompleted) {
        try {
          final isChallenge =
              await c.evaluateJavascript(source: CfSession.challengeProbeJs);
          if (isChallenge == true) {
            // Managed challenges clear themselves in a few seconds.
            challengeSeen = true;
            stillChallenge = true;
            challengeAttempts++;
            // If the challenge does not auto-resolve in ~6 seconds (9 attempts * 700ms),
            // it is an interactive Turnstile / human check requiring user interaction.
            if (challengeAttempts >= 9) {
              CfDiag.log(
                'headless interactive challenge detected ($challengeAttempts attempts) -> requesting user verification',
              );
              finish(_needsVerification(url));
              return;
            }
            await Future<void>.delayed(const Duration(milliseconds: 700));
            continue;
          }
          stillChallenge = false;
          challengeAttempts = 0;

          // Fast check: if expected pages are known and already rendered, exit immediately
          pages = await readUrls(c);
          if (expected == 0) {
            final e = await c.evaluateJavascript(
              source: WebScraper.expectedPagesJs,
            );
            if (e is num) expected = e.toInt();
          }
          if (expected > 0 && pages.length >= expected) break;

          await c.evaluateJavascript(source: WebScraper.stripAdsJs);
          final atBottom =
              await c.evaluateJavascript(source: WebScraper.scrollStepJs);
          await Future<void>.delayed(const Duration(milliseconds: 220));

          pages = await readUrls(c);
          if (expected == 0) {
            final e = await c.evaluateJavascript(
              source: WebScraper.expectedPagesJs,
            );
            if (e is num) expected = e.toInt();
          }
          if (atBottom == true) bottom = true;

          if (pages.length == lastCount) {
            stable++;
          } else {
            stable = 0;
            lastCount = pages.length;
          }

          final complete = expected > 0 && pages.length >= expected;
          if (pages.length >= 2 &&
              (complete ||
                  (bottom && stable >= 2) ||
                  (pages.length >= 8 && stable >= 2))) {
            break;
          }
        } catch (_) {
          // Navigation / reload in progress; try again.
          await Future<void>.delayed(const Duration(milliseconds: 220));
        }
      }

      if (completer.isCompleted) return;

      if ((stillChallenge || challengeSeen) && pages.length < 2) {
        finish(_needsVerification(url));
        return;
      }

      if (pages.length < 2) {
        try {
          final title = (await c.getTitle() ?? '').toLowerCase();
          if (title.contains('moment') ||
              title.contains('cloudflare') ||
              title.contains('human') ||
              title.contains('attention')) {
            finish(_needsVerification(url));
            return;
          }
        } catch (_) {}
      }

      try {
        // Readers that draw pages on <canvas> (comix.to unscrambles its
        // images there; the raw image URLs are scrambled AND hotlink
        // protected) have the correct pictures only in the canvases:
        // snapshot those to files. Prefer them whenever they cover at least
        // as many pages as the URL scan found.
        final rendered = await _captureRendered(c, url, atLeast: pages.length);
        if (rendered.length >= 2) {
          CfDiag.log(
            'using ${rendered.length} rendered pages (urls=${pages.length})',
          );
          pages = rendered;
        }

        final nav = await c.evaluateJavascript(
          source: WebScraper.extractNavigationJs,
        );
        final metaCover = await c.evaluateJavascript(
          source: WebScraper.extractCoverJs,
        );
        final finalTitle = await c.getTitle();

        String? nextUrl;
        String? prevUrl;
        final availableChapters = <ChapterRef>[];
        if (nav is Map) {
          nextUrl = nav['next']?.toString();
          prevUrl = nav['prev']?.toString();
          final chList = nav['chapters'];
          if (chList is List) {
            for (final ch in chList) {
              if (ch is Map && ch['url'] != null && ch['label'] != null) {
                availableChapters.add(
                  ChapterRef(
                    url: ch['url'].toString(),
                    label: ch['label'].toString(),
                  ),
                );
              }
            }
          }
        }

        // Page passed Cloudflare -> remember its cookies for image requests.
        await CfSession.primeAll(url, pages);

        CfDiag.log('headless done ${uri.host} pages=${pages.length}');
        finish(
          ScrapedChapterResult(
            chapterUrl: url,
            pages: pages,
            title: finalTitle != null ? UrlTools.cleanTitle(finalTitle) : null,
            chapterLabel: UrlTools.chapterLabel(url),
            nextChapterUrl: nextUrl ?? UrlTools.stepChapter(url, 1),
            prevChapterUrl: prevUrl ?? UrlTools.stepChapter(url, -1),
            nextGuessed: nextUrl == null,
            isWebtoon: pages.length >= 2,
            availableChapters: availableChapters,
            coverUrl: metaCover is String && metaCover.startsWith('http')
                ? metaCover
                : null,
          ),
        );
      } catch (e) {
        CfDiag.log('headless extract error $e');
        finish(ScrapedChapterResult(chapterUrl: url, pages: const []));
      }
    }

    headless = HeadlessInAppWebView(
      initialSize: const Size(1080, 1920),
      initialUrlRequest: URLRequest(url: WebUri(url)),
      initialSettings: settings,
      onProgressChanged: (controller, progress) async {
        if (completer.isCompleted || started) return;
        if (progress >= 75) {
          started = true;
          CfDiag.log('headless progress $progress% on ${uri.host} -> starting extraction');
          await runExtraction(controller);
        }
      },
      onLoadStop: (controller, loadedUrl) async {
        if (completer.isCompleted || started) return;
        started = true;
        CfDiag.log('headless loaded ${uri.host} -> polling');
        await runExtraction(controller);
      },
      onReceivedError: (controller, request, error) {
        // Only abort if the main web page itself failed to load
        if (request.isForMainFrame == true && !started && !challengeSeen) {
          finish(ScrapedChapterResult(chapterUrl: url, pages: const []));
        }
      },
    );

    await headless!.run();

    // Fast-start fallback timer: don't wait for slow tracking scripts to finish!
    Timer(const Duration(milliseconds: 2800), () async {
      if (!completer.isCompleted && !started && headless != null) {
        final c = headless!.webViewController;
        if (c != null) {
          started = true;
          CfDiag.log('headless fallback timer triggered on ${uri.host}');
          await runExtraction(c);
        }
      }
    });

    quietTimer = Timer(const Duration(seconds: 18), () {
      if (!completer.isCompleted) finish(_needsVerification(url));
    });

    return completer.future.timeout(
      const Duration(seconds: 20),
      onTimeout: () {
        CfDiag.log('headless timeout challengeSeen=$challengeSeen $url');
        final r = _needsVerification(url);
        finish(r);
        return r;
      },
    );
  }

  /// Snapshots canvas / blob: images to files and returns `file://` URLs.
  /// (CfFileService serves those straight from disk, so the reader needs no
  /// special handling.)
  Future<List<String>> _captureRendered(
    InAppWebViewController c,
    String url, {
    int atLeast = 0,
  }) async {
    final out = <String>[];
    try {
      final count = await c.evaluateJavascript(
        source: WebScraper.collectRenderedJs,
      );
      final n = count is num ? count.toInt() : 0;
      if (n < 2 || n < atLeast) return out;

      final base = await getApplicationSupportDirectory();
      final dir = Directory('${base.path}/rendered');
      if (!await dir.exists()) await dir.create(recursive: true);
      final key = _hashKey(url);

      for (var i = 0; i < n; i++) {
        final data = await c.evaluateJavascript(
          source: 'window.__smPages && window.__smPages[$i]',
        );
        if (data is! String) continue;
        final comma = data.indexOf(',');
        if (comma < 0) continue;
        final bytes = base64Decode(data.substring(comma + 1));
        final file = File('${dir.path}/${key}_${i.toString().padLeft(3, '0')}.jpg');
        await file.writeAsBytes(bytes);
        out.add(file.uri.toString());
      }
      await c.evaluateJavascript(source: 'window.__smPages = null;');
    } catch (e) {
      CfDiag.log('capture rendered failed: $e');
    }
    return out;
  }

  static String _hashKey(String s) {
    var h = 0x811c9dc5;
    for (final b in utf8.encode(s)) {
      h = ((h ^ b) * 0x01000193) & 0xFFFFFFFF;
    }
    return h.toRadixString(16).padLeft(8, '0');
  }
}
