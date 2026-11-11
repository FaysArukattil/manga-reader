import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../data/library_repository.dart';
import '../models/series.dart';
import '../services/anilist_service.dart';
import '../services/category_store.dart';
import '../services/mangadex_service.dart';
import '../services/scrape/scrape_service.dart';
import '../services/thumbnail_store.dart';

enum LibrarySort { lastRead, title, added }

const Object _keep = Object();

class LibraryState extends Equatable {
  const LibraryState({
    this.loading = true,
    this.all = const [],
    this.visible = const [],
    this.fromCache = false,
    this.query = '',
    this.sort = LibrarySort.lastRead,
    this.filter,
    this.categoryFilter,
    this.categories = CategoryStore.defaultCategories,
    this.error,
  });

  final bool loading;
  final List<Series> all;
  final List<Series> visible;
  final bool fromCache;
  final String query;
  final LibrarySort sort;
  final ReadStatus? filter;
  final String? categoryFilter;
  final List<String> categories;
  final String? error;

  LibraryState copyWith({
    bool? loading,
    List<Series>? all,
    List<Series>? visible,
    bool? fromCache,
    String? query,
    LibrarySort? sort,
    Object? filter = _keep,
    Object? categoryFilter = _keep,
    List<String>? categories,
    String? error,
  }) =>
      LibraryState(
        loading: loading ?? this.loading,
        all: all ?? this.all,
        visible: visible ?? this.visible,
        fromCache: fromCache ?? this.fromCache,
        query: query ?? this.query,
        sort: sort ?? this.sort,
        filter: identical(filter, _keep) ? this.filter : filter as ReadStatus?,
        categoryFilter: identical(categoryFilter, _keep)
            ? this.categoryFilter
            : categoryFilter as String?,
        categories: categories ?? this.categories,
        error: error ?? this.error,
      );

  @override
  List<Object?> get props => [
        loading,
        all,
        visible,
        fromCache,
        query,
        sort,
        filter,
        categoryFilter,
        categories,
        error,
      ];
}

abstract class LibraryEvent {
  const LibraryEvent();
}

class LibraryStarted extends LibraryEvent {
  const LibraryStarted();
}

class _LibraryReceived extends LibraryEvent {
  const _LibraryReceived(this.snapshot);
  final LibrarySnapshot snapshot;
}

class _LibraryFailed extends LibraryEvent {
  const _LibraryFailed(this.message);
  final String message;
}

class LibraryQueryChanged extends LibraryEvent {
  const LibraryQueryChanged(this.query);
  final String query;
}

class LibrarySortChanged extends LibraryEvent {
  const LibrarySortChanged(this.sort);
  final LibrarySort sort;
}

class LibraryFilterChanged extends LibraryEvent {
  const LibraryFilterChanged(this.filter);
  final ReadStatus? filter;
}

class LibraryCategoryFilterChanged extends LibraryEvent {
  const LibraryCategoryFilterChanged(this.category);
  final String? category;
}

class LibraryCategoriesLoaded extends LibraryEvent {
  const LibraryCategoriesLoaded(this.categories);
  final List<String> categories;
}

class LibraryCategoryAdded extends LibraryEvent {
  const LibraryCategoryAdded(this.name);
  final String name;
}

class LibraryCategoryRemoved extends LibraryEvent {
  const LibraryCategoryRemoved(this.name);
  final String name;
}

class LibraryMoveSeriesRequested extends LibraryEvent {
  const LibraryMoveSeriesRequested(this.series, this.newCategory);
  final Series series;
  final String? newCategory;
}

class LibraryMarkSeriesRead extends LibraryEvent {
  const LibraryMarkSeriesRead(this.seriesId);
  final String seriesId;
}

class LibraryAddRequested extends LibraryEvent {
  const LibraryAddRequested(this.series);
  final Series series;
}

class LibraryEditRequested extends LibraryEvent {
  const LibraryEditRequested(this.series, {this.refetchCover = false});
  final Series series;
  final bool refetchCover;
}

class LibraryDeleteRequested extends LibraryEvent {
  const LibraryDeleteRequested(this.series);
  final Series series;
}

/// Checks MangaDex for new chapters of series on the shelf (one batched
/// request, throttled to once per 15 minutes unless [force]).
class LibraryUpdatesRequested extends LibraryEvent {
  const LibraryUpdatesRequested({this.force = false});
  final bool force;
}

