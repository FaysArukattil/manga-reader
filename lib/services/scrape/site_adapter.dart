import 'package:html/dom.dart' as dom;

class ChapterRef {
  const ChapterRef({
    required this.url,
    required this.label,
  });

  final String url;
  final String label;

  @override
  String toString() => 'ChapterRef($label, $url)';
}

class ScrapedChapterResult {
  const ScrapedChapterResult({
    required this.chapterUrl,
    required this.pages,
    this.title,
    this.chapterLabel,
    this.nextChapterUrl,
    this.prevChapterUrl,
    this.isWebtoon = false,
    this.availableChapters = const [],
  });

  final String chapterUrl;
  final List<String> pages;
  final String? title;
  final String? chapterLabel;
  final String? nextChapterUrl;
  final String? prevChapterUrl;
  final bool isWebtoon;
  final List<ChapterRef> availableChapters;

  ScrapedChapterResult copyWith({
    String? chapterUrl,
    List<String>? pages,
    String? title,
    String? chapterLabel,
    String? nextChapterUrl,
    String? prevChapterUrl,
    bool? isWebtoon,
    List<ChapterRef>? availableChapters,
  }) =>
      ScrapedChapterResult(
        chapterUrl: chapterUrl ?? this.chapterUrl,
        pages: pages ?? this.pages,
        title: title ?? this.title,
        chapterLabel: chapterLabel ?? this.chapterLabel,
        nextChapterUrl: nextChapterUrl ?? this.nextChapterUrl,
        prevChapterUrl: prevChapterUrl ?? this.prevChapterUrl,
        isWebtoon: isWebtoon ?? this.isWebtoon,
        availableChapters: availableChapters ?? this.availableChapters,
      );
}

abstract class SiteAdapter {
  /// Whether this adapter handles the given domain / host.
  bool matches(String host);

  /// Extract chapter pages, next/prev navigation, and labels from a parsed DOM.
  Future<ScrapedChapterResult> extract(dom.Document document, Uri pageUri);
}
