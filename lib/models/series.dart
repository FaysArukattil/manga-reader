import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:equatable/equatable.dart';

import '../core/url_tools.dart';

enum ReadStatus {
  reading('Reading'),
  planned('Plan to read'),
  completed('Completed'),
  dropped('Dropped');

  const ReadStatus(this.label);
  final String label;

  static ReadStatus parse(Object? v) {
    for (final s in ReadStatus.values) {
      if (s.name == v) return s;
    }
    return ReadStatus.reading;
  }
}

class Series extends Equatable {
  const Series({
    required this.id,
    required this.title,
    required this.url,
    required this.host,
    required this.createdAt,
    required this.updatedAt,
    this.titleAuto = false,
    this.coverUrl,
    this.chapter = '',
    this.status = ReadStatus.reading,
    this.scroll = 0,
    this.mode = 0,
    this.dim = 0,
  });

  factory Series.create({
    required String id,
    required String url,
    String title = '',
    ReadStatus status = ReadStatus.reading,
  }) {
    final host = UrlTools.hostOf(url);
    final now = DateTime.now();
    return Series(
      id: id,
      title: title.isEmpty ? host : title,
      titleAuto: title.isEmpty,
      url: url,
      host: host,
      chapter: UrlTools.chapterLabel(url) ?? '',
      status: status,
      createdAt: now,
      updatedAt: now,
    );
  }

  factory Series.fromMap(String id, Map<String, dynamic> m) {
    DateTime ts(Object? v) =>
        v is Timestamp ? v.toDate() : DateTime.fromMillisecondsSinceEpoch(0);
    final url = (m['url'] as String?) ?? '';
    return Series(
      id: id,
      title: (m['title'] as String?) ?? '',
      url: url,
      host: (m['host'] as String?) ?? UrlTools.hostOf(url),
      titleAuto: (m['titleAuto'] as bool?) ?? false,
      coverUrl: m['coverUrl'] as String?,
      chapter: (m['chapter'] as String?) ?? '',
      status: ReadStatus.parse(m['status']),
      scroll: ((m['scroll'] as num?) ?? 0).toDouble(),
      mode: ((m['mode'] as num?) ?? 0).toInt(),
      dim: ((m['dim'] as num?) ?? 0).toDouble(),
      createdAt: ts(m['createdAt']),
      updatedAt: ts(m['updatedAt']),
    );
  }

  final String id;
  final String title;
  final String url;
  final String host;
  final bool titleAuto;
  final String? coverUrl;
  final String chapter;
  final ReadStatus status;
  final double scroll; // 0..1 position inside the saved page
  final int mode; // 0 off, 1 dark, 2 warm
  final double dim; // 0..0.7 black overlay
  final DateTime createdAt;
  final DateTime updatedAt;

  Map<String, dynamic> toMap() => {
    'title': title,
    'titleAuto': titleAuto,
    'url': url,
    'host': host,
    'coverUrl': coverUrl,
    'chapter': chapter,
    'status': status.name,
    'scroll': scroll,
    'mode': mode,
    'dim': dim,
    'createdAt': Timestamp.fromDate(createdAt),
    'updatedAt': Timestamp.fromDate(updatedAt),
  };

  Series copyWith({
    String? title,
    String? url,
    String? host,
    bool? titleAuto,
    String? coverUrl,
    String? chapter,
    ReadStatus? status,
    double? scroll,
    int? mode,
    double? dim,
    DateTime? updatedAt,
  }) => Series(
    id: id,
    title: title ?? this.title,
    url: url ?? this.url,
    host: host ?? this.host,
    titleAuto: titleAuto ?? this.titleAuto,
    coverUrl: coverUrl ?? this.coverUrl,
    chapter: chapter ?? this.chapter,
    status: status ?? this.status,
    scroll: scroll ?? this.scroll,
    mode: mode ?? this.mode,
    dim: dim ?? this.dim,
    createdAt: createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
  );

  @override
  List<Object?> get props => [
    id,
    title,
    url,
    host,
    titleAuto,
    coverUrl,
    chapter,
    status,
    scroll,
    mode,
    dim,
    createdAt,
    updatedAt,
  ];
}
