import 'package:flutter_inappwebview/flutter_inappwebview.dart';

/// Single source of truth for everything Cloudflare-related:
///
///  * ONE user-agent used by the verification WebView, the headless scraper,
///    the HTTP client and image downloads. `cf_clearance` is bound to the UA
///    that solved the challenge, so these must all match. We use the real
///    WebView UA (not a hard-coded fake) because Cloudflare cross-checks the
///    UA against the browser's real fingerprint / client hints.
///  * Reliable "is this a challenge page?" detection. The old checks matched
///    things like `challenge-platform` / `challenges.cloudflare.com`, which
///    appear on NORMAL Cloudflare-protected pages too -> endless re-verify.
///  * A synchronous cookie cache so image requests can send `cf_clearance`.
class CfSession {
  CfSession._();

  static const String _fallbackUserAgent =
      'Mozilla/5.0 (Linux; Android 14; Pixel 8) AppleWebKit/537.36 '
      '(KHTML, like Gecko) Chrome/126.0.0.0 Mobile Safari/537.36';

  static String? _userAgent;

  /// Call once at startup (see main.dart).
  static Future<void> init() async {
    try {
      final ua = await InAppWebViewController.getDefaultUserAgent();
      if (ua.trim().isNotEmpty) {
        // Android WebView appends "; wv" which some sites treat as a bot flag.
        _userAgent = ua.replaceAll('; wv)', ')');
      }
    } catch (_) {}
  }

  static String get userAgent => _userAgent ?? _fallbackUserAgent;

  // ---------------------------------------------------------------- cookies

  static final Map<String, String> _cookieByHost = {};

  /// Reads cookies from the WebView cookie jar for [url]'s host and caches
  /// them so [imageHeaders] can use them synchronously.
  static Future<void> primeCookies(String url) async {
    try {
      final host = Uri.parse(url).host;
      if (host.isEmpty) return;
      final cookies =
          await CookieManager.instance().getCookies(url: WebUri(url));
      if (cookies.isEmpty) return;
      _cookieByHost[host] =
          cookies.map((c) => '${c.name}=${c.value}').join('; ');
    } catch (_) {}
  }

  static Future<void> primeAll(
      String pageUrl, Iterable<String> imageUrls) async {
    final hosts = <String>{};
    await primeCookies(pageUrl);
    for (final u in imageUrls) {
      final h = Uri.tryParse(u)?.host ?? '';
      if (h.isNotEmpty && hosts.add(h)) {
        await primeCookies(u);
      }
    }
  }

  static Future<String?> cookieHeader(String url) async {
    try {
      final cookies =
          await CookieManager.instance().getCookies(url: WebUri(url));
      if (cookies.isEmpty) return null;
      return cookies.map((c) => '${c.name}=${c.value}').join('; ');
    } catch (_) {
      return null;
    }
  }

  static Future<String?> clearanceValue(String url) async {
    try {
      final cookies =
          await CookieManager.instance().getCookies(url: WebUri(url));
      for (final c in cookies) {
        if (c.name == 'cf_clearance') return c.value?.toString();
      }
    } catch (_) {}
    return null;
  }

  /// Headers for downloading a page image (used by CachedNetworkImage).
  static Map<String, String> imageHeaders(String imageUrl, String? referer) {
    final host = Uri.tryParse(imageUrl)?.host ?? '';
    final cookie = _cookieByHost[host];
    return {
      'User-Agent': userAgent,
      if (referer != null) 'Referer': referer,
      if (cookie != null && cookie.isNotEmpty) 'Cookie': cookie,
    };
  }

  // --------------------------------------------------------- hosts needing a WebView

  /// Hosts where plain HTTP got challenged. Dart's HTTP client has a
  /// non-browser TLS fingerprint, so once a host challenges it we go straight
  /// to the WebView for that host (faster, and avoids pointless 403s).
  static final Set<String> webViewOnlyHosts = {};

  // ------------------------------------------------------------ detection

  /// JS run inside a WebView. True ONLY when the page in front of us is an
  /// actual Cloudflare interstitial (not merely a Cloudflare-protected site).
  static const String challengeProbeJs = r'''
(function(){
  try {
    var t = (document.title || '').toLowerCase();
    if (t.indexOf('just a moment') !== -1 ||
        t.indexOf('attention required! | cloudflare') !== -1 ||
        t.indexOf('verify you are human') !== -1) return true;
    if (document.querySelector('#challenge-running, #challenge-stage, #challenge-form, #challenge-error-text, #cf-challenge-running, #cf-please-wait, .cf-browser-verification, #cf-wrapper .cf-error-details')) return true;
    var b = document.body ? (document.body.innerText || '') : '';
    if (b.length < 1500 && /verify you are human|checking (if the site connection is secure|your browser)|enable javascript and cookies to continue/i.test(b)) return true;
    return false;
  } catch (e) { return false; }
})()
''';

  /// JS: is the document fully loaded on a real http(s) page?
  static const String pageReadyProbeJs = r'''
(function(){
  try {
    return document.readyState === 'complete' &&
           /^https?:/.test(location.href) &&
           (document.title || '').trim().length > 0 &&
           !!document.body && (document.body.innerText || '').trim().length > 40;
  } catch (e) { return false; }
})()
''';

  /// HTML-level check, for the HTTP fast path and the adapter.
  /// Deliberately does NOT match `challenge-platform`, `cf-turnstile` or
  /// `challenges.cloudflare.com` on their own: those show up on normal pages
  /// (Cloudflare's JS detections, comment-form Turnstile widgets).
  static bool looksLikeChallengeHtml(String html) {
    final head = html.length > 6000 ? html.substring(0, 6000) : html;
    final lower = head.toLowerCase();
    final title = RegExp(r'<title[^>]*>\s*([^<]*)', caseSensitive: false)
            .firstMatch(head)
            ?.group(1)
            ?.trim()
            .toLowerCase() ??
        '';
    if (title.startsWith('just a moment') ||
        title.startsWith('attention required! | cloudflare') ||
        title.contains('verify you are human')) {
      return true;
    }
    if (lower.contains('id="challenge-running"') ||
        lower.contains('id="challenge-stage"') ||
        lower.contains('id="challenge-form"') ||
        lower.contains('id="cf-challenge-running"') ||
        lower.contains('cf-browser-verification')) {
      return true;
    }
    // Interstitial pages are tiny and define _cf_chl_opt.
    if (html.length < 40000 && html.contains('_cf_chl_opt')) return true;
    return false;
  }

  static bool isChallengeResponse(
    int statusCode,
    Map<String, String> headers,
    String body,
  ) {
    final mitigated = headers.entries.any(
      (e) =>
          e.key.toLowerCase() == 'cf-mitigated' &&
          e.value.toLowerCase().contains('challenge'),
    );
    if (mitigated) return true;
    if (statusCode == 403 || statusCode == 429 || statusCode == 503) {
      return looksLikeChallengeHtml(body);
    }
    // A 200 can still be an interstitial (rare); require strong markers.
    return looksLikeChallengeHtml(body);
  }
}
