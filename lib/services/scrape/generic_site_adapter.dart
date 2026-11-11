import 'package:html/dom.dart' as dom;

import '../../core/url_tools.dart';
import '../../ui/ad_block.dart';
import 'cf_session.dart';
import 'site_adapter.dart';

class GenericSiteAdapter implements SiteAdapter {
  const GenericSiteAdapter();

  @override
  bool matches(String host) => true; // Fallback for all sites

  static const List<String> _readerSelectors = [
    '#readerarea',
    '.reading-content',
    '.entry-content',
    '.container-chapter-reader',
    '#chapter-content',
    '.chapter-content',
    '.chapter-images',
    '.viewer-cnt',
    '.vung-doc',
    '#vungdoc',
    '#images',
    '.page-break',
    '.comic-page',
    '.read-container',
    'div[class*="reading-content"]',
    'div[class*="chapter-content"]',
    'div[class*="read-container"]',
    '#divImage',
    '.wp-manga-chapter-img',
    '.scan-page',
  ];

  /// Whole-token matches only. Substring matching used to reject any URL that
  /// merely contained "ads" (every `/uploads/` path!), "star" (`/start/`),
  /// "icon", "cover" inside longer words, etc.
  static const Set<String> _junkTokens = {
    'avatar', 'avatars', 'logo', 'logos', 'banner', 'banners', 'icon', 'icons',
    'button', 'badge', 'badges', 'discord', 'telegram', 'facebook', 'twitter',
    'patreon', 'donate', 'loading', 'spinner', 'placeholder', 'ads', 'ad',
    'advert', 'advertisement', 'widget', 'header', 'footer', 'rating', 'emoji',
    'sprite', 'favicon', 'thumb', 'thumbs', 'thumbnail', 'thumbnails', 'cover',
  };

  static const Set<String> _junkCoverTokens = {
    'avatar', 'avatars', 'logo', 'logos', 'banner', 'banners', 'icon', 'icons',
    'button', 'spinner', 'placeholder', 'ads', 'ad', 'advert', 'advertisement',
    'rating', 'emoji', 'sprite', 'favicon',
  };

  static bool _hasJunkToken(String url, Set<String> tokens) {
    final uri = Uri.tryParse(url);
    if (uri == null) return true;
    final parts = ('${uri.host}${uri.path}')
        .toLowerCase()
        .split(RegExp(r'[^a-z0-9]+'));
    for (final t in parts) {
      if (tokens.contains(t)) return true;
    }
    return false;
  }

