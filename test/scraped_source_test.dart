import 'package:flutter_test/flutter_test.dart';
import 'package:shelfmark/core/url_tools.dart';
import 'package:shelfmark/services/reader/chapter_source.dart';
import 'package:shelfmark/services/scrape/scrape_service.dart';
import 'package:shelfmark/services/scrape/site_adapter.dart';

typedef _Handler = ScrapedChapterResult Function(String url, bool force);

class _FakeScrape extends ScrapeService {
  _FakeScrape(this.handler);
  final _Handler handler;
  final List<String> calls = [];

  @override
  Future<ScrapedChapterResult> scrapeChapter(
    String url, {
    bool forceRefresh = false,
  }) async {
    calls.add('${forceRefresh ? 'refresh:' : ''}$url');
    return handler(url, forceRefresh);
  }
}

ScrapedChapterResult _chapter(
  String url, {
  String? next,
  bool guessed = false,
  int pages = 3,
}) =>
    ScrapedChapterResult(
      chapterUrl: url,
      pages: List.generate(pages, (i) => '$url/p$i.jpg'),
      nextChapterUrl: next,
      nextGuessed: guessed,
    );

void main() {
  group('ScrapedSource', () {
    test('a guessed next chapter that has no pages means "caught up"',
        () async {
      final scrape = _FakeScrape((url, force) {
        if (url == 'https://x.com/ch-1') {
          return _chapter(url, next: 'https://x.com/ch-2', guessed: true);
        }
        return ScrapedChapterResult(chapterUrl: url, pages: const []);
      });
      final source = ScrapedSource(scrapeService: scrape);

      await source.loadChapter('https://x.com/ch-1');
      expect(await source.getNextChapterId('https://x.com/ch-1'),
          equals('https://x.com/ch-2'));

      // Trying the guess finds nothing -> remembered as dead.
      final none = await source.loadChapter('https://x.com/ch-2');
      expect(none, isEmpty);
      expect(await source.getNextChapterId('https://x.com/ch-1'), isNull);
    });

    test('refresh picks up a real new chapter link', () async {
      var published = false;
      final scrape = _FakeScrape((url, force) {
        if (url == 'https://x.com/ch-1') {
          return _chapter(
            url,
            next: published ? 'https://x.com/ch-2' : null,
          );
        }
        return _chapter(url);
      });
      final source = ScrapedSource(scrapeService: scrape);

      await source.loadChapter('https://x.com/ch-1');
      expect(await source.getNextChapterId('https://x.com/ch-1'), isNull);

      published = true;
      // Cached view still says "nothing new"; only a refresh sees it.
      expect(await source.getNextChapterId('https://x.com/ch-1'), isNull);
      expect(await source.refreshNextChapterId('https://x.com/ch-1'),
          equals('https://x.com/ch-2'));
      expect(await source.getNextChapterId('https://x.com/ch-1'),
          equals('https://x.com/ch-2'));
    });

    test('verification during refresh is surfaced, not swallowed', () async {
      final scrape = _FakeScrape((url, force) {
        if (force) {
          return ScrapedChapterResult(
            chapterUrl: url,
            pages: const [],
            needsVerification: true,
            verificationUrl: url,
          );
        }
        return _chapter(url);
      });
      final source = ScrapedSource(scrapeService: scrape);
      await source.loadChapter('https://x.com/ch-1');
      expect(
        () => source.refreshNextChapterId('https://x.com/ch-1'),
        throwsA(isA<VerificationRequiredException>()),
      );
    });

    test('UrlTools.titleFromUrl cleanly extracts title from various URL slugs', () {
      expect(
        UrlTools.titleFromUrl('https://en-thunderscans.com/the-second-eunuch-regains-his-manhood-chapter-103/'),
        equals('The Second Eunuch Regains His Manhood'),
      );
      expect(
        UrlTools.titleFromUrl('https://www.mgeko.cc/reader/en/did-someone-force-you-to-become-chapter-58-eng-li/'),
        equals('Did Someone Force You To Become'),
      );
      expect(
        UrlTools.titleFromUrl('https://site.com/series/one-piece/chapter-1100'),
        equals('One Piece'),
      );
    });

    test('a guessed next chapter that requires verification does NOT throw and is marked dead', () async {
      final scrape = _FakeScrape((url, force) {
        if (url == 'https://x.com/ch-93') {
          return _chapter(url, next: 'https://x.com/ch-94', guessed: true);
        }
        if (url == 'https://x.com/ch-94') {
          // CF challenge or 404 interstitial on the non-existent guessed chapter
          return const ScrapedChapterResult(
            chapterUrl: 'https://x.com/ch-94',
            pages: [],
            needsVerification: true,
            verificationUrl: 'https://x.com/ch-94',
          );
        }
        return ScrapedChapterResult(chapterUrl: url, pages: const []);
      });
      final source = ScrapedSource(scrapeService: scrape);

      await source.loadChapter('https://x.com/ch-93');
      expect(await source.getNextChapterId('https://x.com/ch-93'), equals('https://x.com/ch-94'));

      // Trying the guessed chapter should NOT throw VerificationRequiredException
      final pages = await source.loadChapter('https://x.com/ch-94');
      expect(pages, isEmpty);

      // Now ch-94 is marked dead, so next chapter ID becomes null (caught up!)
      expect(await source.getNextChapterId('https://x.com/ch-93'), isNull);
    });
  });
}
