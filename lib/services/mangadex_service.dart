import 'dart:convert';

import 'package:http/http.dart' as http;

class MdException implements Exception {
  const MdException(this.message);
  final String message;
  @override
  String toString() => message;
}

class MdManga {
  const MdManga({
    required this.id,
    required this.title,
    required this.description,
    this.coverUrl,
    this.status = '',
    this.latestChapterId,
  });

  final String id;
  final String title;
  final String description;
  final String? coverUrl;
  final String status;
  final String? latestChapterId;
}

class MdChapter {
  const MdChapter({
    required this.id,
    required this.number,
    required this.title,
    required this.pages,
    required this.group,
    this.volume = '',
  });

  factory MdChapter.fromJson(Map<String, dynamic> j) => MdChapter(
        id: j['id'] as String,
        number: (j['number'] as String?) ?? '',
        title: (j['title'] as String?) ?? '',
        pages: ((j['pages'] as num?) ?? 0).toInt(),
        group: (j['group'] as String?) ?? '',
        volume: (j['volume'] as String?) ?? '',
      );

  final String id;
  final String number;
  final String title;
  final int pages;
  final String group;
  final String volume;

  String get label =>
      number.isEmpty ? (title.isEmpty ? 'Oneshot' : title) : 'Ch $number';

  Map<String, dynamic> toJson() => {
        'id': id,
        'number': number,
        'title': title,
        'pages': pages,
        'group': group,
        'volume': volume,
      };
}

/// Client for the official MangaDex API (https://api.mangadex.org/docs/).
///
/// Follows MangaDex's rules for third-party apps: a descriptive User-Agent,
/// request spacing to stay inside rate limits, only chapters hosted by
/// MangaDex itself (external-publisher chapters are skipped), no ads, and
/// scanlation groups are shown as credit in the reader.
class MangaDexService {
  MangaDexService({http.Client? client}) : _client = client ?? http.Client();

  final http.Client _client;

  static const _host = 'api.mangadex.org';
  static const _headers = {
    'User-Agent': 'MangaReader/1.0 (personal non-commercial reader)',
    'Accept': 'application/json',
  };
  static const _ratings = ['safe', 'suggestive'];

  DateTime _last = DateTime.fromMillisecondsSinceEpoch(0);

  Future<void> _gap() async {
    final wait = 250 - DateTime.now().difference(_last).inMilliseconds;
    _last = DateTime.now().add(Duration(milliseconds: wait > 0 ? wait : 0));
    if (wait > 0) await Future<void>.delayed(Duration(milliseconds: wait));
  }

  Future<Map<String, dynamic>> _get(Uri uri) async {
    await _gap();
    final http.Response res;
    try {
      res = await _client
          .get(uri, headers: _headers)
          .timeout(const Duration(seconds: 15));
    } catch (_) {
      throw const MdException(
        'Could not reach MangaDex. Check your connection.',
      );
    }
    if (res.statusCode == 429) {
      throw const MdException('Too many requests. Wait a moment and retry.');
    }
    if (res.statusCode != 200) {
      throw MdException('MangaDex error (${res.statusCode}).');
    }
    return jsonDecode(res.body) as Map<String, dynamic>;
  }

  static String _pick(Object? v) {
    if (v is Map && v.isNotEmpty) {
      final en = v['en'];
      if (en is String) return en;
      final first = v.values.first;
      if (first is String) return first;
    }
    return '';
  }

  MdManga _manga(Map<String, dynamic> m) {
    final attrs = (m['attributes'] as Map<String, dynamic>?) ?? const {};
    final id = m['id'] as String;
    String? cover;
    for (final r in (m['relationships'] as List? ?? const [])) {
      if (r is Map && r['type'] == 'cover_art') {
        final file = (r['attributes'] as Map?)?['fileName'];
        if (file is String) {
          cover = 'https://uploads.mangadex.org/covers/$id/$file.256.jpg';
        }
      }
    }
    return MdManga(
      id: id,
      title: _pick(attrs['title']),
      description: _pick(attrs['description']),
      coverUrl: cover,
      status: (attrs['status'] as String?) ?? '',
      latestChapterId: attrs['latestUploadedChapter'] as String?,
    );
  }

