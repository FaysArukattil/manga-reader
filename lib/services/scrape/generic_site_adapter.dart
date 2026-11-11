import 'package:html/dom.dart' as dom;

import '../../core/url_tools.dart';
import '../../ui/ad_block.dart';
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

  static const List<String> _junkKeywords = [
    'avatar',
    'logo',
    'banner',
    'icon',
    'button',
    'badge',
    'discord',
    'telegram',
    'facebook',
    'twitter',
    'patreon',
    'donate',
    'loading',
    'spinner',
    'placeholder',
    'ads',
    'advertisement',
    'widget',
    'thumb',
    'cover',
    'header',
    'footer',
    'rating',
    'star',
    'comment',
  ];

  @override
  Future<ScrapedChapterResult> extract(
    dom.Document document,
    Uri pageUri,
  ) async {
    // 1. Find reader container or largest image cluster
    dom.Element? readerContainer;
    for (final sel in _readerSelectors) {
      final el = document.querySelector(sel);
      if (el != null && el.querySelectorAll('img').length >= 2) {
        readerContainer = el;
        break;
      }
    }

    final List<dom.Element> imgElements = [];
    if (readerContainer != null) {
      imgElements.addAll(readerContainer.querySelectorAll('img'));
    } else {
      // Find the element with the highest count of content images
      final allImgs = document.querySelectorAll('img');
      imgElements.addAll(allImgs);
    }

    // Also parse <noscript> tags inside reader container if images were hidden for noscript
    for (final noscript in document.querySelectorAll('noscript')) {
      final raw = noscript.text;
      if (raw.contains('<img')) {
        try {
          final temp = dom.Document.html(raw);
          imgElements.addAll(temp.querySelectorAll('img'));
        } catch (_) {}
      }
    }

    final pages = <String>[];
    final seen = <String>{};

    for (final img in imgElements) {
      String? rawSrc = img.attributes['data-src'] ??
          img.attributes['data-lazy-src'] ??
          img.attributes['data-original'] ??
          img.attributes['data-cfsrc'] ??
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
        // Try srcset
        final srcset = img.attributes['srcset'];
        if (srcset != null && srcset.isNotEmpty) {
          rawSrc = srcset.split(',').last.trim().split(' ').first;
        }
      }

      if (rawSrc == null || rawSrc.trim().isEmpty) continue;
      rawSrc = rawSrc.trim();

      // Resolve relative and protocol-relative URLs
      final resolved = _resolveUrl(rawSrc, pageUri);
      if (resolved == null) continue;

      if (_isJunk(resolved, img)) continue;

      if (!seen.contains(resolved)) {
        seen.add(resolved);
        pages.add(resolved);
      }
    }

    // 2. If < 2 pages found in DOM, extract from embedded JavaScript/JSON
    if (pages.length < 2) {
      final scriptPages = _extractPagesFromScripts(document, pageUri);
      for (final sp in scriptPages) {
        if (!seen.contains(sp)) {
          seen.add(sp);
          pages.add(sp);
        }
      }
    }

    // 3. Extract full chapter catalogue
    final catalogue = _extractChapterCatalogue(document, pageUri);

    // 4. Discover Next & Prev Chapter URLs
    final nextUrl = _findNavigationLink(document, pageUri, isNext: true) ??
        _findCatalogueNeighbor(catalogue, pageUri.toString(), isNext: true);
    final prevUrl = _findNavigationLink(document, pageUri, isNext: false) ??
        _findCatalogueNeighbor(catalogue, pageUri.toString(), isNext: false);

    // 5. Extract title and chapter label
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
    );
  }

  List<String> _extractPagesFromScripts(dom.Document document, Uri baseUri) {
    final results = <String>[];
    final seen = <String>{};

    for (final script in document.querySelectorAll('script')) {
      final text = script.text;
      if (text.isEmpty) continue;

      // A. TsManga pattern: ts_reader.run({ ... "images": ["https://...", ...] })
      if (text.contains('ts_reader') ||
          text.contains('"images":') ||
          text.contains("'images':")) {
        final imgArrayMatch = RegExp(
          r'''["']images["']\s*:\s*\[(.*?)\]''',
          dotAll: true,
        ).firstMatch(text);
        if (imgArrayMatch != null) {
          final rawArray = imgArrayMatch.group(1) ?? '';
          final urlMatches =
              RegExp(r'''["'](https?:\/\/[^"'\s]+)["']''').allMatches(rawArray);
          for (final m in urlMatches) {
            final u = m.group(1)?.replaceAll(r'\/', '/');
            if (u != null && !seen.contains(u)) {
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
      ).firstMatch(text);
      if (varMatch != null) {
        final rawArray = varMatch.group(1) ?? '';
        final urlMatches =
            RegExp(r'''["'](https?:\/\/[^"'\s]+)["']''').allMatches(rawArray);
        for (final m in urlMatches) {
          final u = m.group(1)?.replaceAll(r'\/', '/');
          if (u != null && !seen.contains(u)) {
            seen.add(u);
            results.add(u);
          }
        }
        if (results.length >= 2) return results;
      }

      // C. Fallback: scan for any cluster of image URLs inside a script
      if (text.contains('chapter') ||
          text.contains('manga') ||
          text.contains('reader')) {
        final anyImgMatches = RegExp(
          r'''https?:\/\/[^"'\s<>]+\.(?:jpg|jpeg|png|webp|avif)(?:\?[^"'\s<>]*)?''',
          caseSensitive: false,
        ).allMatches(text);
        for (final m in anyImgMatches) {
          final u = m.group(0)?.replaceAll(r'\/', '/');
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
      'select#select-chapter, select[name*="chapter"], select.chapter-select, select.c-select, select.single-chapter-select',
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

  String? _findCatalogueNeighbor(
    List<ChapterRef> catalogue,
    String currentUrl, {
    required bool isNext,
  }) {
    if (catalogue.length < 2) return null;
    final normCurrent = UrlTools.normalize(currentUrl);
    final idx = catalogue.indexWhere(
      (c) => UrlTools.normalize(c.url) == normCurrent,
    );
    if (idx < 0) return null;

    // Check if catalogue is ordered newest-first or oldest-first
    final targetIdx = isNext ? idx + 1 : idx - 1;
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
    for (final k in _junkKeywords) {
      if (lower.contains(k)) return true;
    }
    return false;
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
    if (parsed.hasScheme) {
      if (parsed.scheme == 'http' || parsed.scheme == 'https') {
        return parsed.toString();
      }
      return null;
    }
    return base.resolveUri(parsed).toString();
  }

  bool _isJunk(String url, dom.Element img) {
    final lower = url.toLowerCase();

    // Check ad blockers domain list
    for (final ad in blockedDomains) {
      if (lower.contains(ad)) return true;
    }

    for (final k in _junkKeywords) {
      if (lower.contains(k)) return true;
    }

    final width = int.tryParse(img.attributes['width'] ?? '');
    final height = int.tryParse(img.attributes['height'] ?? '');
    if (width != null && height != null && width > 0 && height > 0) {
      if (width < 140 && height < 140) return true;
    }

    return false;
  }

  String? _findNavigationLink(
    dom.Document doc,
    Uri baseUri, {
    required bool isNext,
  }) {
    final rel = isNext ? 'next' : 'prev';
    // 1. Check <link rel="next|prev"> or <a rel="next|prev">
    final relEl = doc.querySelector('link[rel="$rel"]') ??
        doc.querySelector('a[rel="$rel"]');
    if (relEl != null) {
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
      if (el != null) {
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
