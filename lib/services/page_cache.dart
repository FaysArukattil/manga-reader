import 'dart:convert';
import 'dart:io';

import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import 'package:path_provider/path_provider.dart';

import 'mangadex_service.dart';
import 'scrape/cf_web_fetcher.dart';

/// Disk cache for chapter page images. Keyed by URL *path* (hash/filename),
/// not host, so a cached page is found even when MangaDex@Home hands out a
/// different server next time.
class PageCache {
  PageCache._();

  static final CacheManager instance = CacheManager(
    Config(
      'mdPages',
      stalePeriod: const Duration(days: 30),
      maxNrOfCacheObjects: 4000,
      // Plain HTTP first; falls back to the WebView's network stack for sites
      // (e.g. manhuaus.com) that refuse non-browser image requests.
      fileService: CfFileService(),
    ),
  );

  static String keyFor(String url) => Uri.parse(url).path;
}

/// Small JSON store: page-URL lists for chapters saved for offline reading,
/// and the last-known chapter list per series (so the list shows offline).
class ChapterStore {
  ChapterStore._(this._dir);

  final Directory _dir;

  static Future<ChapterStore> create() async {
    final base = await getApplicationSupportDirectory();
    final dir = Directory('${base.path}/md');
    if (!await dir.exists()) await dir.create(recursive: true);
    return ChapterStore._(dir);
  }

  File _f(String name) => File('${_dir.path}/$name.json');

  Future<void> saveUrls(String chapterId, List<String> urls) =>
      _f('pages_$chapterId').writeAsString(jsonEncode(urls));

  Future<List<String>?> loadUrls(String chapterId) async {
    final f = _f('pages_$chapterId');
    try {
      if (!await f.exists()) return null;
      return (jsonDecode(await f.readAsString()) as List).cast<String>();
    } catch (_) {
      return null;
    }
  }

  Future<void> saveChapters(String mangaId, List<MdChapter> list) =>
      _f('chapters_$mangaId')
          .writeAsString(jsonEncode(list.map((c) => c.toJson()).toList()));

  Future<List<MdChapter>?> loadChapters(String mangaId) async {
    final f = _f('chapters_$mangaId');
    try {
      if (!await f.exists()) return null;
      final raw = jsonDecode(await f.readAsString()) as List;
      return raw
          .whereType<Map<String, dynamic>>()
          .map(MdChapter.fromJson)
          .toList();
    } catch (_) {
      return null;
    }
  }
}
