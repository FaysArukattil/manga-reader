import 'package:flutter_test/flutter_test.dart';
import 'package:shelfmark/blocs/unified_reader_cubit.dart';
import 'package:shelfmark/models/series.dart';
import 'package:shelfmark/services/page_cache.dart';
import 'package:shelfmark/services/reader/chapter_source.dart';
import 'package:shelfmark/services/scrape/site_adapter.dart';

class FakeChapterSource implements ChapterSource {
  FakeChapterSource({
    required this.chapters,
    this.nextMap = const {},
  });

  final Map<String, List<ReaderPageItem>> chapters;
  final Map<String, String> nextMap;

  @override
  String? get lastCoverUrl => null;

  @override
  Future<List<ReaderPageItem>> loadChapter(String chapterId) async {
    return chapters[chapterId] ?? [];
  }

  @override
  Future<String?> getNextChapterId(String currentChapterId) async {
    return nextMap[currentChapterId];
  }

  @override
  Future<String?> getPrevChapterId(String currentChapterId) async {
    return null;
  }

  @override
  Future<List<ChapterRef>> getAvailableChapters(String currentChapterId) async {
    return chapters.keys.map((k) => ChapterRef(url: k, label: k)).toList();
  }
}

void main() {
  group('UnifiedReaderCubit', () {
    late Series testSeries;

    setUp(() {
      testSeries = Series(
        id: 's1',
        title: 'Solo Leveling',
        url: 'https://example.com/ch-1',
        host: 'example.com',
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );
    });

    test('loads initial chapter and restores position by pageKey', () async {
      final ch1Pages = List.generate(
        5,
        (i) => ReaderPageItem(
          url: 'https://cdn.example.com/p$i.jpg',
          chapterId: 'ch1',
          chapterLabel: 'Ch 1',
          pageIndex: i,
          totalInChapter: 5,
        ),
      );

      final fakeSource = FakeChapterSource(chapters: {'ch1': ch1Pages});
      final cubit = UnifiedReaderCubit(
        source: fakeSource,
        series: testSeries,
        startChapterId: 'ch1',
        startPageKey: '/p3.jpg',
      );

      await cubit.init();

      expect(cubit.state.loading, isFalse);
      expect(cubit.state.pages.length, equals(5));
      // Restored to matching pageKey index 3
      expect(cubit.state.currentIndex, equals(3));
      expect(cubit.state.currentPageInChapter, equals(4));

      await cubit.close();
    });

    test('seamlessly appends next chapter and handles caught up state',
        () async {
      final ch1 = List.generate(
        3,
        (i) => ReaderPageItem(
          url: 'https://cdn.example.com/ch1_p$i.jpg',
          chapterId: 'ch1',
          chapterLabel: 'Ch 1',
          pageIndex: i,
          totalInChapter: 3,
        ),
      );
      final ch2 = List.generate(
        3,
        (i) => ReaderPageItem(
          url: 'https://cdn.example.com/ch2_p$i.jpg',
          chapterId: 'ch2',
          chapterLabel: 'Ch 2',
          pageIndex: i,
          totalInChapter: 3,
        ),
      );

      final fakeSource = FakeChapterSource(
        chapters: {'ch1': ch1, 'ch2': ch2},
        nextMap: {'ch1': 'ch2'},
      );

      final cubit = UnifiedReaderCubit(
        source: fakeSource,
        series: testSeries,
        startChapterId: 'ch1',
      );

      await cubit.init();
      expect(cubit.state.pages.length, equals(6)); // ch2 was pre-fetched!

      // Navigate to end of stream
      cubit.onPageChanged(5);
      await pumpEventQueue();
      expect(cubit.state.currentIndex, equals(5));
      expect(cubit.state.isAllCaughtUp, isTrue);

      await cubit.close();
    });

    test('ReaderPageItem.buildGroupedItems combines 111 sliced strips into ~28 seamless pages', () {
      final slices111 = List.generate(
        111,
        (i) => 'https://imgsrv5.com/comic/chapter-59/$i.jpg',
      );

      final pages = ReaderPageItem.buildGroupedItems(
        rawPages: slices111,
        chapterId: 'ch59',
        chapterLabel: 'Chapter 59',
      );

      // Group size should be 4 slices per page -> 28 pages
      expect(pages.length, equals(28));
      expect(pages[0].allUrls.length, equals(4));
      expect(pages[0].allUrls, equals([
        'https://imgsrv5.com/comic/chapter-59/0.jpg',
        'https://imgsrv5.com/comic/chapter-59/1.jpg',
        'https://imgsrv5.com/comic/chapter-59/2.jpg',
        'https://imgsrv5.com/comic/chapter-59/3.jpg',
      ]));
      expect(pages[0].totalInChapter, equals(28));
      expect(pages[27].allUrls.length, equals(3)); // 111 - 27*4 = 3 remaining slices

      // Test matchesKey works for any slice in the page
      final keyForSlice2 = PageCache.keyFor('https://imgsrv5.com/comic/chapter-59/2.jpg');
      expect(pages[0].matchesKey(keyForSlice2), isTrue);
    });

    test('ReaderPageItem.buildGroupedItems leaves standard 28-page chapters untouched', () {
      final slices28 = List.generate(
        28,
        (i) => 'https://imgsrv5.com/comic/chapter-58/$i.jpg',
      );

      final pages = ReaderPageItem.buildGroupedItems(
        rawPages: slices28,
        chapterId: 'ch58',
        chapterLabel: 'Chapter 58',
      );

      expect(pages.length, equals(28));
      expect(pages[0].allUrls.length, equals(1));
      expect(pages[0].url, equals('https://imgsrv5.com/comic/chapter-58/0.jpg'));
    });

    test('emits needsVerification when VerificationRequiredException is thrown',
        () async {
      final verifySource = _VerifyingFakeChapterSource(
        challengeUrl: 'https://example.com/cf-challenge',
      );

      final cubit = UnifiedReaderCubit(
        source: verifySource,
        series: testSeries,
        startChapterId: 'ch-locked',
      );

      await cubit.init();

      expect(cubit.state.loading, isFalse);
      expect(cubit.state.needsVerification, isTrue);
      expect(
        cubit.state.verificationUrl,
        equals('https://example.com/cf-challenge'),
      );

      await cubit.close();
    });
  });
}

class _VerifyingFakeChapterSource implements ChapterSource {
  _VerifyingFakeChapterSource({required this.challengeUrl});
  final String challengeUrl;

  @override
  String? get lastCoverUrl => null;

  @override
  Future<List<ReaderPageItem>> loadChapter(String chapterId) async {
    throw VerificationRequiredException(challengeUrl);
  }

  @override
  Future<String?> getNextChapterId(String currentChapterId) async => null;

  @override
  Future<String?> getPrevChapterId(String currentChapterId) async => null;

  @override
  Future<List<ChapterRef>> getAvailableChapters(String currentChapterId) async =>
      const [];
}