class LibraryBloc extends Bloc<LibraryEvent, LibraryState> {
  LibraryBloc(
    this._repo,
    this._anilist,
    this._thumbs,
    this._md, [
    ScrapeService? scrape,
  ])  : _scrape = scrape ?? ScrapeService(),
        super(const LibraryState()) {
    on<LibraryStarted>(_onStarted);
    on<_LibraryReceived>(
      (e, emit) => emit(
        _recompute(
          state.copyWith(
            loading: false,
            all: e.snapshot.items,
            fromCache: e.snapshot.fromCache,
          ),
        ),
      ),
    );
    on<_LibraryFailed>(
      (e, emit) => emit(state.copyWith(loading: false, error: e.message)),
    );
    on<LibraryQueryChanged>(
      (e, emit) => emit(_recompute(state.copyWith(query: e.query))),
    );
    on<LibrarySortChanged>(
      (e, emit) => emit(_recompute(state.copyWith(sort: e.sort))),
    );
    on<LibraryFilterChanged>(
      (e, emit) => emit(_recompute(state.copyWith(filter: e.filter))),
    );
    on<LibraryCategoryFilterChanged>(
      (e, emit) => emit(_recompute(state.copyWith(categoryFilter: e.category))),
    );
    on<LibraryCategoriesLoaded>(
      (e, emit) => emit(state.copyWith(categories: e.categories)),
    );
    on<LibraryCategoryAdded>(_onCategoryAdded);
    on<LibraryCategoryRemoved>(_onCategoryRemoved);
    on<LibraryMoveSeriesRequested>(_onMoveSeries);
    on<LibraryMarkSeriesRead>(_onMarkRead);
    on<LibraryAddRequested>(_onAdd);
    on<LibraryEditRequested>(_onEdit);
    on<LibraryDeleteRequested>(_onDelete);
    on<LibraryUpdatesRequested>(_onUpdates);
  }

  final LibraryRepository _repo;
  final AniListService _anilist;
  final ThumbnailStore _thumbs;
  final MangaDexService _md;
  final ScrapeService _scrape;
  bool _checked = false;
  DateTime? _lastCheck;
  StreamSubscription<LibrarySnapshot>? _sub;

  Future<void> _onStarted(LibraryStarted e, Emitter<LibraryState> emit) async {
    _sub?.cancel();
    final cats = await CategoryStore.getCategories();
    add(LibraryCategoriesLoaded(cats));

    _sub = _repo.watch().listen((s) {
      add(_LibraryReceived(s));
      if (!_checked) {
        _checked = true;
        add(const LibraryUpdatesRequested());
      }
    }, onError: (Object err) => add(_LibraryFailed(err.toString())));
  }

  Future<void> _onCategoryAdded(
    LibraryCategoryAdded e,
    Emitter<LibraryState> emit,
  ) async {
    final updated = await CategoryStore.addCategory(e.name);
    emit(state.copyWith(categories: updated));
  }

  Future<void> _onCategoryRemoved(
    LibraryCategoryRemoved e,
    Emitter<LibraryState> emit,
  ) async {
    final updated = await CategoryStore.removeCategory(e.name);
    final nextFilter =
        state.categoryFilter == e.name ? null : state.categoryFilter;
    emit(_recompute(
        state.copyWith(categories: updated, categoryFilter: nextFilter)));
  }

  Future<void> _onMoveSeries(
    LibraryMoveSeriesRequested e,
    Emitter<LibraryState> emit,
  ) async {
    _repo.update(e.series.id, {'category': e.newCategory}, touch: false);
  }

  Future<void> _onMarkRead(
    LibraryMarkSeriesRead e,
    Emitter<LibraryState> emit,
  ) async {
    _repo.update(
      e.seriesId,
      {
        'lastReadAt': Timestamp.now(),
        'readCount': FieldValue.increment(1),
      },
      touch: false,
    );
  }

  Future<void> _onAdd(LibraryAddRequested e, Emitter<LibraryState> emit) async {
    final s = e.series;
    _repo.add(s);
    if (s.mdId == null) {
      if (!s.titleAuto && s.title.isNotEmpty) {
        final cover = await _anilist.findCover(s.title);
        if (cover != null) {
          _repo.update(s.id, {'coverUrl': cover}, touch: false);
          return;
        }
      }
      // Auto-extract thumbnail directly from website (og:image, cover meta, or page 1)
      try {
        final scraped = await _scrape.scrapeChapter(s.url);
        final cover = scraped.coverUrl ??
            (scraped.pages.isNotEmpty ? scraped.pages.first : null);
        if (cover != null && cover.startsWith('http')) {
          _repo.update(s.id, {'coverUrl': cover}, touch: false);
        }
      } catch (_) {}
    }
  }

