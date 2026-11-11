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

/// One entry on the shelf. Either a tracked website (url-based, scraped natively)
/// or a MangaDex series (mdId != null, read natively).
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
    // Universal native reader progress fields
    this.chapterUrl,
    this.pageIndex = 0,
    this.pageKey,
    this.pageOffset = 0,
    this.vertical,
    this.rtl,
    this.lastCheckedAt,
    this.newestChapterUrl,
    this.seenChapterUrl,
    // MangaDex-only fields
    this.mdId,
    this.mdChapterId,
    this.mdPage = 0,
    this.mdNewest,
    this.mdSeen,
    // Custom category and reading frequency
    this.category,
    this.readCount = 0,
    this.lastReadAt,
  });

  /// Website entry.
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
      chapterUrl: url,
      status: status,
      createdAt: now,
      updatedAt: now,
    );
  }

  /// MangaDex entry.
  factory Series.md({
    required String id,
    required String mdId,
    required String title,
    String? coverUrl,
    String? newest,
  }) {
    final now = DateTime.now();
    return Series(
      id: id,
      title: title,
      url: 'https://mangadex.org/title/$mdId',
      host: 'mangadex.org',
      coverUrl: coverUrl,
      createdAt: now,
      updatedAt: now,
      mdId: mdId,
      mdNewest: newest,
      mdSeen: newest,
    );
  }

  factory Series.fromMap(String id, Map<String, dynamic> m) {
    DateTime ts(Object? v) =>
        v is Timestamp ? v.toDate() : DateTime.fromMillisecondsSinceEpoch(0);
    DateTime? optTs(Object? v) => v is Timestamp ? v.toDate() : null;

    final url = (m['url'] as String?) ?? '';
    final scrollVal = ((m['scroll'] as num?) ?? 0).toDouble();
    final pIdx =
        ((m['pageIndex'] as num?) ?? (scrollVal >= 1.0 ? scrollVal.toInt() : 0))
            .toInt();

    return Series(
      id: id,
      title: (m['title'] as String?) ?? '',
      url: url,
      host: (m['host'] as String?) ?? UrlTools.hostOf(url),
      titleAuto: (m['titleAuto'] as bool?) ?? false,
      coverUrl: m['coverUrl'] as String?,
      chapter: (m['chapter'] as String?) ?? '',
      status: ReadStatus.parse(m['status']),
      scroll: scrollVal,
      mode: ((m['mode'] as num?) ?? 0).toInt(),
      dim: ((m['dim'] as num?) ?? 0).toDouble(),
      chapterUrl: m['chapterUrl'] as String?,
      pageIndex: pIdx,
      pageKey: m['pageKey'] as String?,
      pageOffset: ((m['pageOffset'] as num?) ?? 0).toDouble(),
      vertical: m['vertical'] as bool?,
      rtl: m['rtl'] as bool?,
      lastCheckedAt: optTs(m['lastCheckedAt']),
      newestChapterUrl: m['newestChapterUrl'] as String?,
      seenChapterUrl: m['seenChapterUrl'] as String?,
      createdAt: ts(m['createdAt']),
      updatedAt: ts(m['updatedAt']),
      mdId: m['mdId'] as String?,
      mdChapterId: m['mdChapterId'] as String?,
      mdPage: ((m['mdPage'] as num?) ?? 0).toInt(),
      mdNewest: m['mdNewest'] as String?,
      mdSeen: m['mdSeen'] as String?,
      category: m['category'] as String?,
      readCount: ((m['readCount'] as num?) ?? 0).toInt(),
      lastReadAt: optTs(m['lastReadAt']),
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
  final double scroll; // backwards compatibility: 0..1 or integer page
  final int mode; // 0 off, 1 dark, 2 warm
  final double dim; // 0..0.7 dimmer overlay
  final DateTime createdAt;
  final DateTime updatedAt;

  // Universal native reader progress fields
  final String? chapterUrl;
  final int pageIndex;
  final String? pageKey;
  final double pageOffset;
  final bool? vertical;
  final bool? rtl;
  final DateTime? lastCheckedAt;
  final String? newestChapterUrl;
  final String? seenChapterUrl;

  // MangaDex-only fields
  final String? mdId;
  final String? mdChapterId;
  final int mdPage;
  final String? mdNewest;
  final String? mdSeen;

  // Custom Category and Frequency
  final String? category;
  final int readCount;
  final DateTime? lastReadAt;

  bool get isMangaDex => mdId != null;

  bool get hasNew {
    if (isMangaDex) {
      return mdNewest != null && mdNewest != mdSeen;
    }
    return newestChapterUrl != null &&
        newestChapterUrl != seenChapterUrl &&
        newestChapterUrl != (chapterUrl ?? url);
  }

  String get resumeLabel {
    final ch = chapter.isNotEmpty
        ? chapter
        : (mdChapterId != null ? 'Ch $mdChapterId' : '');
    final p = pageIndex > 0 ? pageIndex + 1 : (mdPage > 0 ? mdPage + 1 : null);
    if (ch.isNotEmpty && p != null) return '$ch · p. $p';
    if (ch.isNotEmpty) return ch;
    if (p != null) return 'p. $p';
    return '';
  }

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
        if (chapterUrl != null) 'chapterUrl': chapterUrl,
        'pageIndex': pageIndex,
        if (pageKey != null) 'pageKey': pageKey,
        'pageOffset': pageOffset,
        if (vertical != null) 'vertical': vertical,
        if (rtl != null) 'rtl': rtl,
        if (lastCheckedAt != null)
          'lastCheckedAt': Timestamp.fromDate(lastCheckedAt!),
        if (newestChapterUrl != null) 'newestChapterUrl': newestChapterUrl,
        if (seenChapterUrl != null) 'seenChapterUrl': seenChapterUrl,
        'createdAt': Timestamp.fromDate(createdAt),
        'updatedAt': Timestamp.fromDate(updatedAt),
        'mdId': mdId,
        'mdChapterId': mdChapterId,
        'mdPage': mdPage,
        'mdNewest': mdNewest,
        'mdSeen': mdSeen,
        if (category != null) 'category': category,
        'readCount': readCount,
        if (lastReadAt != null) 'lastReadAt': Timestamp.fromDate(lastReadAt!),
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
    String? chapterUrl,
    int? pageIndex,
    String? pageKey,
    double? pageOffset,
    bool? vertical,
    bool? rtl,
    DateTime? lastCheckedAt,
    String? newestChapterUrl,
    String? seenChapterUrl,
    DateTime? updatedAt,
    String? mdId,
    String? mdChapterId,
    int? mdPage,
    String? mdNewest,
    String? mdSeen,
    String? category,
    int? readCount,
    DateTime? lastReadAt,
    bool clearCategory = false,
  }) =>
      Series(
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
        chapterUrl: chapterUrl ?? this.chapterUrl,
        pageIndex: pageIndex ?? this.pageIndex,
        pageKey: pageKey ?? this.pageKey,
        pageOffset: pageOffset ?? this.pageOffset,
        vertical: vertical ?? this.vertical,
        rtl: rtl ?? this.rtl,
        lastCheckedAt: lastCheckedAt ?? this.lastCheckedAt,
        newestChapterUrl: newestChapterUrl ?? this.newestChapterUrl,
        seenChapterUrl: seenChapterUrl ?? this.seenChapterUrl,
        createdAt: createdAt,
        updatedAt: updatedAt ?? this.updatedAt,
        mdId: mdId ?? this.mdId,
        mdChapterId: mdChapterId ?? this.mdChapterId,
        mdPage: mdPage ?? this.mdPage,
        mdNewest: mdNewest ?? this.mdNewest,
        mdSeen: mdSeen ?? this.mdSeen,
        category: clearCategory ? null : (category ?? this.category),
        readCount: readCount ?? this.readCount,
        lastReadAt: lastReadAt ?? this.lastReadAt,
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
        chapterUrl,
        pageIndex,
        pageKey,
        pageOffset,
        vertical,
        rtl,
        lastCheckedAt,
        newestChapterUrl,
        seenChapterUrl,
        createdAt,
        updatedAt,
        mdId,
        mdChapterId,
        mdPage,
        mdNewest,
        mdSeen,
        category,
        readCount,
        lastReadAt,
      ];
}
