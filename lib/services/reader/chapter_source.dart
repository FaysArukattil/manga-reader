import 'dart:math' as math;

import '../mangadex_service.dart';
import '../page_cache.dart';
import '../scrape/scrape_service.dart';
import '../scrape/site_adapter.dart';

class ReaderPageItem {
  const ReaderPageItem({
    required this.url,
    this.urls = const [],
    required this.chapterId,
    required this.chapterLabel,
    required this.pageIndex,
    required this.totalInChapter,
    this.referer,
  });

  final String url;
  final List<String> urls;
  final String chapterId;
  final String chapterLabel;
  final int pageIndex;
  final int totalInChapter;
  final String? referer;

  List<String> get allUrls => urls.isNotEmpty ? urls : [url];
  String get pageKey => PageCache.keyFor(url);

  bool matchesKey(String key) =>
      pageKey == key || allUrls.any((u) => PageCache.keyFor(u) == key);

  /// Builds grouped reader page items.
  /// When webtoons / manhwa chapters are uploaded sliced into dozens or hundreds
  /// of small vertical pieces (e.g. 111 slices of 1250px), displaying each slice
  /// as a single book page splits speech bubbles and dialogues in half.
  /// Grouping consecutive slices targets the standard ~25-30 pages per chapter
  /// and renders them stacked seamlessly without seams or gaps.
  static List<ReaderPageItem> buildGroupedItems({
    required List<String> rawPages,
    required String chapterId,
    required String chapterLabel,
    String? referer,
  }) {
    if (rawPages.isEmpty) return const [];
    final count = rawPages.length;

    int groupSize = 1;
    if (count >= 60) {
      groupSize = (count / 28).round().clamp(1, 6);
    }

    if (groupSize <= 1) {
      return List.generate(
        count,
        (i) => ReaderPageItem(
          url: rawPages[i],
          urls: [rawPages[i]],
          chapterId: chapterId,
          chapterLabel: chapterLabel,
          pageIndex: i,
          totalInChapter: count,
          referer: referer,
        ),
      );
    }

    final List<ReaderPageItem> items = [];
    int pageIdx = 0;
    for (int i = 0; i < count; i += groupSize) {
      final chunk = rawPages.sublist(i, math.min(i + groupSize, count));
      items.add(
        ReaderPageItem(
          url: chunk.first,
          urls: chunk,
          chapterId: chapterId,
          chapterLabel: chapterLabel,
          pageIndex: pageIdx,
          totalInChapter: 0,
          referer: referer,
        ),
      );
      pageIdx++;
    }

    final total = items.length;
    return items
        .map((item) => ReaderPageItem(
              url: item.url,
              urls: item.urls,
              chapterId: item.chapterId,
              chapterLabel: item.chapterLabel,
              pageIndex: item.pageIndex,
              totalInChapter: total,
              referer: item.referer,
            ))
        .toList();
  }
}

abstract class ChapterSource {
  Future<List<ReaderPageItem>> loadChapter(String chapterIdOrUrl);
  Future<String?> getNextChapterId(String currentChapterIdOrUrl);
  Future<String?> getPrevChapterId(String currentChapterIdOrUrl);
  Future<List<ChapterRef>> getAvailableChapters(String currentChapterIdOrUrl);
  String? get lastCoverUrl;
}

class VerificationRequiredException implements Exception {
  const VerificationRequiredException(this.url);
  final String url;

  @override
  String toString() => 'VerificationRequiredException(url: $url)';
}

/// Optional capability: a source that can re-check the network for a newer
/// chapter, bypassing whatever it has cached.
abstract class RefreshableChapterSource implements ChapterSource {
  /// Returns the id of the chapter after [chapterId], looking at the live site.
  /// Throws [VerificationRequiredException] if the site wants verification.
  Future<String?> refreshNextChapterId(String chapterId);
}

class ScrapedSource implements ChapterSource, RefreshableChapterSource {
  ScrapedSource({required this.scrapeService});

  final ScrapeService scrapeService;
  final Map<String, String?> _nextMap = {};
  final Map<String, String?> _prevMap = {};
  final Map<String, bool> _nextGuessed = {};
  final Set<String> _guessedNextUrls = {};
  final Map<String, List<ChapterRef>> _catalogueMap = {};

  /// Chapter URLs that were tried and had no pages (the usual fate of a
  /// guessed "next chapter" when you're on the newest one).
  final Map<String, DateTime> _dead = {};
  static const Duration _deadTtl = Duration(minutes: 10);

  String? _lastCoverUrl;

  @override
  String? get lastCoverUrl => _lastCoverUrl;

  void _remember(String id, ScrapedChapterResult result) {
    _nextMap[id] = result.nextChapterUrl;
    _prevMap[id] = result.prevChapterUrl;
    _nextGuessed[id] = result.nextGuessed;
    if (result.nextGuessed && result.nextChapterUrl != null) {
      _guessedNextUrls.add(result.nextChapterUrl!);
    }
    if (result.availableChapters.isNotEmpty) {
      _catalogueMap[id] = result.availableChapters;
    }
    if (result.coverUrl != null && result.coverUrl!.isNotEmpty) {
      _lastCoverUrl = result.coverUrl;
    }
  }