  Future<void> _onEdit(
    LibraryEditRequested e,
    Emitter<LibraryState> emit,
  ) async {
    final s = e.series;
    _repo.update(
        s.id,
        {
          'title': s.title,
          'titleAuto': false,
          'url': s.url,
          'host': s.host,
          'chapter': s.chapter,
          'status': s.status.name,
          'scroll': s.scroll,
        },
        touch: false);
    if (e.refetchCover) {
      if (!s.titleAuto && s.title.isNotEmpty) {
        final cover = await _anilist.findCover(s.title);
        if (cover != null) {
          _repo.update(s.id, {'coverUrl': cover}, touch: false);
          return;
        }
      }
      try {
        final scraped = await _scrape.scrapeChapter(s.url);
        final cover = scraped.coverUrl ??
            (scraped.pages.isNotEmpty ? scraped.pages.first : null);
        if (cover != null && cover.startsWith('http')) {
          _repo.update(s.id, {'coverUrl': cover}, touch: false);
        }
      } catch (_) {}
    }
  }

  Future<void> _onDelete(
    LibraryDeleteRequested e,
    Emitter<LibraryState> emit,
  ) async {
    _repo.delete(e.series.id);
    await _thumbs.delete(e.series.id);
  }

  Future<void> _onUpdates(
    LibraryUpdatesRequested e,
    Emitter<LibraryState> emit,
  ) async {
    final now = DateTime.now();
    final last = _lastCheck;
    if (!e.force && last != null && now.difference(last).inMinutes < 15) return;
    _lastCheck = now;
    // 1. MangaDex series check
    final md = state.all.where((s) => s.mdId != null).toList();
    if (md.isNotEmpty) {
      try {
        final latest = await _md.latestChapterIds(
          md.map((s) => s.mdId!).toList(),
        );
        for (final s in md) {
          final newest = latest[s.mdId];
          if (newest != null && newest != s.mdNewest) {
            _repo.update(s.id, {'mdNewest': newest}, touch: false);
          }
        }
      } catch (_) {
        // Offline or rate limited: try again next time.
      }
    }

    // 2. Tracked website series check (run sequentially, battery-friendly)
    final webSeries = state.all
        .where((s) => s.mdId == null && s.status == ReadStatus.reading)
        .toList();
    for (final s in webSeries) {
      if (!e.force &&
          s.lastCheckedAt != null &&
          now.difference(s.lastCheckedAt!).inMinutes < 45) {
        continue;
      }
      try {
        final currentChapter = s.chapterUrl ?? s.url;
        // Live check (bypasses the chapter cache) - but a guessed "chapter+1"
        // URL is not evidence of a new chapter, only a real next link is.
        final res =
            await _scrape.scrapeChapter(currentChapter, forceRefresh: true);
        final nextUrl = res.nextChapterUrl;
        if (res.needsVerification) continue;
        if (nextUrl != null && !res.nextGuessed && nextUrl != currentChapter) {
          _repo.update(
            s.id,
            {
              'newestChapterUrl': nextUrl,
              'lastCheckedAt': Timestamp.fromDate(now),
            },
            touch: false,
          );
        } else {
          _repo.update(
            s.id,
            {'lastCheckedAt': Timestamp.fromDate(now)},
            touch: false,
          );
        }
      } catch (_) {}
    }
  }

  LibraryState _recompute(LibraryState base) {
    final q = base.query.trim().toLowerCase();
    final list = base.all.where((s) {
      if (base.filter != null && s.status != base.filter) return false;
      if (base.categoryFilter != null) {
        final targetCat = base.categoryFilter!.trim().toLowerCase();
        final seriesCat = (s.category ?? s.status.label).trim().toLowerCase();
        if (seriesCat != targetCat) return false;
      }
      if (q.isEmpty) return true;
      return s.title.toLowerCase().contains(q) || s.host.contains(q);
    }).toList();
    switch (base.sort) {
      case LibrarySort.lastRead:
        list.sort((a, b) {
          final timeA = a.lastReadAt ?? a.updatedAt;
          final timeB = b.lastReadAt ?? b.updatedAt;
          final timeCmp = timeB.compareTo(timeA);
          if (timeCmp != 0) return timeCmp;
          return b.readCount.compareTo(a.readCount);
        });
      case LibrarySort.title:
        list.sort(
          (a, b) => a.title.toLowerCase().compareTo(b.title.toLowerCase()),
        );
      case LibrarySort.added:
        list.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    }
    return base.copyWith(visible: list);
  }

  @override
  Future<void> close() {
    _sub?.cancel();
    return super.close();
  }
}
