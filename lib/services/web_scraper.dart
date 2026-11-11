class WebScraper {
  WebScraper._();

  /// JavaScript that aggressively strips ads, popups, and intrusive overlays from the DOM.
  static const String stripAdsJs = '''
(function() {
  try {
    // 1. Prevent popups and unsolicited redirects
    window.open = function() { return null; };
    window.alert = function() { return true; };
    window.confirm = function() { return true; };
    window.prompt = function() { return null; };

    // 2. Remove common ad and popup selectors
    var selectors = [
      'iframe',
      'ins.adsbygoogle',
      '.adsbygoogle',
      '[id*="google_ads"]',
      '[id*="div-gpt-ad"]',
      '[class*="advertisement"]',
      '[id*="advertisement"]',
      '.ad-container',
      '.ads-wrapper',
      '.ad-box',
      '.banner-ad',
      '.banner-ads',
      '.floating-ad',
      '.popunder',
      '.popup',
      '#disqus_thread',
      '.disqus',
      '#comments',
      '.social-share',
      '.share-buttons',
      'div[style*="z-index: 999999"]',
      'div[style*="z-index: 2147483647"]',
      'div[style*="z-index: 100000"]'
    ];

    for (var i = 0; i < selectors.length; i++) {
      var elements = document.querySelectorAll(selectors[i]);
      for (var j = 0; j < elements.length; j++) {
        var el = elements[j];
        if (el && el.parentNode) {
          el.parentNode.removeChild(el);
        }
      }
    }
  } catch (e) {}
})();
''';

  /// JavaScript that detects and extracts high-resolution manga / comic page image URLs.
  static const String extractImagesJs = '''
(function() {
  try {
    // 0. Check window globals (ts_reader, pages, etc.)
    if (window.ts_reader && window.ts_reader.params && window.ts_reader.params.sources) {
      var s = window.ts_reader.params.sources;
      for (var si = 0; si < s.length; si++) {
        if (s[si].images && s[si].images.length >= 2) {
          return s[si].images;
        }
      }
    }
    if (window.pages && Array.isArray(window.pages) && window.pages.length >= 2) {
      return window.pages;
    }
    if (window.chapter_preloaded_images && Array.isArray(window.chapter_preloaded_images) && window.chapter_preloaded_images.length >= 2) {
      return window.chapter_preloaded_images;
    }
    if (window.cur_images && Array.isArray(window.cur_images) && window.cur_images.length >= 2) {
      return window.cur_images;
    }

    // Scroll slightly to trigger lazy-loaded reader images
    if (window.scrollY === 0 && document.body.scrollHeight > 1000) {
      window.scrollTo(0, 300);
      window.scrollTo(0, 0);
    }

    // Common manga / webtoon reader containers (ordered by popularity)
    var containerSelectors = [
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
      '.wp-manga-chapter-img'
    ];

    var imgs = [];
    for (var i = 0; i < containerSelectors.length; i++) {
      var container = document.querySelector(containerSelectors[i]);
      if (container) {
        var found = container.querySelectorAll('img');
        if (found && found.length >= 2) {
          for (var k = 0; k < found.length; k++) {
            imgs.push(found[k]);
          }
          break;
        }
      }
    }

    // Fallback: search all images in the document
    if (imgs.length < 2) {
      var allImgs = document.querySelectorAll('img');
      for (var k = 0; k < allImgs.length; k++) {
        imgs.push(allImgs[k]);
      }
    }

    var urls = [];
    var seen = {};
    var skipKeywords = [
      'avatar', 'logo', 'banner', 'icon', 'button', 'badge',
      'discord', 'telegram', 'facebook', 'twitter', 'patreon',
      'donate', 'loading', 'spinner', 'placeholder', 'ads',
      'advertisement', 'widget', 'thumb', 'cover', 'header', 'footer'
    ];

    for (var i = 0; i < imgs.length; i++) {
      var img = imgs[i];
      // Check lazy loading attributes in order of precedence
      var src = img.getAttribute('data-src') ||
                img.getAttribute('data-lazy-src') ||
                img.getAttribute('data-original') ||
                img.getAttribute('data-cfsrc') ||
                img.getAttribute('data-url') ||
                img.getAttribute('data-cdn') ||
                img.getAttribute('data-full-url') ||
                img.getAttribute('data-echo') ||
                img.getAttribute('data-actualsrc') ||
                img.getAttribute('data-page-url') ||
                img.getAttribute('data-image') ||
                img.getAttribute('data-img-src') ||
                img.currentSrc ||
                img.src;

      if (!src && img.getAttribute('srcset')) {
        var parts = img.getAttribute('srcset').split(',');
        if (parts.length > 0) {
          src = parts[parts.length - 1].trim().split(' ')[0];
        }
      }

      if (!src) continue;
      src = src.trim();

      if (src.indexOf('//') === 0) {
        src = window.location.protocol + src;
      }

      if (src.indexOf('http://') !== 0 && src.indexOf('https://') !== 0) {
        continue;
      }

      var lower = src.toLowerCase();

      // Check forbidden keywords
      var skip = false;
      for (var s = 0; s < skipKeywords.length; s++) {
        if (lower.indexOf(skipKeywords[s]) !== -1) {
          skip = true;
          break;
        }
      }
      if (skip) continue;

      // Filter tiny decorative/icon images
      var w = img.naturalWidth || img.width || parseInt(img.getAttribute('width')) || 0;
      var h = img.naturalHeight || img.height || parseInt(img.getAttribute('height')) || 0;
      if (w > 0 && w < 160 && h > 0 && h < 160) {
        continue;
      }

      if (!seen[src]) {
        seen[src] = true;
        urls.push(src);
      }
    }

    return urls;
  } catch (err) {
    return [];
  }
})();
''';

  /// JavaScript to find Next and Previous chapter links on the page.
  static const String extractNavigationJs = '''
(function() {
  try {
    var nextSelectors = [
      'a.next_page',
      'a.ch-next-btn',
      'a.btn-next',
      '.nav-next a',
      'a[rel="next"]',
      'a:has(.fa-arrow-right)',
      'a:has(.fa-angle-right)',
      'a[title*="Next"]'
    ];
    var prevSelectors = [
      'a.prev_page',
      'a.ch-prev-btn',
      'a.btn-prev',
      '.nav-previous a',
      'a[rel="prev"]',
      'a:has(.fa-arrow-left)',
      'a:has(.fa-angle-left)',
      'a[title*="Prev"]'
    ];

    var nextUrl = null;
    var prevUrl = null;

    for (var i = 0; i < nextSelectors.length; i++) {
      var el = document.querySelector(nextSelectors[i]);
      if (el && el.href && el.href.indexOf('http') === 0) {
        nextUrl = el.href;
        break;
      }
    }

    for (var i = 0; i < prevSelectors.length; i++) {
      var el = document.querySelector(prevSelectors[i]);
      if (el && el.href && el.href.indexOf('http') === 0) {
        prevUrl = el.href;
        break;
      }
    }

    var chapters = [];
    var selects = document.querySelectorAll('select#select-chapter option, select[name*="chapter"] option, select.chapter-select option, select.c-select option');
    for (var j = 0; j < selects.length; j++) {
      var opt = selects[j];
      var val = opt.value || opt.getAttribute('data-redirect') || '';
      var lbl = opt.text ? opt.text.trim() : '';
      if (val && lbl) {
        if (val.indexOf('/') === 0) val = window.location.origin + val;
        chapters.push({ url: val, label: lbl });
      }
    }

    return { next: nextUrl, prev: prevUrl, chapters: chapters };
  } catch (e) {
    return { next: null, prev: null, chapters: [] };
  }
})();
''';
}
