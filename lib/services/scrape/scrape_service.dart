import 'dart:async';
import 'package:flutter/widgets.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:html/dom.dart' as dom;
import 'package:http/http.dart' as http;

import '../../core/url_tools.dart';
import '../../ui/ad_block.dart';
import '../web_scraper.dart';
import 'generic_site_adapter.dart';
import 'site_adapter.dart';

class ScrapeService {
  ScrapeService({http.Client? client}) : _client = client ?? http.Client();

  final http.Client _client;
  final List<SiteAdapter> _adapters = [const GenericSiteAdapter()];

  static const String mobileUserAgent =
      'Mozilla/5.0 (Linux; Android 14; Mobile; SM-S928B) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/126.0.0.0 Mobile Safari/537.36';

  void registerAdapter(SiteAdapter adapter) {
    _adapters.insert(0, adapter); // Custom adapters take precedence
  }

  SiteAdapter _adapterFor(String host) {
    for (final a in _adapters) {
      if (a.matches(host)) return a;
    }
    return const GenericSiteAdapter();
  }

  /// Scrapes pages from a chapter URL using the multi-tier engine:
  /// 1. Fast path (HTTP GET + DOM parsing + Script extraction)
  /// 2. Rendered path fallback (Headless WebView with scroll trigger & JS globals)
  /// 3. Series overview auto-detection (resolves chapter list -> chapter 1)
  Future<ScrapedChapterResult> scrapeChapter(String url) async {
    final uri = Uri.tryParse(url);
    if (uri == null) {
      return ScrapedChapterResult(chapterUrl: url, pages: const []);
    }

    final adapter = _adapterFor(uri.host);

    // ------------------------------------------------------------- 1. Fast Path
    try {
      final response = await _client.get(
        uri,
        headers: {
          'User-Agent': mobileUserAgent,
          'Accept':
              'text/html,application/xhtml+xml,application/xml;q=0.9,image/avif,image/webp,*/*;q=0.8',
          'Accept-Language': 'en-US,en;q=0.9',
          'Referer': url,
        },
      ).timeout(const Duration(seconds: 8));

      if (response.statusCode == 200 && response.body.isNotEmpty) {
        final doc = dom.Document.html(response.body);
        final result = await adapter.extract(doc, uri);
        if (result.pages.length >= 2) {
          // Fast path succeeded!
          return result;
        }

        // If this was a series overview page, auto-hop to the first available chapter!
        if (result.pages.isEmpty && result.availableChapters.isNotEmpty) {
          final start = _pickStartingChapter(result.availableChapters, url);
          if (start != null && start.url != url) {
            final chRes = await scrapeChapter(start.url);
            if (chRes.pages.length >= 2) {
              return chRes.copyWith(
                availableChapters: result.availableChapters,
              );
            }
          }
        }
      }
    } catch (_) {
      // Fall through to rendered path
    }

    // --------------------------------- 2. Rendered Path (HeadlessInAppWebView)
    try {
      final rendered = await _scrapeHeadless(url, uri);
      if (rendered.pages.length >= 2) {
        return rendered;
      }
      if (rendered.pages.isEmpty && rendered.availableChapters.isNotEmpty) {
        final start = _pickStartingChapter(rendered.availableChapters, url);
        if (start != null && start.url != url) {
          final chRes = await scrapeChapter(start.url);
          if (chRes.pages.length >= 2) {
            return chRes.copyWith(
              availableChapters: rendered.availableChapters,
            );
          }
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

    final settings = InAppWebViewSettings(
      javaScriptEnabled: true,
      javaScriptCanOpenWindowsAutomatically: false,
      mediaPlaybackRequiresUserGesture: true,
      mixedContentMode: MixedContentMode.MIXED_CONTENT_COMPATIBILITY_MODE,
      useHybridComposition: true,
      contentBlockers: buildContentBlockers(),
      userAgent: mobileUserAgent,
    );

    headless = HeadlessInAppWebView(
      initialSize: const Size(1080, 1920),
      initialUrlRequest: URLRequest(url: WebUri(url)),
      initialSettings: settings,
      onLoadStop: (controller, loadedUrl) async {
        try {
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
          final pageTitle = await controller.getTitle();

          final pages = <String>[];
          if (res is List) {
            for (final p in res) {
              if (p != null && p.toString().isNotEmpty) {
                pages.add(p.toString());
              }
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

          if (!completer.isCompleted) {
            completer.complete(
              ScrapedChapterResult(
                chapterUrl: url,
                pages: pages,
                title:
                    pageTitle != null ? UrlTools.cleanTitle(pageTitle) : null,
                chapterLabel: UrlTools.chapterLabel(url),
                nextChapterUrl: nextUrl ?? UrlTools.stepChapter(url, 1),
                prevChapterUrl: prevUrl ?? UrlTools.stepChapter(url, -1),
                isWebtoon: pages.length >= 2,
                availableChapters: availableChapters,
              ),
            );
          }
        } catch (e) {
          if (!completer.isCompleted) {
            completer.complete(
              ScrapedChapterResult(chapterUrl: url, pages: const []),
            );
          }
        } finally {
          headless?.dispose();
        }
      },
      onReceivedError: (controller, request, error) {
        // Only abort if the main web page itself failed to load
        if (request.isForMainFrame == true && !completer.isCompleted) {
          completer.complete(
            ScrapedChapterResult(chapterUrl: url, pages: const []),
          );
          headless?.dispose();
        }
      },
    );

    await headless.run();

    // Max 14-second timeout for headless scraping
    return completer.future.timeout(
      const Duration(seconds: 14),
      onTimeout: () {
        headless?.dispose();
        return ScrapedChapterResult(chapterUrl: url, pages: const []);
      },
    );
  }
}
