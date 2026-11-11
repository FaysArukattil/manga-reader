import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';

class ProgressRecord {
  const ProgressRecord({
    required this.chapterUrl,
    required this.pageIndex,
    this.pageKey,
    this.pageOffset = 0,
    required this.updatedAt,
  });

  final String chapterUrl;
  final int pageIndex;
  final String? pageKey;
  final double pageOffset;
  final DateTime updatedAt;

  Map<String, dynamic> toMap() => {
        'chapterUrl': chapterUrl,
        'pageIndex': pageIndex,
        if (pageKey != null) 'pageKey': pageKey,
        'pageOffset': pageOffset,
        'updatedAt': updatedAt.millisecondsSinceEpoch,
      };

  factory ProgressRecord.fromMap(Map<String, dynamic> m) {
    return ProgressRecord(
      chapterUrl: (m['chapterUrl'] as String?) ?? '',
      pageIndex: ((m['pageIndex'] as num?) ?? 0).toInt(),
      pageKey: m['pageKey'] as String?,
      pageOffset: ((m['pageOffset'] as num?) ?? 0).toDouble(),
      updatedAt: DateTime.fromMillisecondsSinceEpoch(
        ((m['updatedAt'] as num?) ?? 0).toInt(),
      ),
    );
  }
}

class LocalProgressStore {
  LocalProgressStore._();

  static const String _prefix = 'progress_';

  static Future<void> save({
    required String seriesId,
    required String chapterUrl,
    required int pageIndex,
    String? pageKey,
    double pageOffset = 0,
  }) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final record = ProgressRecord(
        chapterUrl: chapterUrl,
        pageIndex: pageIndex,
        pageKey: pageKey,
        pageOffset: pageOffset,
        updatedAt: DateTime.now(),
      );
      await prefs.setString('$_prefix$seriesId', jsonEncode(record.toMap()));
    } catch (_) {}
  }

  static Future<ProgressRecord?> get(String seriesId) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString('$_prefix$seriesId');
      if (raw == null) return null;
      return ProgressRecord.fromMap(jsonDecode(raw) as Map<String, dynamic>);
    } catch (_) {
      return null;
    }
  }

  static Future<void> delete(String seriesId) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove('$_prefix$seriesId');
    } catch (_) {}
  }
}
