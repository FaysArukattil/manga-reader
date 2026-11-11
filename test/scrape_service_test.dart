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
  });
}