  /// Empty [query] returns the most-followed series.
  Future<List<MdManga>> search(String query, {int offset = 0}) async {
    final q = query.trim();
    final json = await _get(
      Uri.https(_host, '/manga', {
        if (q.isNotEmpty) 'title': q,
        'limit': '24',
        'offset': '$offset',
        'includes[]': ['cover_art'],
        'contentRating[]': _ratings,
        'availableTranslatedLanguage[]': ['en'],
        'hasAvailableChapters': 'true',
        'order[${q.isEmpty ? 'followedCount' : 'relevance'}]': 'desc',
      }),
    );
    return (json['data'] as List)
        .whereType<Map<String, dynamic>>()
        .map(_manga)
        .toList();
  }

  /// Latest chapter id per manga id (used for the "NEW" badge).
  Future<Map<String, String?>> latestChapterIds(List<String> ids) async {
    final out = <String, String?>{};
    for (var i = 0; i < ids.length; i += 100) {
      final chunk = ids.sublist(i, i + 100 > ids.length ? ids.length : i + 100);
      final json = await _get(
        Uri.https(_host, '/manga', {
          'ids[]': chunk,
          'limit': '100',
          'contentRating[]': ['safe', 'suggestive', 'erotica'],
        }),
      );
      for (final m
          in (json['data'] as List).whereType<Map<String, dynamic>>()) {
        out[m['id'] as String] =
            (m['attributes'] as Map?)?['latestUploadedChapter'] as String?;
      }
    }
    return out;
  }

  /// All readable English chapters, oldest first, one per chapter number.
  Future<List<MdChapter>> chapters(String mangaId) async {
    final raw = <MdChapter>[];
    var offset = 0;
    var total = 1;
    while (offset < total && offset < 3000) {
      final json = await _get(
        Uri.https(_host, '/manga/$mangaId/feed', {
          'translatedLanguage[]': ['en'],
          'order[chapter]': 'desc',
          'limit': '500',
          'offset': '$offset',
          'includes[]': ['scanlation_group'],
          'contentRating[]': ['safe', 'suggestive'],
          'includeExternalUrl': '0',
        }),
      );
      total = ((json['total'] as num?) ?? 0).toInt();
      for (final c
          in (json['data'] as List).whereType<Map<String, dynamic>>()) {
        final a = (c['attributes'] as Map<String, dynamic>?) ?? const {};
        if (a['externalUrl'] != null) continue; // hosted elsewhere
        final pages = ((a['pages'] as num?) ?? 0).toInt();
        if (pages == 0) continue;
        var group = '';
        for (final r in (c['relationships'] as List? ?? const [])) {
          if (r is Map && r['type'] == 'scanlation_group') {
            group = ((r['attributes'] as Map?)?['name'] as String?) ?? group;
          }
        }
        raw.add(
          MdChapter(
            id: c['id'] as String,
            number: (a['chapter'] as String?) ?? '',
            title: (a['title'] as String?) ?? '',
            pages: pages,
            group: group,
            volume: (a['volume'] as String?) ?? '',
          ),
        );
      }
      offset += 500;
    }
    final seen = <String>{};
    final unique = <MdChapter>[];
    for (final c in raw) {
      final key = c.number.isEmpty ? c.id : c.number;
      if (seen.add(key)) unique.add(c);
    }
    return unique.reversed.toList();
  }

  /// Image URLs for one chapter (MangaDex@Home). Data-saver is lighter/faster.
  Future<List<String>> pageUrls(
    String chapterId, {
    bool dataSaver = false,
  }) async {
    final json = await _get(Uri.https(_host, '/at-home/server/$chapterId'));
    final base = json['baseUrl'] as String;
    final ch = json['chapter'] as Map<String, dynamic>;
    final hash = ch['hash'] as String;
    final files = (ch[dataSaver ? 'dataSaver' : 'data'] as List).cast<String>();
    final dir = dataSaver ? 'data-saver' : 'data';
    return [for (final f in files) '$base/$dir/$hash/$f'];
  }
}
