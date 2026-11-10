import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Receives "Share -> Shelfmark" text from other apps (e.g. Chrome) through a
/// tiny native channel (see android_overrides/MainActivity.kt).
class ShareService extends ChangeNotifier {
  static const _channel = MethodChannel('com.shelfmark/share');

  String? _pending;

  /// Returns and clears the pending shared text, if any.
  String? take() {
    final p = _pending;
    _pending = null;
    return p;
  }

  Future<void> init() async {
    _channel.setMethodCallHandler((call) async {
      if (call.method == 'onShare' && call.arguments is String) {
        _pending = call.arguments as String;
        notifyListeners();
      }
    });
    try {
      final initial = await _channel.invokeMethod<String>('getInitialShare');
      if (initial != null && initial.isNotEmpty) {
        _pending = initial;
        notifyListeners();
      }
    } on MissingPluginException {
      // Not running on Android with the override; ignore.
    } on PlatformException {
      // Ignore.
    }
  }
}
