package com.faysarukattil.shelfmark

import android.content.Intent
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

/**
 * Receives "Share -> Shelfmark" text (a URL, optionally with a title) and hands
 * it to Dart over a small MethodChannel. No third-party plugin needed.
 */
class MainActivity : FlutterActivity() {
    private var channel: MethodChannel? = null
    private var pendingShare: String? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        val ch = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "com.shelfmark/share")
        ch.setMethodCallHandler { call, result ->
            when (call.method) {
                "getInitialShare" -> {
                    result.success(pendingShare)
                    pendingShare = null
                }
                else -> result.notImplemented()
            }
        }
        channel = ch
        pendingShare = extractShare(intent)
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        val text = extractShare(intent)
        if (text != null) channel?.invokeMethod("onShare", text)
    }

    private fun extractShare(intent: Intent?): String? {
        if (intent == null || intent.action != Intent.ACTION_SEND) return null
        if (intent.type?.startsWith("text/") != true) return null
        val text = intent.getStringExtra(Intent.EXTRA_TEXT) ?: return null
        val subject = intent.getStringExtra(Intent.EXTRA_SUBJECT)
        // Clear so a config change / re-create doesn't re-deliver the same share.
        intent.removeExtra(Intent.EXTRA_TEXT)
        return if (subject.isNullOrBlank()) text else "$subject\n$text"
    }
}
