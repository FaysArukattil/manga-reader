import 'dart:async';
import 'package:flutter/widgets.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:html/dom.dart' as dom;
import 'package:http/http.dart' as http;

import '../../core/url_tools.dart';
import '../../ui/ad_block.dart';
import '../web_scraper.dart';
import 'cf_session.dart';
import 'generic_site_adapter.dart';
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
  /// The user is only asked to verify manually if the headless WebView could
  /// not get past Cloudflare on its own.
  Future<ScrapedChapterResult> scrapeChapter(String url) async {
    final result = await _scrapeChapter(url);
    if (result.pages.isNotEmpty) {
      // Make cf_clearance + UA available to image downloads.
      await CfSession.primeAll(url, result.pages.take(3));
    }
    return result;
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
            .timeout(const Duration(seconds: 6));

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
            return result; // Fast path succeeded!
          } else {
            // Series overview page? Auto-hop to the first available chapter.
            final targetUrl = result.firstChapterUrl ??
                (result.availableChapters.isNotEmpty
                    ? _pickStartingChapter(result.availableChapters, url)?.url
                    : null);

            if (targetUrl != null && targetUrl != url) {
              final chRes = await _scrapeChapter(targetUrl);
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
        final chRes = await _scrapeChapter(targetUrl);
        if (chRes.pages.length >= 2 || chRes.needsVerification) {
          return chRes.copyWith(
            availableChapters: rendered.availableChapters.isNotEmpty
                ? rendered.availableChapters
                : chRes.availableChapters,
            coverUrl: rendered.coverUrl ?? chRes.coverUrl,
          );
        }
      }
    } catch (_) {}

    // Fallback: return best effort or stepChapter
    return ScrapedChapterResult(
      chapterUrl: url,
      pages: const [],
      chapterLabel: UrlTools.chapterLabel(url),
      nextChapterUrl: UrlTools.stepChapter(url, 1),
      prevChapterUrl: UrlTools.stepChapter(url, -1),
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
    var challengeSeen = false;
    Timer? quietTimer;

    void finish(ScrapedChapterResult r) {
      if (!completer.isCompleted) completer.complete(r);
      quietTimer?.cancel();
      final h = headless;
      headless = null;
      h?.dispose();
    }

    // NOTE: no custom userAgent here on purpose -> the WebView's own UA, which
    // matches what Cloudflare sees from the verification screen.
    final settings = InAppWebViewSettings(
      javaScriptEnabled: true,
      domStorageEnabled: true,
      thirdPartyCookiesEnabled: true,
      javaScriptCanOpenWindowsAutomatically: false,
      mediaPlaybackRequiresUserGesture: true,
      mixedContentMode: MixedContentMode.MIXED_CONTENT_COMPATIBILITY_MODE,
      useHybridComposition: true,
      contentBlockers: buildContentBlockers(),
    );

    headless = HeadlessInAppWebView(
      initialSize: const Size(1080, 1920),
      initialUrlRequest: URLRequest(url: WebUri(url)),
      initialSettings: settings,
      onLoadStop: (controller, loadedUrl) async {
        if (completer.isCompleted) return;
        try {
          final isChallenge = await controller.evaluateJavascript(
            source: CfSession.challengeProbeJs,
          );

          if (isChallenge == true) {
            // Cloudflare "managed" challenges solve themselves in a few
            // seconds and then reload the page (-> onLoadStop fires again).
            // Do NOT give up here; just wait. The overall timeout below
            // decides when to ask the user.
            challengeSeen = true;
            return;
          }

          // 1. Strip ads & popups
          await controller.evaluateJavascript(source: WebScraper.stripAdsJs);

          // 2. Trigger lazy loaders with dynamic scroll
          await controller.evaluateJavascript(
            source:
                '(function(){window.scrollTo(0, document.body.scrollHeight/2); setTimeout(function(){window.scrollTo(0, document.body.scrollHeight); setTimeout(function(){window.scrollTo(0,0);}, 250);}, 250);})()',
          );
          await Future<void>.delayed(const Duration(milliseconds: 700));

          // 3. Extract images and chapter navigation
          final res = await controller.evaluateJavascript(
            source: WebScraper.extractImagesJs,
          );
          final nav = await controller.evaluateJavascript(
            source: WebScraper.extractNavigationJs,
          );
          final finalTitle = await controller.getTitle();

          final pages = <String>[];
          if (res is List) {
            for (final p in res) {
              if (p != null && p.toString().isNotEmpty) {
                pages.add(p.toString());
              }
            }
          }

          if (pages.isEmpty) {
            // Still an interstitial that appeared late? (strict probe only;
            // the word "Cloudflare" in a footer must NOT count.)
            final again = await controller.evaluateJavascript(
              source: CfSession.challengeProbeJs,
            );
            if (again == true) {
              challengeSeen = true;
              return;
            }
          }

          String? nextUrl;
          String? prevUrl;
          final availableChapters = <ChapterRef>[];

          if (nav is Map) {
            nextUrl = nav['next']?.toString();
            prevUrl = nav['prev']?.toString();
            final chList = nav['chapters'];
            if (chList is List) {
              for (final c in chList) {
                if (c is Map && c['url'] != null && c['label'] != null) {
                  availableChapters.add(
                    ChapterRef(
                      url: c['url'].toString(),
                      label: c['label'].toString(),
                    ),
                  );
                }
              }
            }
          }

          // Page passed Cloudflare -> remember its cookies for image requests.
          await CfSession.primeCookies(url);

          finish(
            ScrapedChapterResult(
              chapterUrl: url,
              pages: pages,
              title:
                  finalTitle != null ? UrlTools.cleanTitle(finalTitle) : null,
              chapterLabel: UrlTools.chapterLabel(url),
              nextChapterUrl: nextUrl ?? UrlTools.stepChapter(url, 1),
              prevChapterUrl: prevUrl ?? UrlTools.stepChapter(url, -1),
              isWebtoon: pages.length >= 2,
              availableChapters: availableChapters,
            ),
          );
        } catch (e) {
          finish(ScrapedChapterResult(chapterUrl: url, pages: const []));
        }
      },
      onReceivedError: (controller, request, error) {
        // Only abort if the main web page itself failed to load
        if (request.isForMainFrame == true && !challengeSeen) {
          finish(ScrapedChapterResult(chapterUrl: url, pages: const []));
        }
      },
    );

    await headless!.run();

    // Page never finished loading and no challenge was recognised: hand over
    // to the visible verification screen instead of hanging.
    quietTimer = Timer(const Duration(seconds: 15), () {
      if (!challengeSeen) finish(_needsVerification(url));
    });

    // A challenge got 30s to clear on its own; after that the user is asked.
    return completer.future.timeout(
      const Duration(seconds: 30),
      onTimeout: () {
        final r = _needsVerification(url);
        finish(r);
        return r;
      },
    );
  }
}
