import 'dart:async';
import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../core/url_tools.dart';
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
    this.needsVerification = false,
    this.verificationUrl,
    this.nextVerificationUrl,
    this.checkingForNew = false,
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
  final bool needsVerification;
  final String? verificationUrl;

  /// Set when the NEXT chapter (not the current one) needs Cloudflare
  /// verification; the end-of-stream card offers a one-tap verify.
  final String? nextVerificationUrl;
  final bool checkingForNew;
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
    bool? needsVerification,
    String? verificationUrl,
    bool clearVerificationUrl = false,
    String? nextVerificationUrl,
    bool clearNextVerificationUrl = false,
    bool? checkingForNew,
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
        needsVerification: needsVerification ?? this.needsVerification,
        verificationUrl: clearVerificationUrl
            ? null
            : (verificationUrl ?? this.verificationUrl),
        nextVerificationUrl: clearNextVerificationUrl
            ? null
            : (nextVerificationUrl ?? this.nextVerificationUrl),
        checkingForNew: checkingForNew ?? this.checkingForNew,
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
        needsVerification,
        verificationUrl,
        nextVerificationUrl,
        checkingForNew,
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

      // Update series cover thumbnail if missing
      final cover = source.lastCoverUrl ??
          (initialPages.isNotEmpty ? initialPages.first.url : null);
      if (cover != null &&
          cover.isNotEmpty &&
          (series.coverUrl == null || series.coverUrl!.isEmpty)) {
        library?.update(series.id, {'coverUrl': cover}, touch: false);
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
        needsVerification: false,
        clearVerificationUrl: true,
        availableChapters: catalogue,
      ));

      _triggerLocalSave();

      // Check if we need to pre-fetch the next chapter
      await _checkPreloadNextChapter();
    } on VerificationRequiredException catch (v) {
      emit(state.copyWith(
        loading: false,
        needsVerification: true,
        verificationUrl: v.url,
      ));
    } catch (e) {
      emit(state.copyWith(
        loading: false,
        error: 'Failed to load chapter: $e',
      ));
    }
  }

  void retry() {
    emit(state.copyWith(
      loading: true,
      clearError: true,
      needsVerification: false,
      clearVerificationUrl: true,
    ));
    init();
  }

  Future<void> onVerificationCompleted({
    List<String>? verifiedPages,
    String? chapterUrl,
  }) async {
    final chapterToLoad = chapterUrl ??
        startChapterId ??
        series.chapterUrl ??
        series.mdChapterId ??
        series.url;

    if (verifiedPages != null && verifiedPages.length >= 2) {
      final label = UrlTools.chapterLabel(chapterToLoad) ?? '';
      final count = verifiedPages.length;
      final pages = List.generate(
        count,
        (i) => ReaderPageItem(
          url: verifiedPages[i],
          chapterId: chapterToLoad,
          chapterLabel: label,
          pageIndex: i,
          totalInChapter: count,
          referer: chapterToLoad,
        ),
      );

      _loadedChapterIds.add(chapterToLoad);

      emit(state.copyWith(
        pages: pages,
        currentIndex: 0,
        loading: false,
        needsVerification: false,
        clearVerificationUrl: true,
        clearError: true,
      ));
      _triggerLocalSave();
      return;
    }

    retry();
  }

  Future<void> jumpToChapter(String chapterId, {int pageIndex = 0}) async {
    emit(state.copyWith(
      loading: true,
      clearError: true,
      needsVerification: false,
      clearVerificationUrl: true,
    ));
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

      // Update series cover thumbnail if missing
      final cover = source.lastCoverUrl ??
          (pages.isNotEmpty ? pages.first.url : null);
      if (cover != null &&
          cover.isNotEmpty &&
          (series.coverUrl == null || series.coverUrl!.isEmpty)) {
        library?.update(series.id, {'coverUrl': cover}, touch: false);
      }

      emit(state.copyWith(
        pages: pages,
        currentIndex: target,
        loading: false,
        needsVerification: false,
        clearVerificationUrl: true,
        availableChapters:
            catalogue.isNotEmpty ? catalogue : state.availableChapters,
      ));
      _triggerLocalSave();
      await _checkPreloadNextChapter();
    } on VerificationRequiredException catch (v) {
      emit(state.copyWith(
        loading: false,
        needsVerification: true,
        verificationUrl: v.url,
      ));
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

  bool _loadingNext = false;
  int _pollAttempts = 0;
  DateTime _lastAutoCheck = DateTime.fromMillisecondsSinceEpoch(0);

  Future<void> _checkPreloadNextChapter() async {
    if (_loadingNext || state.loadingNextChapter || state.pages.isEmpty) return;
    // Don't hammer a chapter that is waiting for the user to verify it.
    if (state.nextVerificationUrl != null) return;

    // Preload when user is within 5 pages of the end of the loaded stream
    final remaining = state.pages.length - 1 - state.currentIndex;
    if (remaining <= 5) {
      await _loadNextChapter();
    }
  }

  Future<void> _loadNextChapter({String? knownNextId}) async {
    if (_loadingNext || state.pages.isEmpty) return;
    _loadingNext = true;
    try {
      final lastItem = state.pages.last;
      final nextId =
          knownNextId ?? await source.getNextChapterId(lastItem.chapterId);

      if (nextId == null || _loadedChapterIds.contains(nextId)) {
        return;
      }

      emit(state.copyWith(loadingNextChapter: true));
      try {
        final nextPages = await source.loadChapter(nextId);
        if (nextPages.isNotEmpty) {
          _loadedChapterIds.add(nextId);
          _pollTimer?.cancel();
          final combined = List<ReaderPageItem>.from(state.pages)
            ..addAll(nextPages);
          emit(state.copyWith(
            pages: combined,
            loadingNextChapter: false,
            isAllCaughtUp: false,
            clearNextVerificationUrl: true,
          ));
        } else {
          // The "next" link led nowhere: we're on the newest chapter.
          emit(state.copyWith(loadingNextChapter: false, isAllCaughtUp: true));
          _startPollingForNewChapter(lastItem.chapterId);
        }
      } on VerificationRequiredException catch (v) {
        // Next chapter is protected. Keep reading what we have and offer a
        // one-tap verify on the last page instead of failing silently.
        emit(state.copyWith(
          loadingNextChapter: false,
          isAllCaughtUp: true,
          nextVerificationUrl: v.url,
        ));
      } catch (_) {
        emit(state.copyWith(loadingNextChapter: false));
      }
    } finally {
      _loadingNext = false;
    }
  }

  Future<void> _onReachedEnd() async {
    final lastItem = state.pages.isNotEmpty ? state.pages.last : null;
    if (lastItem == null) return;
    if (state.nextVerificationUrl != null) return;

    final nextId = await source.getNextChapterId(lastItem.chapterId);
    if (nextId == null) {
      emit(state.copyWith(isAllCaughtUp: true));
      // Ask the live site right away (throttled) instead of waiting minutes.
      final now = DateTime.now();
      if (now.difference(_lastAutoCheck).inSeconds >= 120) {
        _lastAutoCheck = now;
        unawaited(checkForNewChapters(silent: true));
      }
      _startPollingForNewChapter(lastItem.chapterId);
    } else if (!_loadedChapterIds.contains(nextId)) {
      await _loadNextChapter();
    }
  }

  /// Re-checks the live site for a chapter newer than the last one loaded.
  /// Used by the end-of-stream card ("Check for new chapters") and by the
  /// background poll. When [silent] the user isn't asked to verify.
  Future<void> checkForNewChapters({bool silent = false}) async {
    if (state.pages.isEmpty || state.checkingForNew || _loadingNext) return;
    final src = source;
    if (src is! RefreshableChapterSource) return;

    final lastId = state.pages.last.chapterId;
    emit(state.copyWith(checkingForNew: true));
    try {
      final nextId = await src.refreshNextChapterId(lastId);
      emit(state.copyWith(checkingForNew: false));
      if (nextId != null && !_loadedChapterIds.contains(nextId)) {
        await _loadNextChapter(knownNextId: nextId);
      }
    } on VerificationRequiredException catch (v) {
      emit(state.copyWith(
        checkingForNew: false,
        nextVerificationUrl: silent ? null : v.url,
      ));
    } catch (_) {
      emit(state.copyWith(checkingForNew: false));
    }
  }

  /// Called after the user passed verification (the verified page is already
  /// in the scrape cache, so nothing is asked twice).
  Future<void> onNextVerified() async {
    final verifiedUrl = state.nextVerificationUrl;
    emit(state.copyWith(clearNextVerificationUrl: true));
    _pollAttempts = 0;
    if (state.pages.isEmpty) return;

    final lastId = state.pages.last.chapterId;
    final src = source;
    final verifiedWasCurrentLast = verifiedUrl != null &&
        UrlTools.normalize(verifiedUrl) == UrlTools.normalize(lastId);

    if (verifiedWasCurrentLast && src is RefreshableChapterSource) {
      // The live "is there a new chapter?" check was what got blocked.
      await checkForNewChapters();
    } else {
      // The next chapter itself was blocked; it is cached now.
      await _loadNextChapter();
    }
  }

  void _startPollingForNewChapter(String lastChapterId) {
    if (_pollTimer?.isActive ?? false) return;
    _pollAttempts = 0;
    // Gentle: every 3 minutes, at most 10 times per session at the end.
    _pollTimer = Timer.periodic(const Duration(minutes: 3), (t) async {
      _pollAttempts++;
      if (_pollAttempts > 10) {
        t.cancel();
        return;
      }
      final src = source;
      if (src is RefreshableChapterSource) {
        await checkForNewChapters(silent: true);
        return;
      }
      final nextId = await source.getNextChapterId(lastChapterId);
      if (nextId != null && !_loadedChapterIds.contains(nextId)) {
        t.cancel();
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
