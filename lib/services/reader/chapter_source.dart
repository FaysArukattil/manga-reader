import '../mangadex_service.dart';
import '../page_cache.dart';
import '../scrape/scrape_service.dart';
import '../scrape/site_adapter.dart';

class ReaderPageItem {
  const ReaderPageItem({
    required this.url,
    required this.chapterId,
    required this.chapterLabel,
    required this.pageIndex,
    required this.totalInChapter,
    this.referer,
  });

  final String url;
  final String chapterId;
  final String chapterLabel;
  final int pageIndex;
  final int totalInChapter;
  final String? referer;

  String get pageKey => PageCache.keyFor(url);
}

abstract class ChapterSource {
  Future<List<ReaderPageItem>> loadChapter(String chapterIdOrUrl);
  Future<String?> getNextChapterId(String currentChapterIdOrUrl);
  Future<String?> getPrevChapterId(String currentChapterIdOrUrl);
  Future<List<ChapterRef>> getAvailableChapters(String currentChapterIdOrUrl);
}

class ScrapedSource implements ChapterSource {
  ScrapedSource({required this.scrapeService});

  final ScrapeService scrapeService;
  final Map<String, String?> _nextMap = {};
  final Map<String, String?> _prevMap = {};
  final Map<String, List<ChapterRef>> _catalogueMap = {};

  @override
  Future<List<ReaderPageItem>> loadChapter(String chapterIdOrUrl) async {
    final result = await scrapeService.scrapeChapter(chapterIdOrUrl);
    _nextMap[chapterIdOrUrl] = result.nextChapterUrl;
    _prevMap[chapterIdOrUrl] = result.prevChapterUrl;
    if (result.availableChapters.isNotEmpty) {
      _catalogueMap[chapterIdOrUrl] = result.availableChapters;
    }

    final label = result.chapterLabel ?? '';
    final count = result.pages.length;

    return List.generate(
      count,
      (i) => ReaderPageItem(
        url: result.pages[i],
        chapterId: chapterIdOrUrl,
        chapterLabel: label,
        pageIndex: i,
        totalInChapter: count,
        referer: chapterIdOrUrl,
      ),
    );
  }

  @override
  Future<String?> getNextChapterId(String currentChapterIdOrUrl) async {
    if (_nextMap.containsKey(currentChapterIdOrUrl)) {
      return _nextMap[currentChapterIdOrUrl];
    }
    final res = await scrapeService.scrapeChapter(currentChapterIdOrUrl);
    _nextMap[currentChapterIdOrUrl] = res.nextChapterUrl;
    if (res.availableChapters.isNotEmpty) {
      _catalogueMap[currentChapterIdOrUrl] = res.availableChapters;
    }
    return res.nextChapterUrl;
  }

  @override
  Future<String?> getPrevChapterId(String currentChapterIdOrUrl) async {
    if (_prevMap.containsKey(currentChapterIdOrUrl)) {
      return _prevMap[currentChapterIdOrUrl];
    }
    final res = await scrapeService.scrapeChapter(currentChapterIdOrUrl);
    _prevMap[currentChapterIdOrUrl] = res.prevChapterUrl;
    if (res.availableChapters.isNotEmpty) {
      _catalogueMap[currentChapterIdOrUrl] = res.availableChapters;
    }
    return res.prevChapterUrl;
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