  @override
  Future<ScrapedChapterResult> extract(
    dom.Document document,
    Uri pageUri,
  ) async {
    // 0. Detect a real Cloudflare interstitial (NOT merely a site that uses
    //    Cloudflare / Turnstile somewhere on the page).
    if (CfSession.looksLikeChallengeHtml(document.outerHtml)) {
      return ScrapedChapterResult(
        chapterUrl: pageUri.toString(),
        pages: const [],
        needsVerification: true,
        verificationUrl: pageUri.toString(),
      );
    }

    // 1. Extract cover image from meta tags or poster
    final coverUrl = _extractCover(document, pageUri);

    // 2. Check for "Start Reading" button on overview pages
    final startReadingUrl = _findStartReadingLink(document, pageUri);

    final pages = <String>[];
    final seen = <String>{};

    void addPage(String url) {
      if (!seen.contains(url)) {
        seen.add(url);
        pages.add(url);
      }
    }

    // 3. Find reader container with at least 2 images
    dom.Element? readerContainer;
    for (final sel in _readerSelectors) {
      final el = document.querySelector(sel);
      if (el != null && el.querySelectorAll('img').length >= 2) {
        readerContainer = el;
        break;
      }
    }

    if (readerContainer != null) {
      final imgElements = <dom.Element>[...readerContainer.querySelectorAll('img')];
      // Also parse <noscript> tags inside reader container if images were hidden for noscript
      for (final noscript in readerContainer.querySelectorAll('noscript')) {
        final raw = noscript.text;
        if (raw.contains('<img')) {
          try {
            final temp = dom.Document.html(raw);
            imgElements.addAll(temp.querySelectorAll('img'));
          } catch (_) {}
        }
      }
      for (final img in imgElements) {
        final resolved = _extractImgSrc(img, pageUri);
        if (resolved != null && !_isJunk(resolved, img, insideReader: true)) {
          addPage(resolved);
        }
      }
    }

    // 3b. Direct reader page queries across known reader selectors
    if (pages.length < 2) {
      const directSelectors = [
        '.reading-content img',
        '.wp-manga-chapter-img',
        '.page-break img',
        '#readerarea img',
        '.container-chapter-reader img',
        '#chapter-content img',
        '#chapterimages img',
        '.chapter-images img',
        '.read-container img',
        '.viewer-cnt img',
        '#divImage img',
        '.comic-page img',
        '.entry-content img',
        '.scan-page img',
      ];
      for (final sel in directSelectors) {
        final found = document.querySelectorAll(sel);
        if (found.length >= 2) {
          for (final img in found) {
            final resolved = _extractImgSrc(img, pageUri);
            if (resolved != null && !_isJunk(resolved, img, insideReader: true)) {
              addPage(resolved);
            }
          }
          if (pages.length >= 2) break;
        }
      }
    }

    // 4. If reader container wasn't found or has < 2 images, check embedded scripts
    // (Crucial for WordPress TsManga themes like Thunderscans, dynamic JSON readers, etc.)
    if (pages.length < 2) {
      final scriptPages = _extractPagesFromScripts(document, pageUri);
      for (final sp in scriptPages) {
        addPage(sp);
      }
    }

    // 5. Fallback: If still < 2 pages, look for image cluster in main content containers,
    // explicitly excluding sidebars, widgets, recommendation sections, comments, etc.
    if (pages.length < 2) {
      final contentDivs =
          document.querySelectorAll('div, section, article, main');
      dom.Element? bestCluster;
      int maxCount = 0;
      for (final el in contentDivs) {
        final cls = (el.attributes['class'] ?? '').toLowerCase();
        final id = (el.attributes['id'] ?? '').toLowerCase();
        if (_isExcludedContainer(cls, id)) continue;

        final count = el.querySelectorAll('img').length;
        if (count >= 4 && count > maxCount) {
          maxCount = count;
          bestCluster = el;
        }
      }
      if (bestCluster != null) {
        for (final img in bestCluster.querySelectorAll('img')) {
          final resolved = _extractImgSrc(img, pageUri);
          if (resolved != null && !_isJunk(resolved, img)) {
            addPage(resolved);
          }
        }
      }
    }

    // 6. Extract full chapter catalogue
    final catalogue = _extractChapterCatalogue(document, pageUri);

    // 7. Discover Next & Prev Chapter URLs
    final isLatestInCatalogue =
        isCatalogueLatest(catalogue, pageUri.toString());
    final nextUrl = isLatestInCatalogue
        ? null
        : (_findNavigationLink(document, pageUri, isNext: true) ??
            _findCatalogueNeighbor(catalogue, pageUri.toString(),
                isNext: true));
    final prevUrl = _findNavigationLink(document, pageUri, isNext: false) ??
        _findCatalogueNeighbor(catalogue, pageUri.toString(), isNext: false);

    // 8. Extract title and chapter label
    final title = _extractTitle(document);
    final chapterLabel = UrlTools.chapterLabel(pageUri.toString()) ??
        _extractChapterHeading(document);

    return ScrapedChapterResult(
      chapterUrl: pageUri.toString(),
      pages: pages,
      title: title,
      chapterLabel: chapterLabel,
      nextChapterUrl: nextUrl,
      prevChapterUrl: prevUrl,
      isWebtoon: pages.length >= 2,
      availableChapters: catalogue,
      coverUrl: coverUrl ?? (pages.isNotEmpty ? pages.first : null),
      firstChapterUrl: startReadingUrl ??
          (catalogue.isNotEmpty ? catalogue.first.url : null),
    );
  }

