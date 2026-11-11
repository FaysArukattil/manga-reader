import 'package:flutter_test/flutter_test.dart';
import 'package:html/dom.dart' as dom;
import 'package:shelfmark/services/scrape/generic_site_adapter.dart';

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
  });
}
