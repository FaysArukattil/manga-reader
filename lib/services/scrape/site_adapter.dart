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
    this.coverUrl,
    this.firstChapterUrl,
    this.needsVerification = false,
    this.verificationUrl,
  });

  final String chapterUrl;
  final List<String> pages;
  final String? title;
  final String? chapterLabel;
  final String? nextChapterUrl;
  final String? prevChapterUrl;
  final bool isWebtoon;
  final List<ChapterRef> availableChapters;
  final String? coverUrl;
  final String? firstChapterUrl;
  final bool needsVerification;
  final String? verificationUrl;

  ScrapedChapterResult copyWith({
    String? chapterUrl,
    List<String>? pages,
    String? title,
    String? chapterLabel,
    String? nextChapterUrl,
    String? prevChapterUrl,
    bool? isWebtoon,
    List<ChapterRef>? availableChapters,
    String? coverUrl,
    String? firstChapterUrl,
    bool? needsVerification,
    String? verificationUrl,
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
        coverUrl: coverUrl ?? this.coverUrl,
        firstChapterUrl: firstChapterUrl ?? this.firstChapterUrl,
        needsVerification: needsVerification ?? this.needsVerification,
        verificationUrl: verificationUrl ?? this.verificationUrl,
      );
}

abstract class SiteAdapter {
  /// Whether this adapter handles the given domain / host.
  bool matches(String host);

  /// Extract chapter pages, next/prev navigation, and labels from a parsed DOM.
  Future<ScrapedChapterResult> extract(dom.Document document, Uri pageUri);
}
