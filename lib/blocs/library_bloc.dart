import 'dart:async';

import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../data/library_repository.dart';
import '../models/series.dart';
import '../services/anilist_service.dart';
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
    this.error,
  });

  final bool loading;
  final List<Series> all;
  final List<Series> visible;
  final bool fromCache;
  final String query;
  final LibrarySort sort;
  final ReadStatus? filter;
  final String? error;

  LibraryState copyWith({
    bool? loading,
    List<Series>? all,
    List<Series>? visible,
    bool? fromCache,
    String? query,
    LibrarySort? sort,
    Object? filter = _keep,
    String? error,
  }) => LibraryState(
    loading: loading ?? this.loading,
    all: all ?? this.all,
    visible: visible ?? this.visible,
    fromCache: fromCache ?? this.fromCache,
    query: query ?? this.query,
    sort: sort ?? this.sort,
    filter: identical(filter, _keep) ? this.filter : filter as ReadStatus?,
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

class LibraryBloc extends Bloc<LibraryEvent, LibraryState> {
  LibraryBloc(this._repo, this._anilist, this._thumbs)
    : super(const LibraryState()) {
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
    on<LibraryAddRequested>(_onAdd);
    on<LibraryEditRequested>(_onEdit);
    on<LibraryDeleteRequested>(_onDelete);
  }

  final LibraryRepository _repo;
  final AniListService _anilist;
  final ThumbnailStore _thumbs;
  StreamSubscription<LibrarySnapshot>? _sub;

  void _onStarted(LibraryStarted e, Emitter<LibraryState> emit) {
    _sub?.cancel();
    _sub = _repo.watch().listen(
      (s) => add(_LibraryReceived(s)),
      onError: (Object err) => add(_LibraryFailed(err.toString())),
    );
  }

  Future<void> _onAdd(LibraryAddRequested e, Emitter<LibraryState> emit) async {
    final s = e.series;
    _repo.add(s);
    if (!s.titleAuto && s.title.isNotEmpty) {
      final cover = await _anilist.findCover(s.title);
      if (cover != null) _repo.update(s.id, {'coverUrl': cover}, touch: false);
    }
  }

  Future<void> _onEdit(
    LibraryEditRequested e,
    Emitter<LibraryState> emit,
  ) async {
    final s = e.series;
    _repo.update(s.id, {
      'title': s.title,
      'titleAuto': false,
      'url': s.url,
      'host': s.host,
      'chapter': s.chapter,
      'status': s.status.name,
      'scroll': s.scroll,
    }, touch: false);
    if (e.refetchCover) {
      final cover = await _anilist.findCover(s.title);
      if (cover != null) _repo.update(s.id, {'coverUrl': cover}, touch: false);
    }
  }

  Future<void> _onDelete(
    LibraryDeleteRequested e,
    Emitter<LibraryState> emit,
  ) async {
    _repo.delete(e.series.id);
    await _thumbs.delete(e.series.id);
  }

  LibraryState _recompute(LibraryState base) {
    final q = base.query.trim().toLowerCase();
    final list = base.all.where((s) {
      if (base.filter != null && s.status != base.filter) return false;
      if (q.isEmpty) return true;
      return s.title.toLowerCase().contains(q) || s.host.contains(q);
    }).toList();
    switch (base.sort) {
      case LibrarySort.lastRead:
        list.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
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
