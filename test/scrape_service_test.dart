import 'package:flutter_test/flutter_test.dart';
import 'package:html/dom.dart' as dom;
import 'package:manga_reader/services/scrape/cf_session.dart';
import 'package:manga_reader/services/scrape/generic_site_adapter.dart';

void main() {
  group('GenericSiteAdapter', () {
    const adapter = GenericSiteAdapter();

    test('extracts images from reader containers and filters junk', () async {
      const html = '''
      <!DOCTYPE html>
      <html>
        <head>
          <title>Solo Leveling - Chapter 120</title>
          <link rel="next" href="/manga/solo-leveling/chapter-121" />
          <link rel="prev" href="/manga/solo-leveling/chapter-119" />
        </head>
        <body>
          <header>
            <img src="/images/site-logo.png" width="120" height="40" alt="logo" />
            <img src="/avatars/user1.jpg" alt="avatar" />
          </header>
          <div class="adsbygoogle">
            <img src="https://doubleclick.net/ad.gif" alt="ad" />
          </div>
          <div id="readerarea">
            <img data-src="https://cdn.example.com/ch120/01.jpg" alt="p1" />
            <img data-lazy-src="https://cdn.example.com/ch120/02.jpg" alt="p2" />
            <img src="https://cdn.example.com/ch120/03.jpg" alt="p3" />
            <noscript>
              <img src="https://cdn.example.com/ch120/04.jpg" alt="p4" />
            </noscript>
          </div>
          <footer>
            <img src="/images/discord-badge.png" />
          </footer>
        </body>
      </html>
      ''';

      final doc = dom.Document.html(html);
      final uri =
          Uri.parse('https://example.com/manga/solo-leveling/chapter-120');

      final result = await adapter.extract(doc, uri);

      expect(result.pages.length, equals(4));
      expect(result.pages[0], equals('https://cdn.example.com/ch120/01.jpg'));
      expect(result.pages[1], equals('https://cdn.example.com/ch120/02.jpg'));
      expect(result.pages[2], equals('https://cdn.example.com/ch120/03.jpg'));
      expect(result.pages[3], equals('https://cdn.example.com/ch120/04.jpg'));

      // Navigation discovery
      expect(result.nextChapterUrl,
          equals('https://example.com/manga/solo-leveling/chapter-121'));
      expect(result.prevChapterUrl,
          equals('https://example.com/manga/solo-leveling/chapter-119'));
    });

    test('resolves relative URLs and protocol-relative URLs', () async {
      const html = '''
      <div class="reading-content">
        <img data-src="//cdn.example.com/ch1/01.jpg" />
        <img data-src="/images/manga/ch1/02.png" />
        <img data-src="03.webp" />
      </div>
      ''';

      final doc = dom.Document.html(html);
      final uri = Uri.parse('https://manga.site.com/series/title/ch-1/');

      final result = await adapter.extract(doc, uri);

      expect(
          result.pages,
          equals([
            'https://cdn.example.com/ch1/01.jpg',
            'https://manga.site.com/images/manga/ch1/02.png',
            'https://manga.site.com/series/title/ch-1/03.webp',
          ]));
    });

    test('discovers next chapter via class and anchor text', () async {
      const html = '''
      <div id="chapter-content">
        <img src="https://cdn.example.com/1.jpg" />
        <img src="https://cdn.example.com/2.jpg" />
      </div>
      <div class="nav-links">
        <a class="ch-prev-btn" href="https://example.com/ch-1">Prev</a>
        <a class="ch-next-btn" href="https://example.com/ch-3">Next Chapter »</a>
      </div>
      ''';

      final doc = dom.Document.html(html);
      final uri = Uri.parse('https://example.com/ch-2');

      final result = await adapter.extract(doc, uri);

      expect(result.nextChapterUrl, equals('https://example.com/ch-3'));
      expect(result.prevChapterUrl, equals('https://example.com/ch-1'));
    });

    test('extracts images from embedded ts_reader scripts and chapter dropdown',
        () async {
      const html = '''
      <!DOCTYPE html>
      <html>
        <head>
          <title>Chapter 5 - Epic Manga</title>
        </head>
        <body>
          <select id="select-chapter">
            <option value="https://example.com/ch-4">Chapter 4</option>
            <option value="https://example.com/ch-5" selected>Chapter 5</option>
            <option value="https://example.com/ch-6">Chapter 6</option>
          </select>
          <script>
            ts_reader.run({
              "prevUrl": "https://example.com/ch-4",
              "nextUrl": "https://example.com/ch-6",
              "sources": [{
                "source": "Default",
                "images": [
                  "https://cdn.example.com/page1.webp",
                  "https://cdn.example.com/page2.webp",
                  "https://cdn.example.com/page3.webp"
                ]
              }]
            });
          </script>
        </body>
      </html>
      ''';

      final doc = dom.Document.html(html);
      final uri = Uri.parse('https://example.com/ch-5');

      final result = await adapter.extract(doc, uri);

      expect(result.pages.length, equals(3));
      expect(result.pages[0], equals('https://cdn.example.com/page1.webp'));
      expect(result.pages[1], equals('https://cdn.example.com/page2.webp'));
      expect(result.pages[2], equals('https://cdn.example.com/page3.webp'));
      expect(result.availableChapters.length, equals(3));
      expect(result.nextChapterUrl, equals('https://example.com/ch-6'));
      expect(result.prevChapterUrl, equals('https://example.com/ch-4'));
    });

    test('GenericSiteAdapter detects Cloudflare and Turnstile verification challenges',
        () async {
      const adapter = GenericSiteAdapter();
      const html = '''
      <!DOCTYPE html>
      <html>
        <head>
          <title>Just a moment...</title>
        </head>
        <body>
          <div id="cf-turnstile"></div>
          <p>Checking your browser before accessing the website.</p>
        </body>
      </html>
      ''';

      final doc = dom.Document.html(html);
      final uri = Uri.parse('https://manga-secure.com/chapter-1');

      final result = await adapter.extract(doc, uri);

      expect(result.needsVerification, isTrue);
      expect(result.verificationUrl, equals('https://manga-secure.com/chapter-1'));
    });

    test('GenericSiteAdapter extracts book cover and Start Reading button from overview page',
        () async {
      const adapter = GenericSiteAdapter();
      const html = '''
      <!DOCTYPE html>
      <html>
        <head>
          <title>One Piece - Read Manga</title>
          <meta property="og:image" content="https://cdn.example.com/one-piece-cover.jpg" />
        </head>
        <body>
          <div class="manga-poster">
            <img src="https://cdn.example.com/one-piece-cover.jpg" alt="One Piece Cover" />
          </div>
          <a class="read-now" href="/manga/one-piece/chapter-1">Start Reading</a>
          <div class="chapters">
            <a href="/manga/one-piece/chapter-1">Chapter 1</a>
            <a href="/manga/one-piece/chapter-2">Chapter 2</a>
          </div>
        </body>
      </html>
      ''';

      final doc = dom.Document.html(html);
      final uri = Uri.parse('https://example.com/manga/one-piece');

      final result = await adapter.extract(doc, uri);

      expect(result.coverUrl, equals('https://cdn.example.com/one-piece-cover.jpg'));
      expect(result.firstChapterUrl, equals('https://example.com/manga/one-piece/chapter-1'));
      expect(result.availableChapters.length, equals(2));
    });

    test('extracts images from WordPress ts_reader with JSON escaped slashes and ignores sidebar recommendations',
        () async {
      const adapter = GenericSiteAdapter();
      const html = r'''
      <!DOCTYPE html>
      <html>
        <head>
          <title>The Second Eunuch Regains His Manhood Chapter 103 &#8211; Thunderscans EN</title>
        </head>
        <body>
          <div id="readerarea"></div>
          <aside class="sidebar-widget">
            <div class="widget-post">
              <img src="https://en-thunderscans.com/wp-content/uploads/rec1.jpg" />
              <img src="https://en-thunderscans.com/wp-content/uploads/rec2.jpg" />
              <img src="https://en-thunderscans.com/wp-content/uploads/rec3.jpg" />
              <img src="https://en-thunderscans.com/wp-content/uploads/rec4.jpg" />
              <img src="https://en-thunderscans.com/wp-content/uploads/rec5.jpg" />
            </div>
          </aside>
          <script>
            ts_reader.run({
              "prevUrl": "https:\/\/en-thunderscans.com\/the-second-eunuch-regains-his-manhood-chapter-102\/",
              "nextUrl": "https:\/\/en-thunderscans.com\/the-second-eunuch-regains-his-manhood-chapter-104\/",
              "sources": [{
                "source": "Default",
                "images": [
                  "https:\/\/en-thunderscans.com\/wp-content\/uploads\/manga\/0001.webp",
                  "https:\/\/en-thunderscans.com\/wp-content\/uploads\/manga\/0002.webp",
                  "https:\/\/en-thunderscans.com\/wp-content\/uploads\/manga\/0003.webp"
                ]
              }]
            });
          </script>
        </body>
      </html>
      ''';

      final doc = dom.Document.html(html);
      final uri = Uri.parse('https://en-thunderscans.com/the-second-eunuch-regains-his-manhood-chapter-103/');

      final result = await adapter.extract(doc, uri);

      expect(result.pages.length, equals(3));
      expect(result.pages[0], equals('https://en-thunderscans.com/wp-content/uploads/manga/0001.webp'));
      expect(result.pages[1], equals('https://en-thunderscans.com/wp-content/uploads/manga/0002.webp'));
      expect(result.pages[2], equals('https://en-thunderscans.com/wp-content/uploads/manga/0003.webp'));
      expect(result.nextChapterUrl, equals('https://en-thunderscans.com/the-second-eunuch-regains-his-manhood-chapter-104/'));
      expect(result.prevChapterUrl, equals('https://en-thunderscans.com/the-second-eunuch-regains-his-manhood-chapter-102/'));
    });

    test('descending catalogue correctly marks latest chapter with null nextChapterUrl and ignores disabled links', () async {
      const html = '''
      <!DOCTYPE html>
      <html>
        <body>
          <div class="reading-content">
            <img src="https://cdn.example.com/p1.jpg" />
            <img src="https://cdn.example.com/p2.jpg" />
          </div>
          <select id="select-chapter">
            <option value="https://example.com/ch-93/" selected>Chapter 93</option>
            <option value="https://example.com/ch-92/">Chapter 92</option>
            <option value="https://example.com/ch-91/">Chapter 91</option>
          </select>
          <div class="nav-links">
            <a class="btn prev_page" href="https://example.com/ch-92/">Prev</a>
            <a class="btn next_page disabled" href="#">Next</a>
          </div>
        </body>
      </html>
      ''';

      final doc = dom.Document.html(html);
      final uri = Uri.parse('https://example.com/ch-93/');

      final result = await adapter.extract(doc, uri);

      expect(result.pages.length, equals(2));
      // Since ch-93 is the newest in the catalogue, nextChapterUrl must be NULL!
      expect(result.nextChapterUrl, isNull);
      expect(result.prevChapterUrl, equals('https://example.com/ch-92/'));
    });

    test('extracts comix.to initial-data metadata and recognizes latest chapter', () async {
      const html = r'''
      <!DOCTYPE html>
      <html>
        <head>
          <title>The Fox-Eyed Villain of the Demon Academy · Ch.60</title>
        </head>
        <body class="rpage-body">
          <div id="app-root"></div>
          <script type="application/json" id="initial-data">
          {
            "page": "read",
            "queries": {
              "[\"manga\",\"detail\",\"5rj7\"]": {
                "title": "The Fox-Eyed Villain of the Demon Academy",
                "poster": {
                  "large": "/images/covers/d9/6f/d96fe51439757583cf72f6e7de84a0969175c0d1.jpg"
                },
                "latestChapter": 60,
                "firstChapterUrl": "/title/5rj7-the-fox-eyed-villain-of-the-demon-academy/6658172-chapter-1"
              }
            },
            "read": {
              "chapterId": 7301644,
              "chapterNumber": 60
            }
          }
          </script>
        </body>
      </html>
      ''';

      final doc = dom.Document.html(html);
      final uri = Uri.parse(
        'https://comix.to/title/5rj7-the-fox-eyed-villain-of-the-demon-academy/7301644-chapter-60',
      );

      final result = await adapter.extract(doc, uri);

      expect(result.title, equals('The Fox-Eyed Villain of the Demon Academy'));
      expect(
        result.coverUrl,
        equals(
          'https://comix.to/images/covers/d9/6f/d96fe51439757583cf72f6e7de84a0969175c0d1.jpg',
        ),
      );
      expect(
        result.firstChapterUrl,
        equals(
          'https://comix.to/title/5rj7-the-fox-eyed-villain-of-the-demon-academy/6658172-chapter-1',
        ),
      );
      // Because chapter 60 is latestChapter, nextChapterUrl must be null
      expect(result.nextChapterUrl, isNull);
    });

    test('extracts images from comix.to rpage-main structure', () async {
      const html = '''
      <main class="rpage-main rpage-main--vertical">
        <div class="rpage-main__inner">
          <div class="rpage-page" data-page="1">
            <img class="rpage-page__img" src="https://cdn.example.com/p1.webp" width="800" height="1200" />
          </div>
          <div class="rpage-page" data-page="2">
            <img class="rpage-page__img" src="https://cdn.example.com/p2.webp" width="800" height="1200" />
          </div>
        </div>
      </main>
      ''';

      final doc = dom.Document.html(html);
      final uri = Uri.parse('https://comix.to/title/manga/ch-1');

      final result = await adapter.extract(doc, uri);

      expect(result.pages.length, equals(2));
      expect(result.pages[0], equals('https://cdn.example.com/p1.webp'));
      expect(result.pages[1], equals('https://cdn.example.com/p2.webp'));
    });

    test('imageHeaders omits Referer for comix.to and .site CDNs to avoid 403 blocks', () {
      final headersComix = CfSession.imageHeaders(
        'https://lov.softtouchgoods.site/hi/page1.webp',
        'https://comix.to/title/manga/ch-60',
      );
      expect(headersComix.containsKey('Referer'), isFalse);

      final headersNormal = CfSession.imageHeaders(
        'https://cdn.manga.com/images/page1.jpg',
        'https://mangasite.com/chapter-1',
      );
      expect(headersNormal['Referer'], equals('https://mangasite.com/chapter-1'));
    });
  });
}
