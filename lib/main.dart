import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';

import 'app.dart';
import 'firebase_options.dart';
import 'services/page_cache.dart';
import 'services/share_service.dart';
import 'services/thumbnail_store.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  try {
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );
    FirebaseFirestore.instance.settings = const Settings(
      persistenceEnabled: true,
      cacheSizeBytes: 100 * 1024 * 1024,
    );
  } catch (e, st) {
    debugPrint('Firebase initialization error: $e\n$st');
  }

  if (kDebugMode) {
    try {
      await InAppWebViewController.setWebContentsDebuggingEnabled(true);
    } catch (_) {}
  }

  final thumbs = await ThumbnailStore.create();
  final chapterStore = await ChapterStore.create();
  final share = ShareService();
  await share.init();

  runApp(
    ShelfmarkApp(thumbs: thumbs, share: share, chapterStore: chapterStore),
  );
}
