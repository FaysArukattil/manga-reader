import 'dart:async';
import 'dart:math' as math;

import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../data/library_repository.dart';
import '../services/mangadex_service.dart';
import '../services/page_cache.dart';

// ---------------------------------------------------------------- Discover

class DiscoverState extends Equatable {
  const DiscoverState({
    this.loading = true,
    this.loadingMore = false,
    this.results = const [],
    this.query = '',
    this.error,
    this.endReached = false,
  });

  final bool loading;
  final bool loadingMore;
  final List<MdManga> results;
  final String query;
  final String? error;
  final bool endReached;

  DiscoverState copyWith({
    bool? loading,
    bool? loadingMore,
    List<MdManga>? results,
    String? query,
    String? error,
    bool clearError = false,
    bool? endReached,
  }) =>
      DiscoverState(
        loading: loading ?? this.loading,
        loadingMore: loadingMore ?? this.loadingMore,
        results: results ?? this.results,
        query: query ?? this.query,
        error: clearError ? null : (error ?? this.error),
        endReached: endReached ?? this.endReached,
      );

  @override
  List<Object?> get props => [
        loading,
        loadingMore,
        results,
        query,
        error,
        endReached,
      ];
}

class DiscoverCubit extends Cubit<DiscoverState> {
  DiscoverCubit(this._service) : super(const DiscoverState()) {
    search('');
  }

  final MangaDexService _service;
  int _token = 0;

  Future<void> search(String query) async {
    final token = ++_token;
    emit(DiscoverState(query: query));
    try {
      final r = await _service.search(query);
      if (isClosed || token != _token) return;
      emit(
        DiscoverState(
          loading: false,
          query: query,
          results: r,
          endReached: r.length < 24,
        ),
      );
    } catch (e) {
      if (isClosed || token != _token) return;
      emit(DiscoverState(loading: false, query: query, error: e.toString()));
    }
  }

  Future<void> loadMore() async {
    if (state.loading || state.loadingMore || state.endReached) return;
    final token = _token;
    emit(state.copyWith(loadingMore: true));
    try {
      final r = await _service.search(
        state.query,
        offset: state.results.length,
      );
      if (isClosed || token != _token) return;
      final known = state.results.map((m) => m.id).toSet();
      emit(
        state.copyWith(
          loadingMore: false,
          results: [...state.results, ...r.where((m) => !known.contains(m.id))],
          endReached: r.length < 24,
        ),
      );
    } catch (_) {
      if (!isClosed) emit(state.copyWith(loadingMore: false));
    }
  }
}

// ------------------------------------------------------------------ Detail

class MdDetailState extends Equatable {
  const MdDetailState({
    this.loading = true,
    this.chapters = const [],
    this.error,
    this.offlineList = false,
  });

  final bool loading;
  final List<MdChapter> chapters; // oldest first
  final String? error;
  final bool offlineList;

  @override
  List<Object?> get props => [loading, chapters, error, offlineList];
}

class MdDetailCubit extends Cubit<MdDetailState> {
  MdDetailCubit(this._service, this._store, this.mangaId)
      : super(const MdDetailState()) {
    load();
  }

  final MangaDexService _service;
  final ChapterStore _store;
  final String mangaId;

  Future<void> load() async {
    emit(const MdDetailState());
    try {
      final list = await _service.chapters(mangaId);
      if (isClosed) return;
      emit(MdDetailState(loading: false, chapters: list));
      _store.saveChapters(mangaId, list);
    } catch (e) {
      final cached = await _store.loadChapters(mangaId);
      if (isClosed) return;
      if (cached != null && cached.isNotEmpty) {
        emit(
          MdDetailState(loading: false, chapters: cached, offlineList: true),
        );
      } else {
        emit(MdDetailState(loading: false, error: e.toString()));
      }
    }
  }
}

// ------------------------------------------------------------------ Reader

const Object _keep = Object();

class MdReaderState extends Equatable {
  const MdReaderState({
    required this.index,
    this.page = 0,
    this.loading = true,
    this.error,
    this.urls = const [],
    this.vertical = false,
    this.rtl = false,
    this.dataSaver = false,
    this.showUi = false,
    this.download,
    this.message,
  });

  final int index; // chapter index
  final int page;
  final bool loading;
  final String? error;
  final List<String> urls;
  final bool vertical; // false = horizontal "book", true = vertical "reels"
  final bool rtl; // right-to-left (manga) for horizontal mode
  final bool dataSaver;
  final bool showUi;
  final double? download; // 0..1 while saving offline
  final String? message; // one-shot snackbar text

  MdReaderState copyWith({
    int? index,
    int? page,
    bool? loading,
    Object? error = _keep,
    List<String>? urls,
    bool? vertical,
    bool? rtl,
    bool? dataSaver,
    bool? showUi,
    Object? download = _keep,
    Object? message = _keep,
  }) =>
      MdReaderState(
        index: index ?? this.index,
        page: page ?? this.page,
        loading: loading ?? this.loading,
        error: identical(error, _keep) ? this.error : error as String?,
        urls: urls ?? this.urls,
        vertical: vertical ?? this.vertical,
        rtl: rtl ?? this.rtl,
        dataSaver: dataSaver ?? this.dataSaver,
        showUi: showUi ?? this.showUi,
        download:
            identical(download, _keep) ? this.download : download as double?,
        message: identical(message, _keep) ? this.message : message as String?,
      );

