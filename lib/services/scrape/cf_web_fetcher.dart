import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'dart:ui' show Size;

import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';

import 'cf_session.dart';

/// Downloads a file using the WebView's own network stack (real Chrome TLS
/// fingerprint + the cf_clearance cookie), by running `fetch()` inside a page
/// that lives on the same origin as the file.
///
/// Needed because some sites (e.g. manhuaus.com) answer plain Dart HTTP image
/// requests with 403 / a challenge even when the cookie is valid, while the
/// very same request from a real browser engine succeeds.
class CfWebFetcher {
  CfWebFetcher._();
  static final CfWebFetcher instance = CfWebFetcher._();

  final Map<String, Future<_Session?>> _sessions = {};
  int _active = 0;
  final List<Completer<void>> _waiters = [];
  static const int _maxParallel = 3;

  Future<void> _acquire() async {
    if (_active < _maxParallel) {
      _active++;
      return;
    }
    final c = Completer<void>();
    _waiters.add(c);
    await c.future;
  }

  void _release() {
    if (_waiters.isNotEmpty) {
      _waiters.removeAt(0).complete();
    } else {
      _active--;
    }
  }

  /// Returns the file bytes, or null if the WebView couldn't get it either.
  Future<WebFetchResult?> fetch(String url) async {
    final uri = Uri.tryParse(url);
    if (uri == null || uri.host.isEmpty) return null;
    final origin = '${uri.scheme}://${uri.host}';

    await _acquire();
    try {
      final session = await (_sessions[origin] ??= _open(origin));
      if (session == null) {
        _sessions.remove(origin);
        return null;
      }
      session.touch();

      final res = await session.controller.callAsyncJavaScript(
        functionBody: _fetchJs,
        arguments: {'url': url},
      );
      final v = res?.value;
      if (v is! Map) {
        CfDiag.log('webfetch no result $url err=${res?.error}');
        return null;
      }
      final status = (v['status'] as num?)?.toInt() ?? 0;
      if (status != 200 || v['b64'] == null) {
        CfDiag.log('webfetch status=$status $url');
        // Session may have a stale clearance/challenge: rebuild next time.
        if (status == 403 || status == 429 || status == 503) {
          _sessions.remove(origin);
          await session.dispose();
        }
        return null;
      }
      final bytes = base64Decode(v['b64'] as String);
      return WebFetchResult(bytes, (v['type'] as String?) ?? '');
    } catch (e) {
      CfDiag.log('webfetch error $e');
      _sessions.remove(origin);
      return null;
    } finally {
      _release();
    }
  }

  static const String _fetchJs = r'''
const resp = await fetch(url, {credentials: 'include', cache: 'no-store'});
if (!resp.ok) { return {status: resp.status}; }
const type = resp.headers.get('content-type') || '';
if (type.indexOf('text/html') !== -1) { return {status: 499, type: type}; }
const buf = new Uint8Array(await resp.arrayBuffer());
let bin = '';
const CH = 0x8000;
for (let i = 0; i < buf.length; i += CH) {
  bin += String.fromCharCode.apply(null, buf.subarray(i, i + CH));
}
return {status: 200, type: type, b64: btoa(bin)};
''';

  /// Loads a tiny same-origin page so fetch() runs with that origin's cookies
  /// and no CORS restrictions.
  Future<_Session?> _open(String origin) async {
    final loaded = Completer<void>();
    InAppWebViewController? controller;
    HeadlessInAppWebView? headless;

    headless = HeadlessInAppWebView(
      initialSize: const Size(360, 640),
      initialUrlRequest: URLRequest(url: WebUri('$origin/robots.txt')),
      initialSettings: CfSession.webViewSettings(),
      onWebViewCreated: (c) => controller = c,
      onLoadStop: (c, u) {
        if (!loaded.isCompleted) loaded.complete();
      },
      onReceivedError: (c, r, e) {
        if (r.isForMainFrame == true && !loaded.isCompleted) {
          loaded.complete();
        }
      },
    );

    try {
      await headless.run();
      await loaded.future.timeout(const Duration(seconds: 20));
    } catch (e) {
      CfDiag.log('webfetch session failed for $origin: $e');
      await headless.dispose();
      return null;
    }
    final c = controller;
    if (c == null) {
      await headless.dispose();
      return null;
    }

    // If robots.txt itself sat behind an interstitial, give it time to clear.
    for (var i = 0; i < 12; i++) {
      final ch = await c.evaluateJavascript(source: CfSession.challengeProbeJs);
      if (ch != true) break;
      await Future<void>.delayed(const Duration(seconds: 1));
    }
    CfDiag.log('webfetch session ready for $origin');
    return _Session(headless, c, () => _sessions.remove(origin));
  }
}

