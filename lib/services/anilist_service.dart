import 'dart:convert';

import 'package:http/http.dart' as http;

/// Looks up a cover image on AniList (metadata only, no chapter content).
class AniListService {
  AniListService({http.Client? client}) : _client = client ?? http.Client();

  final http.Client _client;

  static const _query =
      r'query($s:String){Media(search:$s,type:MANGA){coverImage{large}}}';

  Future<String?> findCover(String title) async {
    final q = title.trim();
    if (q.length < 2) return null;
    try {
      final res = await _client
          .post(
            Uri.parse('https://graphql.anilist.co'),
            headers: const {
              'Content-Type': 'application/json',
              'Accept': 'application/json',
            },
            body: jsonEncode({
              'query': _query,
              'variables': {'s': q},
            }),
          )
          .timeout(const Duration(seconds: 8));
      if (res.statusCode != 200) return null;
      final data = jsonDecode(res.body) as Map<String, dynamic>;
      final media = (data['data'] as Map<String, dynamic>?)?['Media'];
      final cover = (media as Map<String, dynamic>?)?['coverImage'];
      return (cover as Map<String, dynamic>?)?['large'] as String?;
    } catch (_) {
      return null;
    }
  }
}
