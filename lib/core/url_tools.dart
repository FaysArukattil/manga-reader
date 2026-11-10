class SharedLink {
  const SharedLink(this.url, this.title);
  final String url;
  final String title;
}

/// Small helpers for URLs, chapter detection and title cleaning.
class UrlTools {
  UrlTools._();

  static final RegExp _chapterRe = RegExp(
    r'(?<![a-zA-Z])(chapter|chap|ch|episode|ep|c)[-_/.\s]?(\d+(?:[._-]\d+)?)(?!\d)',
    caseSensitive: false,
  );
  static final RegExp _urlRe = RegExp(r'https?://[^\s]+');
  static final RegExp _chapterOnly = RegExp(
    r'^(read\s+)?(chapter|chap|ch|episode|ep)[\s.#:-]*\d+(\.\d+)?$',
    caseSensitive: false,
  );
  static final RegExp _chapterAnywhere = RegExp(
    r'\b(chapter|chap|ch|episode|ep)[\s.#:-]*\d+(\.\d+)?\b',
    caseSensitive: false,
  );
  static final RegExp _titleSeparators = RegExp(
    r'\s[|\u2013\u2014\u2022]\s|\s-\s',
  );
  static final RegExp _trailingNoise = RegExp(
    r'(\s+(manga|manhwa|manhua|webtoon|online|free|raw|english|chapter))+$',
    caseSensitive: false,
  );

  static RegExpMatch? _lastChapterMatch(String path) {
    RegExpMatch? last;
    for (final m in _chapterRe.allMatches(path)) {
      last = m;
    }
    return last;
  }

  /// "Ch 12" style label detected from a URL path, or null.
  static String? chapterLabel(String url) {
    final uri = Uri.tryParse(url);
    if (uri == null) return null;
    final m = _lastChapterMatch(uri.path);
    if (m == null) return null;
    final norm = m.group(2)!.replaceAll(RegExp(r'[_-]'), '.');
    final n = num.tryParse(norm);
    return n == null ? 'Ch $norm' : 'Ch $n';
  }

  /// Returns the URL for chapter+[delta] when the URL has a plain integer
  /// chapter number, otherwise null.
  static String? stepChapter(String url, int delta) {
    final uri = Uri.tryParse(url);
    if (uri == null) return null;
    final m = _lastChapterMatch(uri.path);
    if (m == null) return null;
    final raw = m.group(2)!;
    if (!RegExp(r'^\d+$').hasMatch(raw)) return null;
    final next = int.parse(raw) + delta;
    if (next < 0) return null;
    final padded = next.toString().padLeft(raw.length, '0');
    final newPath = uri.path.replaceRange(m.end - raw.length, m.end, padded);
    return uri.replace(path: newPath).toString();
  }

  static String hostOf(String url) {
    final host = Uri.tryParse(url)?.host ?? '';
    return host.replaceFirst(RegExp(r'^www\.'), '');
  }

  static String registrableDomain(String host) {
    final h = host.toLowerCase().replaceFirst(RegExp(r'^www\.'), '');
    final parts = h.split('.');
    if (parts.length <= 2) return h;
    const secondLevel = {'co', 'com', 'org', 'net', 'gov', 'ac', 'edu'};
    final take =
        (parts.last.length == 2 &&
            secondLevel.contains(parts[parts.length - 2]))
        ? 3
        : 2;
    return parts.sublist(parts.length - take).join('.');
  }

  /// Strips fragment and trailing slash so two URLs can be compared.
  static String normalize(String url) {
    var u = url.trim();
    final hash = u.indexOf('#');
    if (hash >= 0) u = u.substring(0, hash);
    if (u.endsWith('/')) u = u.substring(0, u.length - 1);
    return u;
  }

  static SharedLink? parseShare(String raw) {
    final m = _urlRe.firstMatch(raw);
    if (m == null) return null;
    final url = m.group(0)!;
    final rest = raw
        .replaceFirst(url, '')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    return SharedLink(url, cleanTitle(rest));
  }

  /// Turns "Read One Piece Chapter 1100 | SiteName" into "One Piece".
  static String cleanTitle(String raw) {
    final t = raw.trim();
    if (t.isEmpty) return '';
    final parts = t
        .split(_titleSeparators)
        .map((s) => s.trim())
        .where((s) => s.isNotEmpty)
        .toList();
    if (parts.isEmpty) return '';
    final candidates = parts.where((p) => !_chapterOnly.hasMatch(p));
    var out = candidates.isEmpty ? parts.first : candidates.first;
    out = out.replaceAll(_chapterAnywhere, '');
    out = out.replaceFirst(RegExp(r'^read\s+', caseSensitive: false), '');
    out = out.replaceFirst(_trailingNoise, '');
    return out.replaceAll(RegExp(r'\s+'), ' ').trim();
  }
}