class WebFetchResult {
  WebFetchResult(this.bytes, this.contentType);
  final Uint8List bytes;
  final String contentType;
}

class _Session {
  _Session(this._headless, this.controller, this._onClosed) {
    touch();
  }

  final HeadlessInAppWebView _headless;
  final InAppWebViewController controller;
  final void Function() _onClosed;
  Timer? _idle;

  /// Keep the hidden WebView warm while pages are being read, free it after.
  void touch() {
    _idle?.cancel();
    _idle = Timer(const Duration(seconds: 120), () async {
      _onClosed();
      await dispose();
    });
  }

  Future<void> dispose() async {
    _idle?.cancel();
    try {
      await _headless.dispose();
    } catch (_) {}
  }
}

/// A flutter_cache_manager FileService that uses normal HTTP first and falls
/// back to the WebView when the site refuses a non-browser client.
class CfFileService extends FileService {
  CfFileService() {
    concurrentFetches = 3;
  }

  final HttpFileService _http = HttpFileService();

  /// Hosts where plain HTTP was refused; go straight to the WebView.
  static final Set<String> _webHosts = {};

  @override
  Future<FileServiceResponse> get(
    String url, {
    Map<String, String>? headers,
  }) async {
    final host = Uri.tryParse(url)?.host ?? '';
    // Only scraped sites send a Referer; MangaDex etc. never need the fallback.
    final canFallback = headers != null && headers.containsKey('Referer');

    FileServiceResponse? first;
    if (!canFallback || !_webHosts.contains(host)) {
      try {
        first = await _http.get(url, headers: headers);
        final code = first.statusCode;
        if (code < 400 || !canFallback) return first;
        if (code != 403 && code != 401 && code != 429 && code != 503) {
          return first;
        }
        CfDiag.log('http $code for $host -> trying WebView');
      } catch (e) {
        if (!canFallback) rethrow;
        CfDiag.log('http error for $host: $e -> trying WebView');
      }
    }

    final viaWeb = await CfWebFetcher.instance.fetch(url);
    if (viaWeb != null) {
      _webHosts.add(host);
      return _BytesResponse(viaWeb.bytes, _extFor(viaWeb.contentType, url));
    }

    // WebView failed too: let the caller see the original HTTP failure.
    if (first != null) return first;
    return _http.get(url, headers: headers);
  }

  static String _extFor(String contentType, String url) {
    final t = contentType.toLowerCase();
    if (t.contains('webp')) return '.webp';
    if (t.contains('png')) return '.png';
    if (t.contains('gif')) return '.gif';
    if (t.contains('avif')) return '.avif';
    if (t.contains('jpeg') || t.contains('jpg')) return '.jpg';
    final m = RegExp(r'\.(jpe?g|png|webp|gif|avif)(?:$|\?)', caseSensitive: false)
        .firstMatch(url);
    return m != null ? '.${m.group(1)!.toLowerCase()}' : '.jpg';
  }
}

class _BytesResponse implements FileServiceResponse {
  _BytesResponse(this._bytes, this._ext);

  final Uint8List _bytes;
  final String _ext;

  @override
  Stream<List<int>> get content => Stream.value(_bytes);

  @override
  int? get contentLength => _bytes.length;

  @override
  int get statusCode => 200;

  @override
  DateTime get validTill => DateTime.now().add(const Duration(days: 30));

  @override
  String? get eTag => null;

  @override
  String get fileExtension => _ext;
}