  String? _extractImgSrc(dom.Element img, Uri pageUri) {
    String? rawSrc = img.attributes['data-src'] ??
        img.attributes['data-lazy-src'] ??
        img.attributes['data-original'] ??
        img.attributes['data-cfsrc'] ??
        img.attributes['data-wpfc-original-src'] ??
        img.attributes['data-url'] ??
        img.attributes['data-cdn'] ??
        img.attributes['data-full-url'] ??
        img.attributes['data-echo'] ??
        img.attributes['data-actualsrc'] ??
        img.attributes['data-page-url'] ??
        img.attributes['data-image'] ??
        img.attributes['data-img-src'] ??
        img.attributes['src'];

    if (rawSrc == null || rawSrc.trim().isEmpty) {
      final srcset = img.attributes['data-lazy-srcset'] ??
          img.attributes['data-srcset'] ??
          img.attributes['srcset'];
      if (srcset != null && srcset.isNotEmpty) {
        rawSrc = srcset.split(',').last.trim().split(' ').first;
      }
    }

    if (rawSrc == null || rawSrc.trim().isEmpty) return null;
    return _resolveUrl(rawSrc.trim(), pageUri);
  }

  static bool _isExcludedContainer(String cls, String id) {
    const excluded = [
      'sidebar',
      'widget',
      'related',
      'recommend',
      'comment',
      'footer',
      'header',
      'menu',
      'nav',
      'recent',
      'popular',
      'social',
      'disqus',
      'author',
    ];
    for (final ex in excluded) {
      if (cls.contains(ex) || id.contains(ex)) return true;
    }
    return false;
  }

  String? _extractCover(dom.Document doc, Uri baseUri) {
    // 1. og:image or twitter:image
    final og = doc
            .querySelector('meta[property="og:image"]')
            ?.attributes['content'] ??
        doc
            .querySelector('meta[name="twitter:image"]')
            ?.attributes['content'];
    if (og != null && og.trim().isNotEmpty) {
      final res = _resolveUrl(og.trim(), baseUri);
      if (res != null && !_isJunkCoverUrl(res)) return res;
    }

    // 2. Specific cover/poster elements
    final coverSelectors = [
      '.manga-poster img',
      '.summary_image img',
      '.thumb-manga img',
      '.series-thumb img',
      '.poster img',
      '.cover img',
      '.entry-thumb img',
      '.book-info img',
      '.thumb img',
      '.novel-cover img',
      '.manga-info-top img',
    ];
    for (final sel in coverSelectors) {
      final img = doc.querySelector(sel);
      if (img != null) {
        final src = img.attributes['data-src'] ??
            img.attributes['data-lazy-src'] ??
            img.attributes['src'];
        if (src != null && src.trim().isNotEmpty) {
          final res = _resolveUrl(src.trim(), baseUri);
          if (res != null && !_isJunkCoverUrl(res)) return res;
        }
      }
    }

    // 3. Fallback: inspect img tags for cover/poster in alt, class, or id
    for (final img in doc.querySelectorAll('img')) {
      final alt = (img.attributes['alt'] ?? '').toLowerCase();
      final cls = (img.attributes['class'] ?? '').toLowerCase();
      final id = (img.attributes['id'] ?? '').toLowerCase();
      if (alt.contains('cover') ||
          alt.contains('poster') ||
          cls.contains('cover') ||
          cls.contains('poster') ||
          id.contains('cover') ||
          id.contains('poster')) {
        final src = img.attributes['data-src'] ??
            img.attributes['data-lazy-src'] ??
            img.attributes['src'];
        if (src != null && src.trim().isNotEmpty) {
          final res = _resolveUrl(src.trim(), baseUri);
          if (res != null && !_isJunkCoverUrl(res)) return res;
        }
      }
    }

    return null;
  }

  bool _isJunkCoverUrl(String url) {
    final lower = url.toLowerCase();
    for (final ad in blockedDomains) {
      if (lower.contains(ad)) return true;
    }
    return _hasJunkToken(url, _junkCoverTokens);
  }

