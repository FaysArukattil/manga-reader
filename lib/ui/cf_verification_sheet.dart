import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';

import '../services/scrape/cf_session.dart';
import '../services/scrape/site_adapter.dart';
import '../services/web_scraper.dart';
import 'ad_block.dart';

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

/// In-app verification view that renders the real site so the user can pass
/// Cloudflare / Turnstile challenges cleanly, without rogue popups or ads.
class CfVerificationSheet extends StatefulWidget {
  const CfVerificationSheet({
    super.key,
    required this.url,
    this.seriesTitle,
    this.onVerified,
    this.onClose,
    this.isFullScreen = false,
  });

  final String url;
  final String? seriesTitle;
  final ValueChanged<CfVerifiedPage>? onVerified;
  final VoidCallback? onClose;
  final bool isFullScreen;

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
      const Duration(milliseconds: 650),
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

    // Lazy / SPA readers render pages as you scroll: step down the page and
    // keep reading until the list stops growing.
    // Read pages with quick scrolling so lazy-loading images populate fast
    var pages = await _readPages();
    var last = pages.length;
    var stable = 0;
    var bottom = false;
    for (var i = 0; i < 20; i++) {
      if (pages.length >= 2 &&
          (bottom && stable >= 2 || pages.length >= 10 && stable >= 2)) {
        break;
      }
      try {
        final atBottom =
            await _web?.evaluateJavascript(source: WebScraper.scrollStepJs);
        if (atBottom == true) bottom = true;
      } catch (_) {}
      await Future<void>.delayed(const Duration(milliseconds: 180));
      pages = await _readPages();
      if (pages.length == last) {
        stable++;
      } else {
        stable = 0;
        last = pages.length;
      }
      if (pages.length < 2 && bottom && stable >= 4 && i >= 6) break;
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

    final result = CfVerifiedPage(
      url: widget.url,
      pages: pages,
      title: title,
      nextUrl: next,
      prevUrl: prev,
      chapters: chapters,
    );

    if (widget.onVerified != null) {
      widget.onVerified!(result);
    } else if (mounted) {
      Navigator.of(context).pop(result);
    }
  }

  /// Solved = the page in front of us is a normal page (no challenge markers),
  /// fully loaded, for two consecutive polls.
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

  void _handleClose() {
    _done = true;
    _poll?.cancel();
    if (widget.onClose != null) {
      widget.onClose!();
    } else if (mounted) {
      Navigator.pop(context, false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final host = Uri.tryParse(widget.url)?.host ?? widget.url;
    final baseHost = Uri.tryParse(widget.url)?.host.toLowerCase() ?? '';

    return Container(
      color: const Color(0xFF0D0E11),
      child: SafeArea(
        top: widget.isFullScreen,
        bottom: widget.isFullScreen,
        child: Column(
          children: [
            // Top App Bar
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 8),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(6),
                    decoration: BoxDecoration(
                      color: const Color(0xFF00C875).withValues(alpha: 0.15),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.shield_rounded,
                        color: Color(0xFF00C875), size: 18),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          widget.seriesTitle ?? 'Security Verification',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 14.5,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        Text(
                          host,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Colors.white38,
                            fontSize: 11,
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.refresh_rounded,
                        color: Colors.white70, size: 20),
                    tooltip: 'Reload',
                    onPressed: () => _web?.reload(),
                  ),
                  TextButton(
                    onPressed: () => _finish(),
                    child: const Text(
                      'Done',
                      style: TextStyle(
                        color: Color(0xFF00C875),
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close_rounded,
                        color: Colors.white70, size: 22),
                    tooltip: 'Close',
                    onPressed: _handleClose,
                  ),
                ],
              ),
            ),
            if (_progress < 1.0)
              LinearProgressIndicator(
                value: _progress,
                minHeight: 2.5,
                backgroundColor: Colors.transparent,
                valueColor:
                    const AlwaysStoppedAnimation<Color>(Color(0xFF00C875)),
              ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 7),
              color: Colors.white.withValues(alpha: 0.04),
              child: const Row(
                children: [
                  Icon(Icons.info_outline, size: 13, color: Color(0xFF00C875)),
                  SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Tap "Verify you are human" below. Shelfmark will automatically load the chapter once verified.',
                      style: TextStyle(color: Colors.white70, fontSize: 11.5),
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: InAppWebView(
                initialUrlRequest: URLRequest(url: WebUri(widget.url)),
                initialSettings: CfSession.webViewSettings(
                  contentBlockers: buildContentBlockers(),
                  popups: false,
                ),
                onWebViewCreated: (c) => _web = c,
                onProgressChanged: (_, p) {
                  if (mounted) setState(() => _progress = p / 100);
                },
                onLoadStop: (controller, loadedUrl) async {
                  // Center the Turnstile / Cloudflare challenge widget on mobile screen
                  try {
                    await controller.evaluateJavascript(source: r'''
                      (function() {
                        try {
                          var el = document.querySelector('#challenge-stage, .cf-turnstile, iframe[src*="challenges.cloudflare.com"], #cf-wrapper, #challenge-form');
                          if (el) {
                            el.scrollIntoView({behavior: 'smooth', block: 'center'});
                          }
                        } catch(e) {}
                      })();
                    ''');
                  } catch (_) {}
                  _checkIfSolved();
                },
                shouldOverrideUrlLoading: (controller, navigationAction) async {
                  final reqUrl = navigationAction.request.url;
                  if (reqUrl == null) return NavigationActionPolicy.ALLOW;
                  final targetHost = reqUrl.host.toLowerCase();

                  // Allow requests within the site domain, cloudflare challenge, or turnstile
                  final isAllowed = targetHost.isEmpty ||
                      targetHost == baseHost ||
                      targetHost.endsWith('.$baseHost') ||
                      targetHost.contains('cloudflare') ||
                      targetHost.contains('turnstile') ||
                      targetHost.contains('recaptcha') ||
                      targetHost.contains('hcaptcha');

                  if (!isAllowed) {
                    // Block rogue ad redirects
                    return NavigationActionPolicy.CANCEL;
                  }
                  return NavigationActionPolicy.ALLOW;
                },
                // Block popup windows entirely to prevent spam ads
                onCreateWindow: (controller, action) async {
                  return false;
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}
