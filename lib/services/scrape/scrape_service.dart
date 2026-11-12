import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/widgets.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:html/dom.dart' as dom;
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

import '../../core/url_tools.dart';
import '../web_scraper.dart';
import 'cf_session.dart';
import 'generic_site_adapter.dart';
import 'scrape_cache.dart';
import 'site_adapter.dart';

class ScrapeService {
  ScrapeService({http.Client? client}) : _client = client ?? http.Client();

  final http.Client _client;
  final List<SiteAdapter> _adapters = [const GenericSiteAdapter()];

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
        CfDiag.log(
            'cache hit ${Uri.tryParse(url)?.host} pages=${cached.pages.length}');
        await CfSession.primeAll(url, cached.pages);
        return cached;
      }
    }

    final result = await _scrapeChapter(url);
    if (result.pages.length >= 2 && !result.needsVerification) {
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
    final isLatestInCatalogue = chapters.isNotEmpty &&
        GenericSiteAdapter.isCatalogueLatest(chapters, url);
    final nextGuessed = !isLatestInCatalogue && nextUrl == null;
    final nextChapterUrl =
        isLatestInCatalogue ? null : (nextUrl ?? UrlTools.stepChapter(url, 1));
    final prevChapterUrl = prevUrl ?? UrlTools.stepChapter(url, -1);
    final result = ScrapedChapterResult(
      chapterUrl: url,
      pages: pages,
      title: title != null ? UrlTools.cleanTitle(title) : null,
      chapterLabel: UrlTools.chapterLabel(url),
      nextChapterUrl: nextChapterUrl,
      prevChapterUrl: prevChapterUrl,
      nextGuessed: nextGuessed,
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

        if (response.statusCode == 404) {
          CfDiag.log('http 404 ${uri.host} -> chapter does not exist');
          return ScrapedChapterResult(
            chapterUrl: url,
            pages: const [],
            chapterLabel: UrlTools.chapterLabel(url),
          );
        } else if (CfSession.isChallengeResponse(
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
            return result; // Fast path succeeded! Return immediately.
          } else {
            // Series overview page? Auto-hop to the first available chapter
            // ONLY if the incoming URL is not already a chapter URL!
            final isAlreadyChapter = UrlTools.chapterLabel(url) != null;
            if (!isAlreadyChapter) {
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
          }
        } else if (response.statusCode == 403 || response.statusCode == 503) {
          if (CfSession.isChallengeResponse(
            response.statusCode,
            response.headers,
            response.body,
          )) {
            CfSession.webViewOnlyHosts.add(uri.host);
          }
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
      final isAlreadyChapter = UrlTools.chapterLabel(url) != null;
      if (!isAlreadyChapter) {
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
      }
    } catch (e) {
      CfDiag.log('rendered path failed ${uri.host}: $e');
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

    var currentPages = <String>[];

    void finish(ScrapedChapterResult r) {
      if (!completer.isCompleted) completer.complete(r);
      quietTimer?.cancel();
      final h = headless;
      headless = null;
      h?.dispose();
    }

    final settings = CfSession.webViewSettings(
      contentBlockers: null,
    );

    /// Reads the current list of page image URLs from the live DOM / React state.
    Future<List<String>> readUrls(InAppWebViewController c) async {
      try {
        final apiRes = await c.callAsyncJavaScript(
          functionBody: r'''
            try {
              // 1. Direct query of React Query Cache / Fiber for SPA readers (comix.to etc.)
              var els = [
                document.querySelector('.rpage-main'),
                document.querySelector('.rpage'),
                document.querySelector('#app-root'),
                document.querySelector('.rpage-page')
              ].filter(Boolean);

              for (var ei = 0; ei < els.length; ei++) {
                var el = els[ei];
                for (var k in el) {
                  if (k.startsWith('__reactFiber') || k.startsWith('__reactContainer')) {
                    var fiber = el[k];
                    if (fiber && fiber.current) fiber = fiber.current;
                    var root = fiber;
                    while (root && root.return) root = root.return;
                    var stack = [root];
                    var count = 0;
                    while (stack.length > 0 && count < 2500) {
                      count++;
                      var f = stack.pop();
                      if (!f) continue;
                      var hook = f.memoizedState;
                      while (hook) {
                        var state = hook.memoizedState;
                        if (state) {
                          var cand = state.data || state;
                          if (cand && Array.isArray(cand.iT) && cand.iT.length >= 2) {
                            return cand.iT.map(function(item) {
                              return (item && (item.H$ || item.url || item.src)) || '';
                            }).filter(function(u) { return typeof u === 'string' && u.startsWith('http'); });
                          }
                        }
                        hook = hook.next;
                      }
                      if (f.memoizedProps) {
                        if (f.memoizedProps.client && typeof f.memoizedProps.client.getQueryCache === 'function') {
                          var queries = f.memoizedProps.client.getQueryCache().getAll();
                          for (var qi = 0; qi < queries.length; qi++) {
                            var qd = queries[qi].state && queries[qi].state.data;
                            if (qd && Array.isArray(qd.iT) && qd.iT.length >= 2) {
                              return qd.iT.map(function(item) {
                                return (item && (item.H$ || item.url || item.src)) || '';
                              }).filter(function(u) { return typeof u === 'string' && u.startsWith('http'); });
                            }
                          }
                        }
                      }
                      if (f.child) stack.push(f.child);
                      if (f.sibling) stack.push(f.sibling);
                    }
                  }
                }
              }

              // 2. Initial data fallback
              var init = document.getElementById('initial-data');
              if (init && init.textContent) {
                var d = JSON.parse(init.textContent);
                var chapId = d.read && d.read.chapterId;
                if (chapId) {
                  var resp = await fetch('/api/v1/chapters/' + chapId, {
                    headers: { 'Accept': 'application/json', 'X-Requested-With': 'XMLHttpRequest' }
                  });
                  if (resp.ok) {
                    var json = await resp.json();
                    var data = json.data || json;
                    var list = data.iT || data.images || data.pages;
                    if (Array.isArray(list) && list.length >= 2) {
                      return list.map(function(item) {
                        return (item && (item.H$ || item.url || item.src || (typeof item === 'string' ? item : null))) || '';
                      }).filter(function(u) { return u && u.indexOf('http') === 0; });
                    }
                  }
                }
              }
            } catch(e) {}
            return null;
          ''',
        );
        if (apiRes?.value is List) {
          final list = (apiRes!.value as List)
              .map((e) => e?.toString())
              .whereType<String>()
              .where((u) => u.startsWith('http'))
              .toList();
          if (list.length >= 2) return list;
        }
      } catch (_) {}

      final res =
          await c.evaluateJavascript(source: WebScraper.extractImagesJs);
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
      // Long chapters (100+ pages, canvas readers that draw slowly) need far
      // more than 18s. We stop on progress/idleness, not on a short clock.
      final deadline = DateTime.now().add(const Duration(seconds: 150));
      var pages = <String>[];
      var captured = 0; // pages snapshotted from canvases so far
      var totalHint = 0; // real page count (from reader state), 0 = unknown
      var lastProgress = -1;
      var idle = 0;
      var passes = 0;
      var tick = 0;
      var stillChallenge = false;
      var challengeAttempts = 0;
      // Paged-reader state: how many consecutive advance key presses fired
      // with no new captured frame. Used to avoid oscillating fwd/back.
      var advanceStreak = 0;

      // Reset canvas capture counters so a fresh scrape never inherits stale
      // state from a previous run on the same WebView instance.
      await c.evaluateJavascript(
        source:
            'window.__smMap = null; window.__smSigs = null; window.__smSeq = 0;',
      );

      while (DateTime.now().isBefore(deadline) && !completer.isCompleted) {
        try {
          final isChallenge =
              await c.evaluateJavascript(source: CfSession.challengeProbeJs);
          if (isChallenge == true) {
            challengeSeen = true;
            stillChallenge = true;
            challengeAttempts++;
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

          await c.evaluateJavascript(source: WebScraper.stripAdsJs);

          // For paged canvas readers (comix.to etc.) the image list API
          // returns 0 URLs — images are drawn on <canvas> after unscrambling.
          // Extract the real total page count from React state separately so
          // the loop knows when it is done even when readUrls() is empty.
          if (totalHint == 0) {
            final tp =
                await c.evaluateJavascript(source: _totalPageJs);
            if (tp is num && tp > 0) {
              totalHint = tp.toInt();
              CfDiag.log('totalPage from React state: $totalHint');
            }
          }

          // Real total only from the reader's own state (NOT the DOM count,
          // which is just the few pages a virtualised reader has mounted).
          pages = await readUrls(c);
          if (pages.length >= 2) {
            currentPages = pages;
            if (pages.length > totalHint) totalHint = pages.length;
          }

          // Snapshot whatever canvases are mounted RIGHT NOW. Virtualised
          // readers unmount pages that scroll away, so we must collect while
          // scrolling instead of once at the end.
          final cap = await c.evaluateJavascript(source: _captureStepJs);
          if (cap is num) captured = cap.toInt();

          if (totalHint > 0 && captured >= totalHint) break;

          final atBottom =
              await c.evaluateJavascript(source: WebScraper.scrollStepJs);

          // Paged readers (comix.to) ignore scrolling — pages only render
          // when the reader advances. When scrolling brings nothing new, press
          // the reader's own navigation key.
          //
          // FIX: always go FORWARD (ArrowRight). The old formula alternated
          // ArrowLeft every 3rd idle tick which reversed progress and caused
          // the "only 5 pages then black" bug. Only fall back to ArrowLeft
          // after an extended streak with zero captures (indicates we may have
          // overshot the last page and need to step back once).
          if (idle >= 2) {
            final goBack = advanceStreak >= 12;
            final dir = goBack ? 'ArrowLeft' : 'ArrowRight';
            final moved = await c.evaluateJavascript(
              source: _advanceJs.replaceAll('__KEY__', dir),
            );
            if (moved == 'navigated') {
              CfDiag.log('reader navigated away while advancing -> stop');
              await c.evaluateJavascript(source: 'history.back();');
              await Future<void>.delayed(const Duration(milliseconds: 900));
              await c.evaluateJavascript(source: _captureStepJs);
              break;
            }
            advanceStreak++;
            // Give the reader time to unscramble and paint the new page.
            // 700ms grace prevents capturing a blank/mid-draw canvas and
            // also prevents double-advancing before the first page settles.
            await Future<void>.delayed(const Duration(milliseconds: 700));
          } else {
            await Future<void>.delayed(const Duration(milliseconds: 300));
          }

          final progress = captured > pages.length ? captured : pages.length;
          if (progress == lastProgress) {
            idle++;
          } else {
            idle = 0;
            advanceStreak = 0;
            lastProgress = progress;
          }
          tick++;
          if (tick == 3 || tick % 20 == 0) {
            CfDiag.log(
                'scan tick=$tick captured=$captured urls=${pages.length} '
                'hint=$totalHint idle=$idle streak=$advanceStreak '
                'bottom=$atBottom probe='
                '${await c.evaluateJavascript(source: _probeJs)}');
          }

          if (atBottom == true && idle >= 6) {
            if (totalHint > 0 &&
                captured > 0 &&
                captured < totalHint &&
                passes < 2) {
              passes++;
              idle = 0;
              advanceStreak = 0;
              await c.evaluateJavascript(source: _scrollTopJs);
              await Future<void>.delayed(const Duration(milliseconds: 600));
              continue;
            }
            if (progress >= 2) break;
          }
          // No new page for ~10s of advance attempts: done or reader exhausted.
          if (idle >= 25 && progress >= 2) break;
        } catch (_) {
          await Future<void>.delayed(const Duration(milliseconds: 300));
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
          if (title.contains('404') ||
              title.contains('not found') ||
              title.contains('page not found') ||
              title.contains("doesn't exist")) {
            CfDiag.log('headless page is 404/not found: $url');
            finish(ScrapedChapterResult(chapterUrl: url, pages: const []));
            return;
          }
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
        await c.evaluateJavascript(source: _captureStepJs); // final sweep
        final rendered = await _captureRendered(c, url, atLeast: pages.length);
        if (rendered.length >= 2 && rendered.length >= pages.length) {
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
        bool isLatest = false;
        final availableChapters = <ChapterRef>[];
        if (nav is Map) {
          nextUrl = nav['next']?.toString();
          prevUrl = nav['prev']?.toString();
          isLatest = nav['isLatest'] == true;
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

        final isLatestInCatalogue = isLatest ||
            (availableChapters.isNotEmpty &&
                GenericSiteAdapter.isCatalogueLatest(availableChapters, url));

        final nextGuessed = !isLatestInCatalogue && nextUrl == null;
        final nextChapterUrl = isLatestInCatalogue
            ? null
            : (nextUrl ?? UrlTools.stepChapter(url, 1));
        final prevChapterUrl = prevUrl ?? UrlTools.stepChapter(url, -1);

        // Page passed Cloudflare -> remember its cookies for image requests.
        await CfSession.primeAll(url, pages);

        String? resolvedTitle =
            finalTitle != null ? UrlTools.cleanTitle(finalTitle) : null;
        if (resolvedTitle == null ||
            resolvedTitle.isEmpty ||
            RegExp(r'^\d+$').hasMatch(resolvedTitle.replaceAll(RegExp(r'\s+'), ''))) {
          final fromUrl = UrlTools.titleFromUrl(url);
          if (fromUrl.isNotEmpty) resolvedTitle = fromUrl;
        }

        CfDiag.log('headless done ${uri.host} pages=${pages.length} title="$resolvedTitle"');
        finish(
          ScrapedChapterResult(
            chapterUrl: url,
            pages: pages,
            title: resolvedTitle,
            chapterLabel: UrlTools.chapterLabel(url),
            nextChapterUrl: nextChapterUrl,
            prevChapterUrl: prevChapterUrl,
            nextGuessed: nextGuessed,
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
          CfDiag.log(
              'headless progress $progress% on ${uri.host} -> starting extraction');
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
      onReceivedHttpError: (controller, request, errorResponse) {
        if (request.isForMainFrame == true &&
            errorResponse.statusCode == 404 &&
            !challengeSeen) {
          CfDiag.log('headless HTTP 404 for $url');
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

    // Hard backstop only. The extraction loop has its own progress-based
    // stop (idle / 150s); the old 18s/20s cut-offs threw away long chapters.
    quietTimer = Timer(const Duration(seconds: 200), () {
      if (!completer.isCompleted) {
        finish(currentPages.length >= 2
            ? ScrapedChapterResult(
                chapterUrl: url,
                pages: currentPages,
                chapterLabel: UrlTools.chapterLabel(url),
              )
            : (challengeSeen
                ? _needsVerification(url)
                : ScrapedChapterResult(chapterUrl: url, pages: const [])));
      }
    });

    return completer.future.timeout(
      const Duration(seconds: 210),
      onTimeout: () {
        CfDiag.log('headless timeout challengeSeen=$challengeSeen $url');
        final r = challengeSeen
            ? _needsVerification(url)
            : (currentPages.length >= 2
                ? ScrapedChapterResult(
                    chapterUrl: url,
                    pages: currentPages,
                    chapterLabel: UrlTools.chapterLabel(url),
                  )
                : ScrapedChapterResult(chapterUrl: url, pages: const []));
        finish(r);
        return r;
      },
    );
  }

  /// Incremental snapshot: stores every mounted, drawn canvas / blob image in
  /// `window.__smMap` (keyed by its page index, else a content-hash key so
  /// paged readers that reuse the same canvas position still get distinct
  /// entries) and returns how many distinct pages have been collected so far.
  static const String _captureStepJs = r"""
(function() {
  try {
    var map = window.__smMap || (window.__smMap = {});
    var sigs = window.__smSigs || (window.__smSigs = {});
    var pageSeq = window.__smSeq || (window.__smSeq = 0);
    var els = document.querySelectorAll('canvas, img[src^="blob:"], .rpage-page__img, .rpage-page img');
    function pad(n) { n = String(Math.max(0, n)); while (n.length < 9) n = '0' + n; return n; }
    for (var i = 0; i < els.length; i++) {
      var el = els[i];
      var isCanvas = el.tagName === 'CANVAS';
      var w = isCanvas ? el.width : (el.naturalWidth || 0);
      var h = isCanvas ? el.height : (el.naturalHeight || 0);
      if (!w || !h || w < 200 || h < 200) continue;
      if (!isCanvas && !el.complete) continue;
      try {
        var c = el;
        if (!isCanvas) {
          c = document.createElement('canvas');
          c.width = w; c.height = h;
          c.getContext('2d').drawImage(el, 0, 0);
        } else {
          // Skip canvases that are not drawn yet (mostly transparent).
          // Use a 16x16 sample and require >=60% painted so we accept
          // partially-unscrambled tiles (comix.to unscrambles progressively).
          var t = document.createElement('canvas');
          t.width = 16; t.height = 16;
          var tc = t.getContext('2d');
          tc.drawImage(el, 0, 0, 16, 16);
          var px = tc.getImageData(0, 0, 16, 16).data, painted = 0;
          for (var j = 3; j < px.length; j += 4) { if (px[j] > 10) painted++; }
          if (painted < 256 * 0.60) continue;
        }

        // Compute a content-fingerprint so paged readers that reuse the same
        // canvas DOM node (always at the same scroll position) still produce
        // distinct map entries for each page they display.
        var thumb = document.createElement('canvas');
        thumb.width = 8; thumb.height = 8;
        thumb.getContext('2d').drawImage(c, 0, 0, 8, 8);
        var thumbData = thumb.getContext('2d').getImageData(0, 0, 8, 8).data;
        var hash = 0;
        for (var hi = 0; hi < thumbData.length; hi += 4) {
          hash = ((hash * 31) + thumbData[hi] + thumbData[hi+1] + thumbData[hi+2]) | 0;
        }
        var sig = w + 'x' + h + ':' + hash;
        if (sigs[sig]) continue;   // exact same visual content already stored
        sigs[sig] = 1;

        // Key: prefer [data-page] attribute; fall back to seq# so paged
        // readers (same Y every time) still get unique keys.
        var key = null;
        var holder = el.closest ? el.closest('[data-page]') : null;
        var dp = holder ? parseInt(holder.getAttribute('data-page')) : NaN;
        if (!isNaN(dp)) {
          key = 'p' + pad(dp);
          if (map[key]) continue; // already captured this [data-page]
        } else {
          // Use sequence counter so the same canvas position gets different keys
          key = 'q' + pad(pageSeq++);
          window.__smSeq = pageSeq;
        }

        var f = document.createElement('canvas');
        f.width = c.width; f.height = c.height;
        var fc = f.getContext('2d');
        fc.fillStyle = '#fff'; fc.fillRect(0, 0, f.width, f.height);
        fc.drawImage(c, 0, 0);
        var d = f.toDataURL('image/jpeg', 0.92);
        map[key] = d;
      } catch (e) {}
    }
    return Object.keys(map).length;
  } catch (e) { return 0; }
})();
""";

  /// Presses a navigation key the way a reader expects; reports 'navigated'
  /// if that changed the page URL (i.e. we left the chapter).
  /// Clicks the canvas/reader area first to ensure keyboard focus, and
  /// also tries any visible next/prev button the reader provides.
  static const String _advanceJs = r"""
(function() {
  try {
    var before = location.pathname;
    var key = '__KEY__';
    var goNext = key === 'ArrowRight';
    var code = goNext ? 39 : 37;

    // 1. Try clicking the reader's own next/prev UI button (most reliable).
    var btnSelectors = goNext
      ? ['[class*="next-btn"]','[class*="btn-next"]','[class*="nextBtn"]',
         '[class*="next-page"]','[class*="page-next"]','.rpage-btn--next',
         'button[class*="next"]','button[class*="right"]',
         '[aria-label*="next" i]','[title*="next" i]']
      : ['[class*="prev-btn"]','[class*="btn-prev"]','[class*="prevBtn"]',
         '[class*="prev-page"]','[class*="page-prev"]','.rpage-btn--prev',
         'button[class*="prev"]','button[class*="left"]',
         '[aria-label*="prev" i]','[title*="prev" i]'];
    for (var si = 0; si < btnSelectors.length; si++) {
      var btn = document.querySelector(btnSelectors[si]);
      if (btn) { btn.click(); break; }
    }

    // 2. Click the canvas / reader container to give it keyboard focus.
    var reader = document.querySelector('.rpage-main, .rpage, [class*="reader-wrap"], [class*="reader-container"]');
    if (reader) reader.click();
    var canvas = document.querySelector('canvas');
    if (canvas) canvas.click();

    // 3. Dispatch keyboard events on every likely target.
    var targets = [document.activeElement, document, window, document.body];
    ['keydown', 'keyup'].forEach(function(type) {
      targets.forEach(function(t) {
        if (!t) return;
        try {
          t.dispatchEvent(new KeyboardEvent(type, {
            key: key, code: key, keyCode: code, which: code,
            bubbles: true, cancelable: true
          }));
        } catch (e) {}
      });
    });

    if (location.pathname !== before) return 'navigated';
    return 'ok';
  } catch (e) { return 'err'; }
})();
""";

  /// Extracts the real total page count from the reader's React / query state.
  /// Works for paged canvas readers (comix.to, etc.) where readUrls() returns
  /// zero because all images are drawn on <canvas> after unscrambling.
  static const String _totalPageJs = r"""
(function() {
  try {
    var roots = document.querySelectorAll(
      '.rpage-main, .rpage, #app-root, [class*="reader"], [class*="chapter"]');
    for (var ri = 0; ri < roots.length; ri++) {
      var el = roots[ri];
      for (var k in el) {
        if (!k.startsWith('__reactFiber') && !k.startsWith('__reactContainer')) continue;
        var fiber = el[k];
        if (fiber && fiber.current) fiber = fiber.current;
        var stack = [fiber];
        var count = 0;
        while (stack.length > 0 && count < 3000) {
          count++;
          var f = stack.pop();
          if (!f) continue;
          var hook = f.memoizedState;
          while (hook) {
            var s = hook.memoizedState;
            if (s && typeof s === 'object') {
              if (typeof s.totalPage === 'number' && s.totalPage > 1) return s.totalPage;
              if (typeof s.total_page === 'number' && s.total_page > 1) return s.total_page;
              if (s.data) {
                if (typeof s.data.totalPage === 'number' && s.data.totalPage > 1) return s.data.totalPage;
                if (typeof s.data.total_page === 'number' && s.data.total_page > 1) return s.data.total_page;
              }
            }
            hook = hook.next;
          }
          var props = f.memoizedProps;
          if (props && props.client && typeof props.client.getQueryCache === 'function') {
            try {
              var queries = props.client.getQueryCache().getAll();
              for (var qi = 0; qi < queries.length; qi++) {
                var d = queries[qi].state && queries[qi].state.data;
                if (!d) continue;
                if (typeof d.totalPage === 'number' && d.totalPage > 1) return d.totalPage;
                if (typeof d.total_page === 'number' && d.total_page > 1) return d.total_page;
              }
            } catch(e) {}
          }
          if (f.child) stack.push(f.child);
          if (f.sibling) stack.push(f.sibling);
        }
      }
    }
    // Fallback: comix.to embeds chapter info in a #initial-data script tag
    var init = document.getElementById('initial-data');
    if (init) {
      try {
        var d = JSON.parse(init.textContent);
        var tp = (d.read && d.read.totalPage) || (d.chapter && d.chapter.totalPage);
        if (typeof tp === 'number' && tp > 1) return tp;
      } catch(e) {}
    }
  } catch(e) {}
  return 0;
})();
""";

  /// Small DOM summary for the diagnostics log.
  static const String _probeJs = r"""
(function() {
  try {
    return JSON.stringify({
      canvas: document.querySelectorAll('canvas').length,
      rpage: document.querySelectorAll('.rpage-page').length,
      img: document.querySelectorAll('img').length,
      dp: Array.prototype.map.call(document.querySelectorAll('[data-page]'), function(e) { return e.getAttribute('data-page'); }).slice(0, 12),
      path: location.pathname.slice(-40),
      sh: (document.scrollingElement || document.documentElement).scrollHeight
    });
  } catch (e) { return 'err'; }
})();
""";

  static const String _scrollTopJs = r"""
(function() {
  try {
    var root = document.scrollingElement || document.documentElement;
    root.scrollTop = 0;
    var all = document.querySelectorAll('div, main, section');
    for (var i = 0; i < all.length && i < 2500; i++) {
      if (all[i].scrollTop > 0) all[i].scrollTop = 0;
    }
  } catch (e) {}
  return true;
})();
""";

  /// Writes the collected snapshots to files and returns `file://` URLs
  /// (CfFileService serves those straight from disk).
  Future<List<String>> _captureRendered(
    InAppWebViewController c,
    String url, {
    int atLeast = 0,
  }) async {
    final out = <String>[];
    try {
      final count = await c.evaluateJavascript(
        source: r"""
(function() {
  var m = window.__smMap || {};
  window.__smPages = Object.keys(m).sort().map(function(k) { return m[k]; });
  return window.__smPages.length;
})();
""",
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
        final file =
            File('${dir.path}/${key}_${i.toString().padLeft(3, '0')}.jpg');
        await file.writeAsBytes(bytes);
        out.add(file.uri.toString());
      }
      await c.evaluateJavascript(
          source:
              'window.__smPages = null; window.__smMap = null; window.__smSigs = null;');
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