  String? _findStartReadingLink(dom.Document doc, Uri baseUri) {
    // 1. Dedicated button classes
    final buttonSelectors = [
      'a.read-now',
      'a.btn-read',
      'a.start-reading',
      'a.btn-start-reading',
      'a.first-chapter',
      'a.read-first',
      'a[href*="/chapter-1"]',
      'a[href*="/chapter/1"]',
      'a[href*="/chapter-01"]',
      'a[href*="/read/1"]',
    ];
    for (final sel in buttonSelectors) {
      final el = doc.querySelector(sel);
      if (el != null) {
        final href = el.attributes['href'];
        if (href != null && href.trim().isNotEmpty) {
          final res = _resolveUrl(href.trim(), baseUri);
          if (res != null && res != baseUri.toString()) return res;
        }
      }
    }

    // 2. Scan anchor text for "Start Reading", "Read Now", etc.
    for (final a in doc.querySelectorAll('a')) {
      final text = a.text.trim().toLowerCase();
      if (text.contains('start reading') ||
          text.contains('read first') ||
          text.contains('read now') ||
          text.contains('first chapter') ||
          text == 'read' ||
          text.contains('read chapter 1')) {
        final href = a.attributes['href'];
        if (href != null && href.trim().isNotEmpty) {
          final res = _resolveUrl(href.trim(), baseUri);
          if (res != null && res != baseUri.toString()) return res;
        }
      }
    }
    return null;
  }

  List<String> _extractPagesFromScripts(dom.Document document, Uri baseUri) {
    final results = <String>[];
    final seen = <String>{};

    for (final script in document.querySelectorAll('script')) {
      final text = script.text;
      if (text.isEmpty) continue;

      // Normalize escaped slashes often found in JSON / JS variables: "\/" -> "/"
      final unescapedText = text.replaceAll(r'\/', '/').replaceAll(r'\\/', '/');

      // A. TsManga pattern: ts_reader.run({ ... "images": ["https://...", ...] })
      if (unescapedText.contains('ts_reader') ||
          unescapedText.contains('"images":') ||
          unescapedText.contains("'images':")) {
        final imgArrayMatch = RegExp(
          r'''["']images["']\s*:\s*\[(.*?)\]''',
          dotAll: true,
        ).firstMatch(unescapedText);
        if (imgArrayMatch != null) {
          final rawArray = imgArrayMatch.group(1) ?? '';
          final urlMatches =
              RegExp(r'''["'](https?://[^"'\s]+)["']''').allMatches(rawArray);
          for (final m in urlMatches) {
            final u = m.group(1);
            if (u != null && !_isJunkUrl(u) && !seen.contains(u)) {
              seen.add(u);
              results.add(u);
            }
          }
          if (results.length >= 2) return results;
        }
      }

      // B. JavaScript variable assignment: var pages = [...] / var images = [...]
      final varMatch = RegExp(
        r'''(?:var|let|const)\s+(?:pages|images|chapter_preloaded_images|pData|imgList|imageList|cur_images)\s*=\s*\[(.*?)\]''',
        dotAll: true,
      ).firstMatch(unescapedText);
      if (varMatch != null) {
        final rawArray = varMatch.group(1) ?? '';
        final urlMatches =
            RegExp(r'''["'](https?://[^"'\s]+)["']''').allMatches(rawArray);
        for (final m in urlMatches) {
          final u = m.group(1);
          if (u != null && !_isJunkUrl(u) && !seen.contains(u)) {
            seen.add(u);
            results.add(u);
          }
        }
        if (results.length >= 2) return results;
      }

      // C. Fallback: scan for any cluster of image URLs inside a script
      if (unescapedText.contains('chapter') ||
          unescapedText.contains('manga') ||
          unescapedText.contains('reader')) {
        final anyImgMatches = RegExp(
          r'''https?://[^"'\s<>]+\.(?:jpg|jpeg|png|webp|avif)(?:\?[^"'\s<>]*)?''',
          caseSensitive: false,
        ).allMatches(unescapedText);
        for (final m in anyImgMatches) {
          final u = m.group(0);
          if (u != null && !_isJunkUrl(u) && !seen.contains(u)) {
            seen.add(u);
            results.add(u);
          }
        }
        if (results.length >= 3) return results;
      }
    }

    return results;
  }

