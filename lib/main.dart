import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';

import 'app.dart';
import 'firebase_options.dart';
import 'services/share_service.dart';
import 'services/thumbnail_store.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  try {
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );
    // Offline persistence keeps the shelf readable without a connection.
    FirebaseFirestore.instance.settings = const Settings(
      persistenceEnabled: true,
      cacheSizeBytes: 100 * 1024 * 1024,
    );
  } catch (e, stack) {
    debugPrint('Firebase.initializeApp warning/error: $e\n$stack');
  }

  if (kDebugMode) {
    try {
      await InAppWebViewController.setWebContentsDebuggingEnabled(true);
    } catch (e) {
      debugPrint('InAppWebViewController error: $e');
    }
  }

  late final ThumbnailStore thumbs;
  try {
    thumbs = await ThumbnailStore.create();
  } catch (e) {
    debugPrint('ThumbnailStore.create error: $e');
    rethrow;
  }

  final share = ShareService();
  try {
    await share.init();
  } catch (e) {
    debugPrint('ShareService.init error: $e');
  }

  runApp(ShelfmarkApp(thumbs: thumbs, share: share));
}
