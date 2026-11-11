# Shelfmark

A pure, distraction-free manga reader and tracker: one shelf for every series you read across any website. It scrapes chapter content directly, strips all ads, popups, and website chrome, and presents chapters as an Apple Books-tier native 3D flippable book or continuous vertical webtoon.

> **Privacy Notice**: Shelfmark stores links and reading progress only. No manga content is hosted or redistributed. Page images are cached temporarily on-device strictly for reading and prefetching.

---

## Features

- **Universal Native Book Reader**:
  - Full-bleed pages on pure black with zero website chrome, headers, footers, popups, or ads.
  - 3D perspective page-flip physics (`rotateY` transform) following your gesture.
  - Multi-mode reading: Manga (Right-to-Left), Book (Left-to-Right), and Webtoon (Continuous vertical scroll).
  - Pinch-to-zoom (`InteractiveViewer`) to inspect fine panel artwork.
  - Ambient book-opening loading placeholder with cover art backdrop.
- **Multi-Tier Automatic Scraper (`ScrapeService`)**:
  - **Tier 1 (Fast Path)**: Ultra-fast HTTP GET request with realistic mobile `User-Agent` and `package:html` DOM parsing.
  - **Tier 2 (Rendered Path Fallback)**: Automatically spins up a temporary `HeadlessInAppWebView` with aggressive content blockers for JavaScript-rendered or lazy-loaded sites, auto-scrolls to trigger images, and extracts DOM assets before immediate disposal.
  - **Hotlink Protection**: Automatically passes matching `Referer` and mobile `User-Agent` headers to `CachedNetworkImage` and `PageCache`.
- **Seamless Chapter Streaming**:
  - Reading chapter N to N+1 is completely seamless: next chapters are scraped and appended in the background before you reach the end. No disruptive "Next Chapter" buttons required.
  - Discreet chapter seam indicator when crossing chapters.
  - Calm "You're all caught up" card that polls quietly in the background (every 30s) and appends newly released chapters live.
- **Bulletproof Progress Sync**:
  - Instant local saving to `SharedPreferences` on every page turn (debounced 500ms) and immediately upon exit or app pause.
  - Background Firestore cloud sync throttled to battery-friendly intervals.
  - Resumption saves exact `chapterUrl`, `pageIndex`, and `pageKey` (hash of the image URL path) so reopening never flashes page 1.
- **MangaDex & Web Series Unified**:
  - Both MangaDex official API series and scraped web series share the exact same unified reader engine (`UnifiedReaderPage`).

---

## Adding Custom Site Adapters

While `GenericSiteAdapter` handles 98%+ of manga sites automatically via standard reader containers and image heuristics, stubborn or proprietary sites can be customized in ~10 lines of code:

```dart
class MyCustomSiteAdapter implements SiteAdapter {
  const MyCustomSiteAdapter();

  @override
  bool matches(String host) => host.contains('mysite.com');

  @override
  Future<ScrapedChapterResult> extract(dom.Document document, Uri pageUri) async {
    // 1. Target custom image selectors
    final imgs = document.querySelectorAll('.custom-chapter-images img');
    final pages = imgs.map((e) => e.attributes['data-src'] ?? e.attributes['src'])
                      .whereType<String>().toList();

    // 2. Target custom next/prev navigation links
    final nextUrl = document.querySelector('a.custom-next-btn')?.attributes['href'];

    return ScrapedChapterResult(
      chapterUrl: pageUri.toString(),
      pages: pages,
      nextChapterUrl: nextUrl,
      chapterLabel: UrlTools.chapterLabel(pageUri.toString()),
    );
  }
}
```

Register your adapter in `ScrapeService`:
```dart
scrapeService.registerAdapter(const MyCustomSiteAdapter());
```

---

## Setup & Running

1. Run `flutter pub get`
2. Connect a device or launch an emulator
3. Run `flutter run`
4. Run tests: `flutter test`
5. Run analysis: `flutter analyze`
