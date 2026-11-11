# Shelfmark — Implementation Progress

## Goal
Transform Shelfmark from a website-embedding viewer into a universal, content-only native reader across any manga/comic website, featuring seamless chapter streaming, flippable 3D page turns or vertical reels, zero ad clutter, automatic background updates, and rock-solid local & cloud progress resumption, followed by a premium Apple Books-tier UI overhaul.

## Architecture decisions
1. **Generic Scraping Engine (`ScrapeService` + `SiteAdapter`)**:
   - Tier 1: Fast HTTP GET + DOM parsing (`package:html`) with realistic mobile headers (`User-Agent`, `Referer`, `Accept`), ad/junk domain filtering, and lazy-loading resolution.
   - Tier 2: Headless WebView (`HeadlessInAppWebView`) with content blockers (`ad_block.dart`), scroll triggering for lazy loaders, and script extraction. Immediately disposed after extraction to preserve battery.
   - Tier 3: Adapter Registry (`SiteAdapter` interface): Generic adapter handles standard manga/webtoon containers, plus extensible per-site adapters for custom selectors.
2. **Unified Reader Core (`ChapterSource` + `UnifiedReaderCubit`)**:
   - Abstract `ChapterSource` base with implementations for `MangaDexSource` and `ScrapedSource`.
   - Single reader engine (`UnifiedReaderPage` + `UnifiedReaderCubit`) shared by both MangaDex and scraped web series.
   - Continuous page stream with invisible chapter seam markers — swiping across chapters is completely seamless without any required tap or button.
   - Background prefetching of adjacent pages with hotlink-safe headers (`Referer`, `User-Agent`) + pre-scraping the next chapter before reaching chapter end.
3. **Local-First & Cloud-Synced Progress (`LocalProgressStore`)**:
   - Progress saved instantly to `shared_preferences` (debounced 500ms on page change, immediate on pop/pause/dispose).
   - Syncs to Firestore throttled (every 10s or forced on leave/pause).
   - Tracks `chapterUrl`, `pageIndex`, `pageKey` (SHA/hash of image URL path), and `pageOffset` for webtoon strips.
   - Resuming loads saved chapter, jumps directly to `pageKey` / `pageIndex` without page 1 flash.
4. **Automatic New Chapter Discovery**:
   - Reaching end checks for next chapter, shows calm "You're all caught up" card, and polls quietly in background (every 30s).
   - When a new chapter drops, it appends live to the stream.
   - Periodic background check in `LibraryBloc` across shelf entries with `hasNew` badge.
5. **Smooth Loading & Pure Book Presentation**:
   - Replaced jarring black screen with ambient blurred-cover book opening placeholder.
   - Full-bleed pages with 3D perspective page-flip physics (`rotateY` transform).
   - Zero website chrome, zero ads, zero intrusive buttons.
6. **Design System & Micro-Interactions**:
   - Refined dark-first Obsidian/Emerald theme (`AppColors`, `AppTheme`, `AppThemeTokens`).
   - Reusable `ShimmerBox` skeleton loaders and `PressableScale` scale-on-press with tactile haptic feedback.

## Checklist

### Phase 1: Universal Native Reader (No Website UI)
- [x] **M1.1: Dependencies & Data Models**
  - [x] Add `html` and `shared_preferences` to `pubspec.yaml`
  - [x] Update `Series` model with `chapterUrl`, `pageIndex`, `pageKey`, `pageOffset`, `vertical`, `rtl`, `lastCheckedAt`, `newestChapterUrl`, `seenChapterUrl`, keeping backwards compatibility with `url` and `scroll`
  - [x] Update `firestore.rules` for the new fields
  - [x] Update `LibraryRepository` to persist and read extended fields
  - [x] Add `LocalProgressStore` using `shared_preferences`
- [x] **M1.2: Scraping Engine & Site Adapters**
  - [x] Implement `SiteAdapter` interface and `GenericSiteAdapter`
  - [x] Implement `ScrapeService` with Fast Path (HTTP + `package:html`)
  - [x] Implement Headless WebView fallback path with auto-scroll and script extraction
  - [x] Implement next/previous chapter URL resolver and chapter label parser
  - [x] Implement hotlink-safe image loading headers (`Referer`, `User-Agent`) for `PageCache` & `CachedNetworkImage`
  - [x] Write unit tests with HTML fixtures for image extraction, ad filtering, relative URLs, and next/prev resolution