  @override
  List<Object?> get props => [
        index,
        page,
        loading,
        error,
        urls,
        vertical,
        rtl,
        dataSaver,
        showUi,
        download,
        message,
      ];
}

class MdReaderCubit extends Cubit<MdReaderState> {
  MdReaderCubit({
    required MangaDexService service,
    required ChapterStore store,
    required this.chapters,
    required int startIndex,
    int startPage = 0,
    LibraryRepository? library,
    this.seriesId,
  })  : _service = service,
        _store = store,
        _library = library,
        super(MdReaderState(index: startIndex, page: startPage)) {
    loadChapter(startIndex, startPage: startPage);
  }

  final MangaDexService _service;
  final ChapterStore _store;
  final LibraryRepository? _library;
  final String? seriesId;
  final List<MdChapter> chapters;
  final Map<String, List<String>> _warm = {};
  Timer? _debounce;

  MdChapter get current => chapters[state.index];
  bool get hasNext => state.index < chapters.length - 1;
  bool get hasPrev => state.index > 0;

  Future<List<String>> _urls(MdChapter c) async {
    final saved = await _store.loadUrls(c.id); // offline copy wins
    if (saved != null) return saved;
    final warm = _warm[c.id];
    if (warm != null) return warm;
    final fresh = await _service.pageUrls(c.id, dataSaver: state.dataSaver);
    _warm[c.id] = fresh;
    return fresh;
  }

  Future<void> loadChapter(int index, {int startPage = 0}) async {
    emit(
      state.copyWith(
        index: index,
        page: startPage,
        loading: true,
        error: null,
        urls: const [],
      ),
    );
    try {
      final urls = await _urls(chapters[index]);
      if (isClosed) return;
      final page = math.min(
        math.max(startPage, 0),
        math.max(urls.length - 1, 0),
      );
      emit(state.copyWith(loading: false, urls: urls, page: page));
      _saveProgress();
    } catch (e) {
      if (!isClosed) emit(state.copyWith(loading: false, error: e.toString()));
    }
  }

  void next() {
    if (hasNext) loadChapter(state.index + 1);
  }

  void prev() {
    if (hasPrev) loadChapter(state.index - 1);
  }

  void setPage(int page) {
    if (isClosed) return;
    emit(state.copyWith(page: page));
    _debounce?.cancel();
    _debounce = Timer(const Duration(seconds: 2), _saveProgress);
    // Warm the next chapter's URL list near the end so crossing is instant.
    if (hasNext && page >= state.urls.length - 3) {
      final n = chapters[state.index + 1];
      if (!_warm.containsKey(n.id)) {
        _urls(n).catchError((Object _) => <String>[]);
      }
    }
  }

  void _saveProgress() {
    final lib = _library;
    final id = seriesId;
    if (lib == null || id == null) return;
    lib.update(id, {
      'mdChapterId': current.id,
      'chapter': current.label,
      'mdPage': state.page,
    });
  }

  void flush() {
    _debounce?.cancel();
    _saveProgress();
  }

  void toggleUi() => emit(state.copyWith(showUi: !state.showUi));
  void hideUi() {
    if (state.showUi) emit(state.copyWith(showUi: false));
  }

  void setVertical(bool v) => emit(state.copyWith(vertical: v));
  void setRtl(bool v) => emit(state.copyWith(rtl: v));

  Future<void> setDataSaver(bool v) async {
    emit(state.copyWith(dataSaver: v));
    _warm.clear();
    await loadChapter(state.index, startPage: state.page);
  }

  void clearMessage() => emit(state.copyWith(message: null));

  Future<void> downloadCurrent() async {
    final c = current;
    final urls = state.urls;
    if (urls.isEmpty || state.download != null) return;
    emit(state.copyWith(download: 0.0));
    try {
      var done = 0;
      for (var i = 0; i < urls.length; i += 3) {
        final batch = urls.skip(i).take(3).toList();
        await Future.wait(
          batch.map(
            (u) => PageCache.instance.downloadFile(u, key: PageCache.keyFor(u)),
          ),
        );
        done += batch.length;
        if (isClosed) return;
        emit(state.copyWith(download: done / urls.length));
      }
      await _store.saveUrls(c.id, urls);
      if (!isClosed) {
        emit(
          state.copyWith(
            download: null,
            message: '${c.label} saved for offline reading',
          ),
        );
      }
    } catch (_) {
      if (!isClosed) {
        emit(
          state.copyWith(
            download: null,
            message: 'Download failed. Try again.',
          ),
        );
      }
    }
  }

  @override
  Future<void> close() {
    _debounce?.cancel();
    _saveProgress();
    return super.close();
  }
}
