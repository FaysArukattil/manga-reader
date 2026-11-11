import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';

import '../services/scrape/cf_session.dart';
import '../services/scrape/site_adapter.dart';
import '../services/web_scraper.dart';

/// What the sheet read from the page once it was unlocked. The caller stores
/// it in the scrape cache so this chapter is never verified again.
class CfVerifiedPage {
  const CfVerifiedPage({
    required this.url,
    required this.pages,
    this.title,
    this.nextUrl,
    this.prevUrl,
    this.chapters = const [],
  });

  final String url;
  final List<String> pages;
  final String? title;
  final String? nextUrl;
  final String? prevUrl;
  final List<ChapterRef> chapters;
}

/// Bottom sheet that shows the real site so the user can pass Cloudflare /
/// Turnstile once. Pops with:
///   * [CfVerifiedPage]  -> challenge cleared; pages/nav read from the page
///   * `false` / null    -> cancelled
///
/// Why the old one looped:
///  - it considered "a cf_clearance cookie exists" as solved, so a stale
///    cookie closed the sheet instantly, then scraping hit the challenge again;
///  - it spoofed a user-agent that didn't match the real WebView, so
///    Cloudflare kept re-challenging;
///  - it matched `challenge-platform` in the DOM, which is present on normal
///    Cloudflare pages, so even a solved page looked like a challenge.
class CfVerificationSheet extends StatefulWidget {
  const CfVerificationSheet({super.key, required this.url});

  final String url;

  @override
  State<CfVerificationSheet> createState() => _CfVerificationSheetState();
}

class _CfVerificationSheetState extends State<CfVerificationSheet> {
  InAppWebViewController? _web;
  double _progress = 0;
  bool _done = false;
  bool _checking = false;
  int _okStreak = 0;
  Timer? _poll;

  @override
  void initState() {
    super.initState();
    // Poll for the whole life of the sheet (the user may take a while).
    _poll = Timer.periodic(
      const Duration(milliseconds: 800),
      (_) => _checkIfSolved(),
    );
  }

  @override
  void dispose() {
    _poll?.cancel();
    super.dispose();
  }

  Future<List<String>> _readPages() async {
    final out = <String>[];
    try {
      final res = await _web?.evaluateJavascript(
        source: WebScraper.extractImagesJs,
      );
      if (res is List) {
        for (final p in res) {
          if (p != null && p.toString().isNotEmpty) out.add(p.toString());
        }
      }
    } catch (_) {}
    return out;
  }

  Future<void> _finish() async {
    if (_done) return;
    _done = true;
    _poll?.cancel();

    // Lazy-loaded readers need a nudge; try a few times before giving up.
    var pages = <String>[];
    for (var i = 0; i < 4 && pages.length < 2; i++) {
      try {
        await _web?.evaluateJavascript(
          source:
              'window.scrollTo(0, document.body.scrollHeight/2); setTimeout(function(){window.scrollTo(0,0);}, 150);',
        );
      } catch (_) {}
      await Future<void>.delayed(const Duration(milliseconds: 450));
      pages = await _readPages();
    }

    String? next, prev, title;
    final chapters = <ChapterRef>[];
    try {
      final nav = await _web?.evaluateJavascript(
        source: WebScraper.extractNavigationJs,
      );
      if (nav is Map) {
        next = nav['next']?.toString();
        prev = nav['prev']?.toString();
        final list = nav['chapters'];
        if (list is List) {
          for (final c in list) {
            if (c is Map && c['url'] != null && c['label'] != null) {
              chapters.add(
                ChapterRef(
                  url: c['url'].toString(),
                  label: c['label'].toString(),
                ),
              );
            }
          }
        }
      }
      title = await _web?.getTitle();
    } catch (_) {}

    // Image downloads must send cf_clearance + the matching UA.
    await CfSession.primeAll(widget.url, pages);
    CfSession.webViewOnlyHosts.add(Uri.tryParse(widget.url)?.host ?? '');
    if (!mounted) return;
    Navigator.of(context).pop(
      CfVerifiedPage(
        url: widget.url,
        pages: pages,
        title: title,
        nextUrl: next,
        prevUrl: prev,
        chapters: chapters,
      ),
    );
  }

