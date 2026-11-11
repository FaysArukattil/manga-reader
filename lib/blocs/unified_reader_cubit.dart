import 'dart:async';
import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../data/library_repository.dart';
import '../models/series.dart';
import '../services/local_progress_store.dart';
import '../services/reader/chapter_source.dart';
import '../services/scrape/site_adapter.dart';

class UnifiedReaderState extends Equatable {
  const UnifiedReaderState({
    this.pages = const [],
    this.currentIndex = 0,
    this.loading = true,
    this.loadingNextChapter = false,
    this.isAllCaughtUp = false,
    this.vertical = false,
    this.rtl = false,
    this.pageFlipEffect = true,
    this.soundEffect = true,
    this.dim = 0.0,
    this.availableChapters = const [],
    this.error,
  });

  final List<ReaderPageItem> pages;
  final int currentIndex;
  final bool loading;
  final bool loadingNextChapter;
  final bool isAllCaughtUp;
  final bool vertical;
  final bool rtl;
  final bool pageFlipEffect;
  final bool soundEffect;
  final double dim;
  final List<ChapterRef> availableChapters;
  final String? error;

  ReaderPageItem? get currentPageItem =>
      (currentIndex >= 0 && currentIndex < pages.length)
          ? pages[currentIndex]
          : null;

  String get currentChapterLabel => currentPageItem?.chapterLabel ?? '';

  int get currentPageInChapter => (currentPageItem?.pageIndex ?? 0) + 1;

  int get totalPagesInChapter => currentPageItem?.totalInChapter ?? 1;

  UnifiedReaderState copyWith({
    List<ReaderPageItem>? pages,
    int? currentIndex,
    bool? loading,
    bool? loadingNextChapter,
    bool? isAllCaughtUp,
    bool? vertical,
    bool? rtl,
    bool? pageFlipEffect,
    bool? soundEffect,
    double? dim,
    List<ChapterRef>? availableChapters,
    String? error,
    bool clearError = false,
  }) =>
      UnifiedReaderState(
        pages: pages ?? this.pages,
        currentIndex: currentIndex ?? this.currentIndex,
        loading: loading ?? this.loading,
        loadingNextChapter: loadingNextChapter ?? this.loadingNextChapter,
        isAllCaughtUp: isAllCaughtUp ?? this.isAllCaughtUp,
        vertical: vertical ?? this.vertical,
        rtl: rtl ?? this.rtl,
        pageFlipEffect: pageFlipEffect ?? this.pageFlipEffect,
        soundEffect: soundEffect ?? this.soundEffect,
        dim: dim ?? this.dim,
        availableChapters: availableChapters ?? this.availableChapters,
        error: clearError ? null : (error ?? this.error),
      );

  @override
  List<Object?> get props => [
        pages,
        currentIndex,
        loading,
        loadingNextChapter,
        isAllCaughtUp,
        vertical,
        rtl,
        pageFlipEffect,
        soundEffect,
        dim,
        availableChapters,
        error,
      ];
}

class UnifiedReaderCubit extends Cubit<UnifiedReaderState> {
  UnifiedReaderCubit({
    required this.source,
    required this.series,
    this.library,
    this.startChapterId,
    this.startPageIndex = 0,
    this.startPageKey,
  }) : super(
          UnifiedReaderState(
            vertical: series.vertical ?? false,
            rtl: series.rtl ?? false,
            dim: series.dim,
          ),
        );

  final ChapterSource source;
  final Series series;
  final LibraryRepository? library;
  final String? startChapterId;
  final int startPageIndex;
  final String? startPageKey;

  final Set<String> _loadedChapterIds = {};
  Timer? _debounceSave;
  Timer? _pollTimer;
  DateTime _lastFirestoreSync = DateTime.fromMillisecondsSinceEpoch(0);

  Future<void> init() async {
    final chapterToLoad =
        startChapterId ?? series.chapterUrl ?? series.mdChapterId ?? series.url;

    try {
      final initialPages = await source.loadChapter(chapterToLoad);
      if (initialPages.isEmpty) {
        emit(state.copyWith(
          loading: false,
          error: 'No pages found for this chapter.',
        ));
        return;
      }

      _loadedChapterIds.add(chapterToLoad);

      // Restore position: prioritize pageKey match, fall back to startPageIndex
      int targetIndex = 0;
      if (startPageKey != null) {
        final matchIdx = initialPages.indexWhere(
          (p) => p.pageKey == startPageKey,
        );
        if (matchIdx >= 0) targetIndex = matchIdx;
      }
      if (targetIndex == 0 && startPageIndex > 0) {
        targetIndex = startPageIndex.clamp(0, initialPages.length - 1);
      }

      final catalogue = await source.getAvailableChapters(chapterToLoad);

      emit(state.copyWith(
        pages: initialPages,
        currentIndex: targetIndex,
        loading: false,
        availableChapters: catalogue,
      ));

      _triggerLocalSave();

      // Check if we need to pre-fetch the next chapter
      await _checkPreloadNextChapter();
    } catch (e) {
      emit(state.copyWith(
        loading: false,
        error: 'Failed to load chapter: $e',
      ));
    }
  }

