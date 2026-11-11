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
  ///
  /// Junk filtering is TOKEN based (the URL is split on non-alphanumerics and
  /// whole tokens are compared). The old substring match rejected every URL
  /// containing "ads", which includes any `/uploads/` path, so whole sites
  /// (e.g. kaynscans.com) lost all of their pages and their cover.
  static const String extractImagesJs = r'''
(function() {
  try {
    function unwrap(src) {
      try {
        var u = new URL(src, location.href);
        if (/\/_next\/image\/?$/.test(u.pathname) && u.searchParams.get('url')) {
          return new URL(u.searchParams.get('url'), location.href).href;
        }
      } catch (e) {}
      return src;
    }
    var JUNK = {avatar:1, avatars:1, logo:1, logos:1, banner:1, banners:1, icon:1, icons:1,
      button:1, badge:1, badges:1, discord:1, telegram:1, facebook:1, twitter:1, patreon:1,
      donate:1, loading:1, spinner:1, placeholder:1, ads:1, ad:1, advert:1, advertisement:1,
      widget:1, header:1, footer:1, rating:1, emoji:1, sprite:1, favicon:1, thumb:1,
      thumbs:1, thumbnail:1, thumbnails:1, cover:1};
    function isJunkUrl(u) {
      try {
        var p = new URL(u);
        var toks = (p.hostname + p.pathname).toLowerCase().split(/[^a-z0-9]+/);
        for (var i = 0; i < toks.length; i++) { if (JUNK[toks[i]]) return true; }
      } catch (e) { return true; }
      return false;
    }
    function fromSrcset(ss) {
      var best = null, bestW = -1;
      var parts = ss.split(',');
      for (var i = 0; i < parts.length; i++) {
        var bits = parts[i].trim().split(/\s+/);
        if (!bits[0]) continue;
        var w = bits[1] ? parseFloat(bits[1]) : 0;
        if (w >= bestW) { bestW = w; best = bits[0]; }
      }
      return best;
    }
    function srcOf(img) {
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
                img.getAttribute('src') ||
                img.currentSrc;
      if (!src || src.indexOf('data:') === 0) {
        var ss = img.getAttribute('data-srcset') || img.getAttribute('srcset');
        var pic = img.parentElement && img.parentElement.tagName === 'PICTURE' ? img.parentElement : null;
        if (!ss && pic) {
          var so = pic.querySelector('source[srcset]');
          if (so) ss = so.getAttribute('srcset');
        }
        if (ss) src = fromSrcset(ss) || src;
      }
      if (!src) return null;
      src = src.trim();
      if (src.indexOf('//') === 0) src = location.protocol + src;
      try { src = new URL(src, location.href).href; } catch (e) { return null; }
      if (src.indexOf('http://') !== 0 && src.indexOf('https://') !== 0) return null;
      return unwrap(src);
    }

    // 0. Window globals
    if (window.ts_reader && window.ts_reader.params && window.ts_reader.params.sources) {
      var s = window.ts_reader.params.sources;
      for (var si = 0; si < s.length; si++) {
        if (s[si].images && s[si].images.length >= 2) return s[si].images;
      }
    }
    var gl = ['pages', 'chapter_preloaded_images', 'cur_images'];
    for (var gi = 0; gi < gl.length; gi++) {
      var g = window[gl[gi]];
      if (g && Array.isArray(g) && g.length >= 2 && typeof g[0] === 'string') return g;
    }

    // 1. Known reader containers
    var containerSelectors = [
      '#readerarea', '.reading-content', '.container-chapter-reader', '#chapter-content',
      '.chapter-content', '.chapter-images', '.viewer-cnt', '.vung-doc', '#vungdoc',
      '#images', '.comic-page', '.read-container', 'div[class*="reading-content"]',
      'div[class*="chapter-content"]', 'div[class*="read-container"]', '#divImage',
      '.wp-manga-chapter-img', '.entry-content', '.page-break'
    ];
    var items = [];
    function collect(list) {
      var out = [];
      var seen = {};
      for (var i = 0; i < list.length; i++) {
        var img = list[i];
        var u = srcOf(img);
        if (!u || seen[u] || isJunkUrl(u)) continue;
        var w = img.naturalWidth || parseInt(img.getAttribute('width')) || 0;
        var h = img.naturalHeight || parseInt(img.getAttribute('height')) || 0;
        if ((w > 0 && w < 160) && (h > 0 && h < 160)) continue;
        seen[u] = true;
        out.push({el: img, url: u, w: w, h: h});
      }
      return out;
    }
    for (var i = 0; i < containerSelectors.length; i++) {
      var c = document.querySelector(containerSelectors[i]);
      if (c) {
        var got = collect(c.querySelectorAll('img'));
        if (got.length >= 2) { items = got; break; }
      }
    }

    // 2. Fallback for SPA readers with unknown markup: pick the group of
    //    sibling images that looks most like a run of pages.
    if (items.length < 2) {
      var all = collect(document.querySelectorAll('img'));
      var groups = [];
      for (var d = 1; d <= 3; d++) {
        var map = new Map();
        for (var k = 0; k < all.length; k++) {
          var anc = all[k].el;
          for (var dd = 0; dd < d && anc; dd++) anc = anc.parentElement;
          if (!anc) continue;
          if (!map.has(anc)) map.set(anc, []);
          map.get(anc).push(all[k]);
        }
        map.forEach(function(v) { groups.push({depth: d, items: v}); });
      }
      var best = null, bestScore = 0;
      for (var gi2 = 0; gi2 < groups.length; gi2++) {
        var gr = groups[gi2];
        if (gr.items.length < 2) continue;
        var score = 0;
        for (var m = 0; m < gr.items.length; m++) {
          var it = gr.items[m];
          var alt = (it.el.getAttribute('alt') || '');
          score += /page\s*\d+|^\d+$/i.test(alt) ? 3 : 1;
          if (it.w >= 400 || it.h >= 600) score += 1;
        }
        score -= gr.depth * 0.1;
        if (score > bestScore) { bestScore = score; best = gr; }
      }
      items = best ? best.items : all;
    }

    var urls = [];
    for (var n = 0; n < items.length; n++) urls.push(items[n].url);
    return urls;
  } catch (err) {
    return [];
  }
})();
''';

  /// Scrolls the document and any inner scroll containers one step down so
  /// lazy / virtualised readers render the next pages. Returns true once
  /// everything is scrolled to the bottom.
  static const String scrollStepJs = r'''
(function() {
  try {
    var done = true;
    var root = document.scrollingElement || document.documentElement;
    var vh = window.innerHeight || 800;
    var maxRoot = root.scrollHeight - vh;
    if (root.scrollTop < maxRoot - 4) {
      root.scrollTop = Math.min(maxRoot, root.scrollTop + Math.max(400, vh * 0.9));
      done = false;
    }
    var all = document.querySelectorAll('div, main, section');
    for (var i = 0; i < all.length && i < 2500; i++) {
      var e = all[i];
      if (e.clientHeight > 200 && e.scrollHeight > e.clientHeight + 400) {
        var oy = getComputedStyle(e).overflowY;
        if (oy === 'auto' || oy === 'scroll') {
          var mx = e.scrollHeight - e.clientHeight;
          if (e.scrollTop < mx - 4) {
            e.scrollTop = Math.min(mx, e.scrollTop + Math.max(400, e.clientHeight * 0.9));
            done = false;
          }
        }
      }
    }
    return done;
  } catch (e) { return true; }
})();
''';

  /// "13 pages" style hint, so the scraper knows when a lazy reader has
  /// rendered everything. 0 when the page doesn't say.
  static const String expectedPagesJs = r'''
(function() {
  try {
    var t = (document.body && document.body.innerText) || '';
    var m = t.match(/(\d{1,4})\s*pages\b/i);
    return m ? parseInt(m[1]) : 0;
  } catch (e) { return 0; }
})();
''';

  /// Cover / poster image from meta tags (resolved to an absolute http URL).
  static const String extractCoverJs = r'''
(function() {
  try {
    var sels = ['meta[property="og:image"]', 'meta[name="twitter:image"]', 'link[rel="image_src"]'];
    for (var i = 0; i < sels.length; i++) {
      var el = document.querySelector(sels[i]);
      var v = el && (el.getAttribute('content') || el.getAttribute('href'));
      if (v) {
        var u = new URL(v, location.href).href;
        if (u.indexOf('http') === 0) return u;
      }
    }
  } catch (e) {}
  return null;
})();
''';

  /// For readers that draw pages onto <canvas> (or blob: images) so no real
  /// image URL exists: snapshot each one as a JPEG data URL into
  /// `window.__smPages` and return how many were captured. The data is then
  /// pulled one page at a time (a single huge bridge message would fail).
  static const String collectRenderedJs = r'''
(function() {
  try {
    window.__smPages = [];
    var els = document.querySelectorAll('canvas, img[src^="blob:"]');
    for (var i = 0; i < els.length; i++) {
      var el = els[i];
      var isCanvas = el.tagName === 'CANVAS';
      var w = isCanvas ? el.width : el.naturalWidth;
      var h = isCanvas ? el.height : el.naturalHeight;
      if (!w || !h || w < 300 || h < 300) continue;
      try {
        var c = el;
        if (!isCanvas) {
          c = document.createElement('canvas');
          c.width = w; c.height = h;
          c.getContext('2d').drawImage(el, 0, 0);
        }
        window.__smPages.push(c.toDataURL('image/jpeg', 0.92));
      } catch (e) {}
    }
    return window.__smPages.length;
  } catch (e) { return 0; }
})();
''';

  /// JavaScript to find Next and Previous chapter links on the page.
  static const String extractNavigationJs = r'''
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

    // Fallback for SPA readers whose chapter URLs carry a unique id
    // (e.g. /title/slug/7301644-chapter-60 -> .../7301701-chapter-61): the
    // next URL can't be guessed, so find the real link by chapter number.
    function chNum(path) {
      var m = path.match(/chapter[-_\/]?(\d+(?:[._-]\d+)?)/i);
      return m ? parseFloat(m[1].replace(/[_-]/, '.')) : null;
    }
    function dirOf(path) { return path.replace(/\/[^\/]*\/?$/, ''); }
    try {
      var curPath = location.pathname;
      var curNum = chNum(curPath);
      if (curNum !== null && (!nextUrl || !prevUrl)) {
        var curDir = dirOf(curPath);
        var bestNext = null, bestNextN = Infinity, bestPrev = null, bestPrevN = -Infinity;
        var anchors = document.querySelectorAll('a[href]');
        for (var ai = 0; ai < anchors.length; ai++) {
          var u;
          try { u = new URL(anchors[ai].href, location.href); } catch (e) { continue; }
          if (u.origin !== location.origin || u.pathname === curPath) continue;
          var n = chNum(u.pathname);
          if (n === null || dirOf(u.pathname) !== curDir) continue;
          if (n > curNum && n < bestNextN) { bestNextN = n; bestNext = u.href; }
          if (n < curNum && n > bestPrevN) { bestPrevN = n; bestPrev = u.href; }
        }
        if (!nextUrl && bestNext) nextUrl = bestNext;
        if (!prevUrl && bestPrev) prevUrl = bestPrev;
      }
    } catch (e) {}

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