  bool _isDead(String? id) {
    if (id == null) return false;
    final at = _dead[id];
    if (at == null) return false;
    if (DateTime.now().difference(at) > _deadTtl) {
      _dead.remove(id);
      return false;
    }
    return true;
  }

  @override
  Future<List<ReaderPageItem>> loadChapter(String chapterIdOrUrl) async {
    final result = await scrapeService.scrapeChapter(chapterIdOrUrl);
    _remember(chapterIdOrUrl, result);

    final isGuessed = _guessedNextUrls.contains(chapterIdOrUrl) ||
        _nextGuessed[chapterIdOrUrl] == true;

    if (result.needsVerification) {
      // Guessed next chapters must never prompt verification because they
      // frequently do not exist (404/interstitial). Mark as dead and return empty.
      if (isGuessed) {
        _dead[chapterIdOrUrl] = DateTime.now();
        return const [];
      }
      throw VerificationRequiredException(
        result.verificationUrl ?? chapterIdOrUrl,
      );
    }

    if (result.pages.isEmpty) {
      _dead[chapterIdOrUrl] = DateTime.now();
    } else {
      _dead.remove(chapterIdOrUrl);
    }

    final label = result.chapterLabel ?? '';
    return ReaderPageItem.buildGroupedItems(
      rawPages: result.pages,
      chapterId: chapterIdOrUrl,
      chapterLabel: label,
      referer: chapterIdOrUrl,
    );
  }

  @override
  Future<String?> getNextChapterId(String currentChapterIdOrUrl) async {
    if (!_nextMap.containsKey(currentChapterIdOrUrl)) {
      final res = await scrapeService.scrapeChapter(currentChapterIdOrUrl);
      if (!res.needsVerification) _remember(currentChapterIdOrUrl, res);
    }
    final next = _nextMap[currentChapterIdOrUrl];
    if (next == null || _isDead(next)) return null;
    return next;
  }

  @override
  Future<String?> refreshNextChapterId(String chapterId) async {
    final res =
        await scrapeService.scrapeChapter(chapterId, forceRefresh: true);
    if (res.needsVerification) {
      throw VerificationRequiredException(res.verificationUrl ?? chapterId);
    }
    if (res.pages.isNotEmpty || res.nextChapterUrl != null) {
      _remember(chapterId, res);
    }
    final next = _nextMap[chapterId];
    if (next == null) return null;
    // A real link on the live page beats any earlier "dead" verdict; a guess
    // gets another try only once its cool-down has passed.
    if (_nextGuessed[chapterId] != true) _dead.remove(next);
    return _isDead(next) ? null : next;
  }

  @override
  Future<String?> getPrevChapterId(String currentChapterIdOrUrl) async {
    if (!_prevMap.containsKey(currentChapterIdOrUrl)) {
      final res = await scrapeService.scrapeChapter(currentChapterIdOrUrl);
      if (!res.needsVerification) _remember(currentChapterIdOrUrl, res);
    }
    return _prevMap[currentChapterIdOrUrl];
  }

  @override
  Future<List<ChapterRef>> getAvailableChapters(
      String currentChapterIdOrUrl) async {
    if (_catalogueMap.containsKey(currentChapterIdOrUrl)) {
      return _catalogueMap[currentChapterIdOrUrl]!;
    }
    for (final list in _catalogueMap.values) {
      if (list.isNotEmpty) return list;
    }
    return const [];
  }
}

class MangaDexSource implements ChapterSource {
  MangaDexSource({
    required this.service,
    required this.store,
    required this.chapters,
  });

  final MangaDexService service;
  final ChapterStore store;
  final List<MdChapter> chapters; // oldest first

  @override
  String? get lastCoverUrl => null;

  @override
  Future<List<ReaderPageItem>> loadChapter(String chapterId) async {
    List<String>? urls = await store.loadUrls(chapterId);
    if (urls == null || urls.isEmpty) {
      urls = await service.pageUrls(chapterId);
      await store.saveUrls(chapterId, urls);
    }

    final ch = chapters.where((c) => c.id == chapterId).firstOrNull;
    final label = ch?.label ?? '';
    final count = urls.length;

    return List.generate(
      count,
      (i) => ReaderPageItem(
        url: urls![i],
        chapterId: chapterId,
        chapterLabel: label,
        pageIndex: i,
        totalInChapter: count,
      ),
    );
  }

  @override
  Future<String?> getNextChapterId(String currentChapterId) async {
    final idx = chapters.indexWhere((c) => c.id == currentChapterId);
    if (idx >= 0 && idx + 1 < chapters.length) {
      return chapters[idx + 1].id;
    }
    return null;
  }

  @override
  Future<String?> getPrevChapterId(String currentChapterId) async {
    final idx = chapters.indexWhere((c) => c.id == currentChapterId);
    if (idx > 0) {
      return chapters[idx - 1].id;
    }
    return null;
  }

  @override
  Future<List<ChapterRef>> getAvailableChapters(String currentChapterId) async {
    return chapters.map((c) => ChapterRef(url: c.id, label: c.label)).toList();
  }
}