  List<ChapterRef> _extractChapterCatalogue(dom.Document doc, Uri baseUri) {
    final list = <ChapterRef>[];
    final seenUrls = <String>{};

    // 1. Check <select> elements (standard in 90% of manga reader pages)
    final selects = doc.querySelectorAll(
      'select#select-chapter, select[name*="chapter"], select.chapter-select, select.c-select, select.single-chapter-select, .select-chapter select, .chapter-selection select',
    );
    for (final select in selects) {
      for (final opt in select.querySelectorAll('option')) {
        final val = opt.attributes['value'] ??
            opt.attributes['data-redirect'] ??
            opt.attributes['data-url'] ??
            '';
        final label = opt.text.trim();
        final resolved = _resolveUrl(val, baseUri);
        if (resolved != null &&
            label.isNotEmpty &&
            !seenUrls.contains(resolved)) {
          seenUrls.add(resolved);
          list.add(ChapterRef(url: resolved, label: label));
        }
      }
      if (list.length >= 2) return list;
    }

    // 2. Check chapter link lists
    final chapterLinks = doc.querySelectorAll(
      '.chapter-list a, .wp-manga-chapter a, ul.row-content-chapter a, div.eph-num a, .list-chapter a, .listing-chapters_wrap a, a[href*="/chapter/"], a[href*="/chapter-"], a.chapter-name',
    );
    for (final a in chapterLinks) {
      final href = a.attributes['href'];
      if (href == null || href.isEmpty) continue;
      final resolved = _resolveUrl(href, baseUri);
      if (resolved == null) continue;
      final text = a.text.trim();
      final label = text.isNotEmpty
          ? text
          : (UrlTools.chapterLabel(resolved) ?? 'Chapter');
      if (!seenUrls.contains(resolved)) {
        seenUrls.add(resolved);
        list.add(ChapterRef(url: resolved, label: label));
      }
    }

    return list;
  }

  static double? _parseChapterNum(String textOrUrl) {
    final uri = Uri.tryParse(textOrUrl);
    final target = (uri != null && uri.path.isNotEmpty) ? uri.path : textOrUrl;
    final m = RegExp(
      r'(?:chapter|chap|ch|episode|ep)[-_/.\s]?(\d+(?:[._-]\d+)?)',
      caseSensitive: false,
    ).allMatches(target);
    if (m.isNotEmpty) {
      final norm = m.last.group(1)!.replaceAll(RegExp(r'[_-]'), '.');
      final val = double.tryParse(norm);
      if (val != null) return val;
    }
    final m2 = RegExp(
      r'(?:chapter|chap|ch|episode|ep|#)?\s*(\d+(?:\.\d+)?)',
      caseSensitive: false,
    ).firstMatch(textOrUrl);
    if (m2 != null) {
      return double.tryParse(m2.group(1)!);
    }
    return null;
  }

  static bool _isCatalogueDescending(List<ChapterRef> catalogue) {
    if (catalogue.length < 2) return true;
    double? firstNum;
    double? lastNum;
    for (int i = 0; i < catalogue.length; i++) {
      firstNum = _parseChapterNum(catalogue[i].url) ??
          _parseChapterNum(catalogue[i].label);
      if (firstNum != null) break;
    }
    for (int i = catalogue.length - 1; i >= 0; i--) {
      lastNum = _parseChapterNum(catalogue[i].url) ??
          _parseChapterNum(catalogue[i].label);
      if (lastNum != null) break;
    }
    if (firstNum != null && lastNum != null && firstNum != lastNum) {
      return firstNum > lastNum;
    }
    return true; // Default to newest-first (industry standard)
  }

