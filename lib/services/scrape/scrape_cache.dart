import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

import 'site_adapter.dart';

/// Persistent cache of scraped chapters.
///
/// Once a chapter has been scraped (or verified by the user) its page list,
/// next/prev links and chapter catalogue are stored on disk. Re-opening the
/// chapter, resuming reading, or reading offline never touches the network
/// (and therefore never hits Cloudflare) again. Only *new* content needs a
/// fresh scrape.
class ScrapeCache {
  ScrapeCache._();
  static final ScrapeCache instance = ScrapeCache._();

  /// Image URLs on some CDNs rotate; refresh old entries eventually.
  static const Duration maxAge = Duration(days: 21);
  static const int _maxMemory = 60;

  /// Bump when scraping output changes, so stale entries (wrong next links,
  /// unreadable image URLs) are re-scraped instead of served from disk.
  static const int _version = 3;

  final Map<String, _Entry> _mem = {};
  Directory? _dir;

  Future<Directory?> _ensureDir() async {
    if (_dir != null) return _dir;
    try {
      final base = await getApplicationSupportDirectory();
      final d = Directory('${base.path}/scrape_cache');
      if (!await d.exists()) await d.create(recursive: true);
      _dir = d;
    } catch (_) {}
    return _dir;
  }

  static String _norm(String url) {
    var u = url.trim();
    final hash = u.indexOf('#');
    if (hash >= 0) u = u.substring(0, hash);
    if (u.endsWith('/')) u = u.substring(0, u.length - 1);
    return u;
  }

  /// Two independent 32-bit hashes -> stable 16-hex-char file name.
  static String _fileKey(String url) {
    var h1 = 0x811c9dc5;
    var h2 = 0x5bd1e995;
    for (final b in utf8.encode(url)) {
      h1 = ((h1 ^ b) * 0x01000193) & 0xFFFFFFFF;
      h2 = ((h2 + b) * 0x5bd1e995) & 0xFFFFFFFF;
      h2 ^= h2 >> 15;
    }
    return h1.toRadixString(16).padLeft(8, '0') +
        h2.toRadixString(16).padLeft(8, '0');
  }

  Future<ScrapedChapterResult?> get(String url) async {
    final key = _norm(url);
    var e = _mem[key];
    if (e == null) {
      try {
        final dir = await _ensureDir();
        if (dir == null) return null;
        final f = File('${dir.path}/${_fileKey(key)}.json');
        if (!await f.exists()) return null;
        final m = jsonDecode(await f.readAsString()) as Map<String, dynamic>;
        if (m['url'] != key) return null; // hash collision guard
        if (m['v'] != _version) return null; // scraped by an older engine
        e = _Entry.fromJson(m);
        _remember(key, e);
      } catch (_) {
        return null;
      }
    }
    if (DateTime.now().difference(e.savedAt) > maxAge) return null;
    return e.result;
  }

  Future<void> put(String url, ScrapedChapterResult result) async {
    if (result.pages.length < 2 || result.needsVerification) return;
    final key = _norm(url);
    final e = _Entry(result, DateTime.now());
    _remember(key, e);
    try {
      final dir = await _ensureDir();
      if (dir == null) return;
      final f = File('${dir.path}/${_fileKey(key)}.json');
      await f.writeAsString(jsonEncode(e.toJson(key)));
    } catch (_) {}
  }

  Future<void> remove(String url) async {
    final key = _norm(url);
    _mem.remove(key);
    try {
      final dir = await _ensureDir();
      if (dir == null) return;
      final f = File('${dir.path}/${_fileKey(key)}.json');
      if (await f.exists()) await f.delete();
    } catch (_) {}
  }

  void _remember(String key, _Entry e) {
    _mem.remove(key);
    _mem[key] = e;
    while (_mem.length > _maxMemory) {
      _mem.remove(_mem.keys.first);
    }
  }
}

class _Entry {
  _Entry(this.result, this.savedAt);
  final ScrapedChapterResult result;
  final DateTime savedAt;

  Map<String, dynamic> toJson(String key) => {
        'v': ScrapeCache._version,
        'url': key,
        'savedAt': savedAt.millisecondsSinceEpoch,
        'chapterUrl': result.chapterUrl,
        'pages': result.pages,
        'title': result.title,
        'chapterLabel': result.chapterLabel,
        'next': result.nextChapterUrl,
        'prev': result.prevChapterUrl,
        'nextGuessed': result.nextGuessed,
        'isWebtoon': result.isWebtoon,
        'cover': result.coverUrl,
        'chapters': [
          for (final c in result.availableChapters)
            {'url': c.url, 'label': c.label},
        ],
      };

  factory _Entry.fromJson(Map<String, dynamic> m) {
    return _Entry(
      ScrapedChapterResult(
        chapterUrl: (m['chapterUrl'] as String?) ?? (m['url'] as String),
        pages: ((m['pages'] as List?) ?? const []).cast<String>(),
        title: m['title'] as String?,
        chapterLabel: m['chapterLabel'] as String?,
        nextChapterUrl: m['next'] as String?,
        prevChapterUrl: m['prev'] as String?,
        nextGuessed: (m['nextGuessed'] as bool?) ?? false,
        isWebtoon: (m['isWebtoon'] as bool?) ?? false,
        coverUrl: m['cover'] as String?,
        availableChapters: [
          for (final c in ((m['chapters'] as List?) ?? const []))
            ChapterRef(
              url: (c as Map)['url'] as String,
              label: c['label'] as String,
            ),
        ],
      ),
      DateTime.fromMillisecondsSinceEpoch(
        ((m['savedAt'] as num?) ?? 0).toInt(),
      ),
    );
  }
}