  Future<void> jumpToChapter(String chapterId, {int pageIndex = 0}) async {
    emit(state.copyWith(loading: true, clearError: true));
    try {
      final pages = await source.loadChapter(chapterId);
      if (pages.isEmpty) {
        emit(state.copyWith(
          loading: false,
          error: 'Could not load chapter pages.',
        ));
        return;
      }
      _loadedChapterIds.clear();
      _loadedChapterIds.add(chapterId);
      final target = pageIndex.clamp(0, pages.length - 1);
      final catalogue = await source.getAvailableChapters(chapterId);
      emit(state.copyWith(
        pages: pages,
        currentIndex: target,
        loading: false,
        availableChapters:
            catalogue.isNotEmpty ? catalogue : state.availableChapters,
      ));
      _triggerLocalSave();
      await _checkPreloadNextChapter();
    } catch (e) {
      emit(state.copyWith(
        loading: false,
        error: 'Failed to jump to chapter: $e',
      ));
    }
  }

  void setPageFlipEffect(bool enabled) {
    emit(state.copyWith(pageFlipEffect: enabled));
  }

  void setSoundEffect(bool enabled) {
    emit(state.copyWith(soundEffect: enabled));
  }

  void onPageChanged(int index) {
    if (index < 0 || index >= state.pages.length) return;
    emit(state.copyWith(currentIndex: index));

    _triggerLocalSave();
    _checkPreloadNextChapter();

    // Check if reached end
    if (index >= state.pages.length - 1) {
      _onReachedEnd();
    }
  }

  void _triggerLocalSave() {
    _debounceSave?.cancel();
    _debounceSave = Timer(const Duration(milliseconds: 500), () {
      _flushProgress(forceFirestore: false);
    });
  }

  Future<void> flush() async {
    _debounceSave?.cancel();
    await _flushProgress(forceFirestore: true);
  }

  Future<void> _flushProgress({required bool forceFirestore}) async {
    final current = state.currentPageItem;
    if (current == null) return;

    // 1. Instant local save
    await LocalProgressStore.save(
      seriesId: series.id,
      chapterUrl: current.chapterId,
      pageIndex: current.pageIndex,
      pageKey: current.pageKey,
    );

    // 2. Throttled Firestore sync (max once per 10s or forced)
    final now = DateTime.now();
    if (library != null &&
        (forceFirestore ||
            now.difference(_lastFirestoreSync).inSeconds >= 10)) {
      _lastFirestoreSync = now;
      library!.update(series.id, {
        'chapterUrl': current.chapterId,
        'chapter': current.chapterLabel,
        'pageIndex': current.pageIndex,
        'pageKey': current.pageKey,
        'scroll': current.pageIndex.toDouble(),
        'vertical': state.vertical,
        'rtl': state.rtl,
      });
    }
  }

  Future<void> _checkPreloadNextChapter() async {
    if (state.loadingNextChapter || state.pages.isEmpty) return;

    // Preload when user is within 5 pages of the end of the loaded stream
    final remaining = state.pages.length - 1 - state.currentIndex;
    if (remaining <= 5) {
      await _loadNextChapter();
    }
  }

  Future<void> _loadNextChapter() async {
    if (state.loadingNextChapter || state.pages.isEmpty) return;
    final lastItem = state.pages.last;
    final nextId = await source.getNextChapterId(lastItem.chapterId);

    if (nextId == null || _loadedChapterIds.contains(nextId)) {
      return;
    }

    emit(state.copyWith(loadingNextChapter: true));
    try {
      final nextPages = await source.loadChapter(nextId);
      if (nextPages.isNotEmpty) {
        _loadedChapterIds.add(nextId);
        final combined = List<ReaderPageItem>.from(state.pages)
          ..addAll(nextPages);
        emit(state.copyWith(
          pages: combined,
          loadingNextChapter: false,
          isAllCaughtUp: false,
        ));
      } else {
        emit(state.copyWith(loadingNextChapter: false));
      }
    } catch (_) {
      emit(state.copyWith(loadingNextChapter: false));
    }
  }

  Future<void> _onReachedEnd() async {
    final lastItem = state.pages.isNotEmpty ? state.pages.last : null;
    if (lastItem == null) return;

    final nextId = await source.getNextChapterId(lastItem.chapterId);
    if (nextId == null) {
      emit(state.copyWith(isAllCaughtUp: true));
      _startPollingForNewChapter(lastItem.chapterId);
    } else if (!_loadedChapterIds.contains(nextId)) {
      await _loadNextChapter();
    }
  }

  void _startPollingForNewChapter(String lastChapterId) {
    _pollTimer?.cancel();
    _pollTimer = Timer.periodic(const Duration(seconds: 30), (_) async {
      final nextId = await source.getNextChapterId(lastChapterId);
      if (nextId != null && !_loadedChapterIds.contains(nextId)) {
        _pollTimer?.cancel();
        await _loadNextChapter();
      }
    });
  }

  void setDirection({required bool vertical, required bool rtl}) {
    emit(state.copyWith(vertical: vertical, rtl: rtl));
    library?.update(series.id, {'vertical': vertical, 'rtl': rtl},
        touch: false);
  }

  void setDim(double dim) {
    emit(state.copyWith(dim: dim));
    library?.update(series.id, {'dim': dim}, touch: false);
  }

  @override
  Future<void> close() {
    _debounceSave?.cancel();
    _pollTimer?.cancel();
    return super.close();
  }
}