  static bool isCatalogueLatest(
      List<ChapterRef> catalogue, String currentUrl) {
    if (catalogue.isEmpty) return false;
    final normCurrent = UrlTools.normalize(currentUrl);
    final curUri = Uri.tryParse(currentUrl);

    int idx = catalogue.indexWhere(
      (c) => UrlTools.normalize(c.url) == normCurrent,
    );
    if (idx < 0 && curUri != null) {
      idx = catalogue.indexWhere((c) {
        final cUri = Uri.tryParse(c.url);
        return cUri != null && cUri.path == curUri.path;
      });
    }
    if (idx < 0) {
      final curNum = _parseChapterNum(currentUrl);
      if (curNum != null) {
        idx = catalogue.indexWhere((c) {
          final cNum =
              _parseChapterNum(c.url) ?? _parseChapterNum(c.label);
          return cNum == curNum;
        });
      }
    }

    final isDesc = _isCatalogueDescending(catalogue);
    if (idx >= 0) {
      return isDesc ? (idx == 0) : (idx == catalogue.length - 1);
    }

    // If current URL wasn't matched directly, check if chapter number is >= max in catalogue
    final curNum = _parseChapterNum(currentUrl);
    if (curNum != null) {
      double? maxNum;
      for (final c in catalogue) {
        final n = _parseChapterNum(c.url) ?? _parseChapterNum(c.label);
        if (n != null && (maxNum == null || n > maxNum)) {
          maxNum = n;
        }
      }
      if (maxNum != null && curNum >= maxNum) {
        return true;
      }
    }

    return false;
  }

  String? _findCatalogueNeighbor(
    List<ChapterRef> catalogue,
    String currentUrl, {
    required bool isNext,
  }) {
    if (catalogue.length < 2) return null;
    final normCurrent = UrlTools.normalize(currentUrl);
    int idx = catalogue.indexWhere(
      (c) => UrlTools.normalize(c.url) == normCurrent,
    );
    if (idx < 0) {
      final curUri = Uri.tryParse(currentUrl);
      if (curUri != null) {
        idx = catalogue.indexWhere((c) {
          final cUri = Uri.tryParse(c.url);
          return cUri != null && cUri.path == curUri.path;
        });
      }
    }
    if (idx < 0) {
      final curNum = _parseChapterNum(currentUrl);
      if (curNum != null) {
        idx = catalogue.indexWhere((c) {
          final cNum =
              _parseChapterNum(c.url) ?? _parseChapterNum(c.label);
          return cNum == curNum;
        });
      }
    }
    if (idx < 0) return null;

    final isDesc = _isCatalogueDescending(catalogue);
    final targetIdx = isDesc
        ? (isNext ? idx - 1 : idx + 1)
        : (isNext ? idx + 1 : idx - 1);

    if (targetIdx >= 0 && targetIdx < catalogue.length) {
      return catalogue[targetIdx].url;
    }
    return null;
  }

  bool _isJunkUrl(String url) {
    final lower = url.toLowerCase();
    for (final ad in blockedDomains) {
      if (lower.contains(ad)) return true;
    }
    return _hasJunkToken(url, _junkTokens);
  }

  String? _resolveUrl(String raw, Uri base) {
    if (raw.startsWith('data:image/')) {
      // Allow only substantial data URIs
      return raw.length > 500 ? raw : null;
    }
    if (raw.startsWith('//')) {
      return '${base.scheme}:$raw';
    }
    final parsed = Uri.tryParse(raw);
    if (parsed == null) return null;
    String? out;
    if (parsed.hasScheme) {
      if (parsed.scheme == 'http' || parsed.scheme == 'https') {
        out = parsed.toString();
      } else {
        return null;
      }
    } else {
      out = base.resolveUri(parsed).toString();
    }
    return _unwrapNextImage(out, base);
  }