  /// Solved = the page in front of us is a normal page (no challenge markers),
  /// fully loaded, for two consecutive polls. A leftover cookie is irrelevant.
  Future<void> _checkIfSolved() async {
    if (_done || _checking || _web == null) return;
    _checking = true;
    try {
      final challenge = await _web!.evaluateJavascript(
        source: CfSession.challengeProbeJs,
      );
      final ready = await _web!.evaluateJavascript(
        source: CfSession.pageReadyProbeJs,
      );
      if (challenge != true && ready == true) {
        _okStreak++;
      } else {
        _okStreak = 0;
      }
      if (_okStreak >= 2) {
        await _finish();
      }
    } catch (_) {
      _okStreak = 0;
    } finally {
      _checking = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final host = Uri.tryParse(widget.url)?.host ?? widget.url;

    return Container(
      height: MediaQuery.of(context).size.height * 0.88,
      decoration: const BoxDecoration(
        color: Color(0xFF141416),
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
            child: Row(
              children: [
                const Icon(Icons.shield_outlined,
                    color: Color(0xFF00B96B), size: 20),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Security Verification',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      Text(
                        host,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            color: Colors.white38, fontSize: 11),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.refresh,
                      color: Colors.white70, size: 20),
                  tooltip: 'Reload',
                  onPressed: () => _web?.reload(),
                ),
                TextButton(
                  onPressed: () => _finish(),
                  child: const Text(
                    'Done',
                    style: TextStyle(
                      color: Color(0xFF00B96B),
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                IconButton(
                  icon:
                      const Icon(Icons.close, color: Colors.white70, size: 20),
                  onPressed: () {
                    _done = true;
                    _poll?.cancel();
                    Navigator.pop(context, false);
                  },
                ),
              ],
            ),
          ),
          if (_progress < 1.0)
            LinearProgressIndicator(
              value: _progress,
              minHeight: 2,
              backgroundColor: Colors.transparent,
              valueColor:
                  const AlwaysStoppedAnimation<Color>(Color(0xFF00B96B)),
            ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            color: Colors.white.withValues(alpha: 0.04),
            child: const Row(
              children: [
                Icon(Icons.info_outline, size: 14, color: Colors.white54),
                SizedBox(width: 6),
                Expanded(
                  child: Text(
                    'Complete the "Verify you are human" check below. It continues automatically once the page loads.',
                    style: TextStyle(color: Colors.white70, fontSize: 11),
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: InAppWebView(
              initialUrlRequest: URLRequest(url: WebUri(widget.url)),
              // No custom userAgent: the real WebView UA is what passes
              // Turnstile, and it matches CfSession.userAgent everywhere else.
              initialSettings: InAppWebViewSettings(
                javaScriptEnabled: true,
                domStorageEnabled: true,
                databaseEnabled: true,
                thirdPartyCookiesEnabled: true,
                javaScriptCanOpenWindowsAutomatically: true,
                useHybridComposition: true,
                supportZoom: true,
                mixedContentMode:
                    MixedContentMode.MIXED_CONTENT_COMPATIBILITY_MODE,
              ),
              onWebViewCreated: (c) => _web = c,
              onProgressChanged: (_, p) {
                if (mounted) setState(() => _progress = p / 100);
              },
              onLoadStop: (_, __) => _checkIfSolved(),
              // Turnstile / some sites open helper windows; keep them in-app.
              onCreateWindow: (controller, action) async {
                final u = action.request.url;
                if (u != null) {
                  await controller.loadUrl(urlRequest: URLRequest(url: u));
                }
                return false;
              },
            ),
          ),
        ],
      ),
    );
  }
}