- [x] **M1.3: Unified Chapter Source & Reader Engine**
  - [x] Define `ChapterSource` contract with `MangaDexSource` and `ScrapedSource`
  - [x] Refactor reader pager into unified `UnifiedReaderPage` & `UnifiedReaderCubit`
  - [x] Implement seamless chapter-to-chapter streaming (no "Next Chapter" tap required)
  - [x] Implement auto-direction detection (webtoon vertical vs paged horizontal 3D flip)
  - [x] Background prefetch of next 4 pages + pre-scrape of next chapter
  - [x] Quiet image loading & retry with exponential backoff
- [x] **M1.4: "All Caught Up" State Machine & Live Polling**
  - [x] Implement minimal "You're all caught up" end-of-stream card (text only)
  - [x] Implement auto-checking while sitting at end, on app resume, and on reopen
  - [x] Live append when next chapter is detected
  - [x] Implement shelf library periodic update checker for website series
- [x] **M1.5: Local & Cloud Progress Resumption**
  - [x] Implement instant local save on page turn (500ms debounce) & immediate on leave/pause/detach
  - [x] Implement exact restore via `pageKey` and `pageIndex` with zero flash
  - [x] Update shelf cards to show resume point ("Ch 124 · p. 7") and new-chapter badge
- [x] **M1.6: Phase 1 Verification & Acceptance Tests**
  - [x] Unit tests for progress save/restore and pageKey resilience
  - [x] Unit tests for "end reached -> auto check" state machine
  - [x] Verify `flutter analyze` (0 errors/warnings) and `flutter test` (all 6 tests passing)
  - [x] Manual test matrix check across static, lazy, JS, webtoon, hotlink, and MangaDex sites

### Phase 2: UI Overhaul (Apple Books / Netflix / Spotify Polish)
- [x] **M2.1: Design System & Tokens (`lib/theme/`)**
  - [x] Colors (deep dark palette, emerald accent, surface hierarchy, semantic `ThemeExtension` in `app_colors.dart`)
  - [x] Theme definitions (`AppTheme` dark & light modes with `CardThemeData`, `ColorScheme`)
  - [x] Reusable motion and loading components (`ShimmerBox`, `PressableScale` with haptics)
- [x] **M2.2: Screen Redesigns**
  - [x] Redesign Login Screen (ambient glow backdrop, emerald gradient brand icon, clean Google button)
  - [x] Redesign Library Shelf (skeleton grid loader, refresh indicator, pill filter chips, glowing FAB)
  - [x] Redesign Series Card & Form (cover shadow, resume pill, "NEW" badge, fluid inputs)
  - [x] Redesign Discover & MangaDex Detail Pages (shimmer skeletons, pressable cover tiles, clean typography)
  - [x] Redesign Reader chrome-less polish (ambient cover placeholder, 3D flip physics, discreet corner page pill, hidden long-press settings)
- [x] **M2.3: Polish, Verification & Final Deliverable**
  - [x] `flutter analyze` verified: 0 errors, 0 warnings
  - [x] `flutter test` verified: 100% pass rate across test suite
  - [x] Updated `README.md` with scraper architecture, site adapter guide, and privacy note

## Current status
- Phase 1 & Phase 2 COMPLETE.
- Brand Identity COMPLETE (Design C).
- Universal Scraper Engine UPGRADED: Full support for embedded JS/JSON (`ts_reader.run`, variable arrays), all lazy attributes, Android headless sizing (`1080x1920`), overview page auto-hop to Chapter 1, and chapter dropdown extraction.
- Natural Book Reader & 3D Physics UPGRADED:
  - Default reading direction flipped to Standard Book (swipe left to turn page).
  - Explicit gesture descriptions ("Standard Book - Swipe Left", "Japanese Manga - Swipe Right", "Vertical Reel - Scroll Down").
  - Physical 3D page curl animation with dynamic spine curve and fold shadow tracking finger movement.
  - Page turn paper flip sound effect (`ReaderAudio`) with haptics.
  - Switches to toggle 3D animation and sound effects.
  - In-reader press-and-hold menu with quick page jump slider and full chapter catalogue.