  /// Next.js serves `/_next/image?url=%2Fuploads%2Fp.webp&w=640&q=75`; the
  /// encoded `url` is the original, full-resolution file.
  String _unwrapNextImage(String url, Uri base) {
    final u = Uri.tryParse(url);
    if (u == null) return url;
    if (u.path.endsWith('/_next/image') || u.path.endsWith('/_next/image/')) {
      final inner = u.queryParameters['url'];
      if (inner != null && inner.isNotEmpty) {
        final innerUri = Uri.tryParse(inner);
        if (innerUri != null) {
          final abs = innerUri.hasScheme ? innerUri : u.resolveUri(innerUri);
          if (abs.scheme == 'http' || abs.scheme == 'https') {
            return abs.toString();
          }
        }
      }
    }
    return url;
  }

  bool _isJunk(String url, dom.Element img, {bool insideReader = false}) {
    final lower = url.toLowerCase();

    // Check ad blockers domain list
    for (final ad in blockedDomains) {
      if (lower.contains(ad)) return true;
    }

    if (RegExp(
      r'(adsterra|exoclick|syndication|mobicow|popads|propeller|clickadu|hilltopads|highperformanceformat|profitablecpmrate|effectivegatecpm|tsyndicate|ad-maven|admaven|histats|mgid|taboola|outbrain|zergnet|disqus|monetag|yadro|dtscout|trafficjunky|trafficfactory|coinhive|crypto|casino|1xbet|melbet|bidgear|clksite|bonus|banner_ad|ad_banner)',
      caseSensitive: false,
    ).hasMatch(lower)) {
      return true;
    }

    if (_hasJunkToken(url, _junkTokens)) return true;

    // Filter out parent ad containers
    dom.Element? cur = img.parent;
    for (var i = 0; i < 4 && cur != null; i++) {
      final pCls = (cur.attributes['class'] ?? '').toLowerCase();
      final pId = (cur.attributes['id'] ?? '').toLowerCase();
      if (pCls.contains('adsbygoogle') ||
          pCls.contains('ad-box') ||
          pCls.contains('ad-slot') ||
          pCls.contains('ad-wrapper') ||
          pCls.contains('ad-container') ||
          pCls.contains('banner-ad') ||
          pCls.contains('advertisement') ||
          pCls.contains('code-block') ||
          pId.contains('adsbygoogle') ||
          pId.contains('banner-ad')) {
        return true;
      }
      cur = cur.parent;
    }

    // Filter out thumbnail/avatar/widget classes
    final cls = (img.attributes['class'] ?? '').toLowerCase();
    if (cls.contains('thumb') ||
        cls.contains('avatar') ||
        cls.contains('icon') ||
        cls.contains('badge') ||
        cls.contains('author') ||
        cls.contains('logo')) {
      return true;
    }

    // Inside reader container: pages and slices are valid content!
    if (insideReader) return false;

    // Check if inside a chapter link (e.g. <a href="/chapter-12"><img ...></a>) outside reader
    final parent = img.parent;
    if (parent != null && parent.localName == 'a') {
      final parentHref = (parent.attributes['href'] ?? '').toLowerCase();
      if (parentHref.contains('chapter') || parentHref.contains('/manga/')) {
        return true;
      }
    }

    final width = int.tryParse(img.attributes['width'] ?? '');
    final height = int.tryParse(img.attributes['height'] ?? '');
    if ((width != null && width > 0 && width < 180) &&
        (height != null && height > 0 && height < 180)) {
      return true;
    }

    // Skip horizontal banner ads (e.g. 728x90, 468x60, 320x50), but never wide webtoon strips
    if (width != null && height != null && width > 0 && height > 0) {
      if (width < 500 && (width / height > 3.2 || (height < 130 && width > 250))) return true;
      if ((width - 300).abs() < 40 && (height - 250).abs() < 40) return true;
    }

    return false;
  }

  String? _findNavigationLink(
    dom.Document doc,
    Uri baseUri, {
    required bool isNext,
  }) {
    bool isDisabled(dom.Element el) {
      final cls = (el.attributes['class'] ?? '').toLowerCase();
      final parentCls = (el.parent?.attributes['class'] ?? '').toLowerCase();
      if (cls.contains('disabled') || parentCls.contains('disabled')) return true;
      if (el.attributes['aria-disabled'] == 'true' ||
          el.attributes['disabled'] != null) {
        return true;
      }
      final href = (el.attributes['href'] ?? '').trim().toLowerCase();
      if (href == '#' || href.startsWith('javascript:')) return true;
      return false;
    }

    // 0. Check ts_reader or JSON navigation parameters: prevUrl / nextUrl
    final navKey = isNext ? 'nextUrl' : 'prevUrl';
    final rawHtml = doc.outerHtml;
    final navMatch = RegExp(
      '["\']$navKey["\']\\s*:\\s*["\']([^"\']+)["\']',
      caseSensitive: false,
    ).firstMatch(rawHtml);
    if (navMatch != null) {
      final raw =
          navMatch.group(1)?.replaceAll(r'\/', '/').replaceAll(r'\\/', '/');
      if (raw != null &&
          raw.isNotEmpty &&
          raw != 'false' &&
          raw != 'null' &&
          raw != '#') {
        final res = _resolveUrl(raw.trim(), baseUri);
        if (res != null && res != baseUri.toString()) return res;
      }
    }

    final rel = isNext ? 'next' : 'prev';
    // 1. Check <link rel="next|prev"> or <a rel="next|prev">
    final relEl = doc.querySelector('link[rel="$rel"]') ??
        doc.querySelector('a[rel="$rel"]');
    if (relEl != null && !isDisabled(relEl)) {
      final href = relEl.attributes['href'];
      if (href != null && href.isNotEmpty) {
        return _resolveUrl(href, baseUri);
      }
    }

    // 2. Check classes like .next_page, .nav-next, .btn-next
    final classSelectors = isNext
        ? [
            'a.next_page',
            'a.ch-next-btn',
            'a.btn-next',
            '.nav-next a',
            'a[title*="Next"]',
            'a[aria-label*="Next"]',
            'a[class*="next"]',
          ]
        : [
            'a.prev_page',
            'a.ch-prev-btn',
            'a.btn-prev',
            '.nav-previous a',
            'a[title*="Prev"]',
            'a[aria-label*="Prev"]',
            'a[class*="prev"]',
          ];

    for (final sel in classSelectors) {
      final el = doc.querySelector(sel);
      if (el != null && !isDisabled(el)) {
        final href = el.attributes['href'];
        if (href != null && href.isNotEmpty) {
          final res = _resolveUrl(href, baseUri);
          if (res != null && res != baseUri.toString()) return res;
        }
      }
    }

    // 3. Check anchor texts
    final anchors = doc.querySelectorAll('a');
    final matchWords = isNext
        ? ['next', 'newer', '>', '»', 'next chapter']
        : ['prev', 'previous', 'older', '<', '«', 'prev chapter'];

    for (final a in anchors) {
      if (isDisabled(a)) continue;
      final text = a.text.trim().toLowerCase();
      for (final w in matchWords) {
        if (text == w || text.contains(w)) {
          final href = a.attributes['href'];
          if (href != null && href.isNotEmpty) {
            final res = _resolveUrl(href, baseUri);
            if (res != null && res != baseUri.toString()) return res;
          }
        }
      }
    }

    return null;
  }

  String? _extractTitle(dom.Document doc) {
    final titleEl = doc.querySelector('title');
    if (titleEl != null && titleEl.text.isNotEmpty) {
      return UrlTools.cleanTitle(titleEl.text);
    }
    final h1 = doc.querySelector('h1');
    if (h1 != null && h1.text.isNotEmpty) {
      return UrlTools.cleanTitle(h1.text);
    }
    return null;
  }

  String? _extractChapterHeading(dom.Document doc) {
    for (final sel in ['h1', 'h2', '.chapter-title', '.current-chapter']) {
      final el = doc.querySelector(sel);
      if (el != null && el.text.isNotEmpty) {
        final label = UrlTools.chapterLabel(el.text);
        if (label != null) return label;
      }
    }
    return null;
  }
}