- Custom Categories & Smart Shelf Sorting:
  - User can create, rename, and delete custom categories on the homescreen.
  - Move books between categories by long-pressing on any book card.
  - Smart sorting puts recently read and frequently read manga at the top of the shelf.
- Clean analysis (`flutter analyze`: 0 issues), all unit tests passing (`7/7`).

## Files changed
- `pubspec.yaml`: Added `html`, `shared_preferences`, and `assets/logo/` bundle.
- `assets/logo/shelfmark_logo_c.svg` & `shelfmark_logo.png`: Master vector and 512x512 PNG assets for Design C.
- `android/app/src/main/res/mipmap-*/ic_launcher.png`: Native Android app launcher icons in mdpi, hdpi, xhdpi, xxhdpi, xxxhdpi.
- `android/app/src/main/res/drawable*/launch_background.xml`: Seamless dark Obsidian splash screen with centered launcher logo.
- `web/favicon.png` & `web/icons/`: Web launcher icons.
- `lib/ui/components/brand_logo.dart`: Reusable glowing brand logo component.
- `lib/ui/login_page.dart`: Centered 92px BrandLogo with glowing backdrop.
- `lib/ui/library_page.dart`: Branded AppBar with BrandLogo + shelf title, and prominent empty shelf icon.
- `lib/ui/unified_reader_page.dart`: Ambient cover loading screen with glowing BrandLogo and book opening indicator.
- `lib/models/series.dart`: Extended progress fields & resume labels.
- `lib/models/series.dart`: Extended progress fields & resume labels.
- `lib/services/local_progress_store.dart`: Instant offline local progress store.
- `lib/services/scrape/site_adapter.dart`: Adapter contract & scraped results.
- `lib/services/scrape/generic_site_adapter.dart`: Generic DOM image extractor & navigation link resolver.
- `lib/services/scrape/scrape_service.dart`: Multi-tier scraper (Fast Path + Headless fallback).
- `lib/services/scrape/example_site_adapter.dart`: Adapter example documentation.
- `lib/services/reader/chapter_source.dart`: Unified chapter source contracts.
- `lib/blocs/unified_reader_cubit.dart`: Continuous chapter streaming, background pre-scraping, live caught-up polling.
- `lib/ui/unified_reader_page.dart`: Full-bleed native book reader with 3D flip physics, ambient placeholder, and hidden settings.
- `lib/theme/app_colors.dart`: Design system color tokens & `AppThemeTokens` extension.
- `lib/theme/app_theme.dart`: Material 3 dark/light themes.
- `lib/theme/components/shimmer_box.dart`: Shimmer skeleton loader.
- `lib/theme/components/pressable_scale.dart`: Scale-on-press with haptics.
- `lib/ui/login_page.dart`: Redesigned ambient login screen.
- `lib/ui/library_page.dart`: Redesigned shelf with shimmer skeletons, refresh indicator, and pill chips.
- `lib/ui/series_card.dart`: Redesigned card with resume pill and glowing "NEW" badge.
- `lib/ui/series_form.dart`: Polished add/edit sheet.
- `lib/ui/discover_page.dart`: Polished discover view with shimmer loading.
- `lib/ui/md_detail_page.dart`: Unified reader integration.
- `test/scrape_service_test.dart`: Scraper test suite.
- `test/unified_reader_cubit_test.dart`: Unified reader cubit test suite.
- `README.md`: Complete documentation and privacy notes.

## How to test
- Run unit tests: `flutter test`
- Run static analysis: `flutter analyze`
- Run app on connected device: `flutter run`

## Log
- 2026-11-11 10:45 UTC: Created `PROGRESS.md` with complete Phase 1 and Phase 2 roadmap.
- 2026-11-11 10:48 UTC: Completed Phase 1 (M1.1 - M1.6), all tests passing, zero analyze issues.
- 2026-11-11 10:53 UTC: Completed Phase 2 (M2.1 - M2.3), design system and UI overhaul verified, zero analyze issues, test suite green.
