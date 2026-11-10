import 'dart:async';

import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../core/url_tools.dart';
import '../data/library_repository.dart';
import '../models/series.dart';
import '../services/anilist_service.dart';

class ReaderState extends Equatable {
  const ReaderState({
    required this.mode,
    required this.dim,
    required this.chapter,
    this.blocked,
  });

  final int mode; // 0 off, 1 dark, 2 warm
  final double dim;
  final String chapter;
  final String? blocked; // last blocked redirect URL (one-shot)

  ReaderState copyWith({
    int? mode,
    double? dim,
    String? chapter,
    String? blocked,
    bool clearBlocked = false,
  }) => ReaderState(
    mode: mode ?? this.mode,
    dim: dim ?? this.dim,
    chapter: chapter ?? this.chapter,
    blocked: clearBlocked ? null : (blocked ?? this.blocked),
  );

  @override
  List<Object?> get props => [mode, dim, chapter, blocked];
}

/// Holds reader settings and decides *when* to write progress.
/// Write policy (battery/quota friendly): at most one write when the page URL
/// settles after a navigation, plus one on leaving/pausing. No scroll listener.
class ReaderCubit extends Cubit<ReaderState> {
  ReaderCubit({
    required Series series,
    required LibraryRepository library,
    required AniListService anilist,
  }) : _series = series,
       _library = library,
       _anilist = anilist,
       _currentUrl = series.url,
       _savedUrl = series.url,
       _savedScroll = series.scroll,
       _allowedRoots = {UrlTools.registrableDomain(series.host)},
       super(
         ReaderState(
           mode: series.mode,
           dim: series.dim,
           chapter: series.chapter,
         ),
       );

  Series _series;
  final LibraryRepository _library;
  final AniListService _anilist;
  final Set<String> _allowedRoots;
  String _currentUrl;
  String _savedUrl;
  double _savedScroll;
  Timer? _debounce;

  String get currentUrl => _currentUrl;

  // ---- navigation guard -------------------------------------------------
  bool isAllowedHost(String host) =>
      _allowedRoots.contains(UrlTools.registrableDomain(host));

  void allowHost(String host) =>
      _allowedRoots.add(UrlTools.registrableDomain(host));

  void reportBlocked(String url) {
    if (!isClosed) emit(state.copyWith(blocked: url));
  }

  void clearBlocked() {
    if (!isClosed) emit(state.copyWith(clearBlocked: true));
  }

  // ---- progress ---------------------------------------------------------
  void onUrl(String url) {
    if (isClosed) return;
    _currentUrl = url;
    final label = UrlTools.chapterLabel(url);
    if (label != null && label != state.chapter) {
      emit(state.copyWith(chapter: label));
    }
    _debounce?.cancel();
    if (UrlTools.normalize(url) == UrlTools.normalize(_savedUrl)) return;
    // Wait for redirects to settle before writing.
    _debounce = Timer(const Duration(milliseconds: 1500), () {
      _savedUrl = _currentUrl;
      _savedScroll = 0;
      _library.update(_series.id, {
        'url': _currentUrl,
        'chapter': state.chapter,
        'scroll': 0.0,
      });
    });
  }

  /// Call when leaving the reader or when the app goes to background.
  Future<void> flush({required double scroll}) async {
    _debounce?.cancel();
    _savedUrl = _currentUrl;
    _savedScroll = scroll;
    _library.update(_series.id, {
      'url': _currentUrl,
      'chapter': state.chapter,
      'scroll': scroll,
    });
  }

  double get savedScroll => _savedScroll;

  Future<void> onPageTitle(String raw) async {
    if (!_series.titleAuto) return;
    final title = UrlTools.cleanTitle(raw);
    if (title.length < 2) return;
    _series = _series.copyWith(title: title, titleAuto: false);
    _library.update(_series.id, {
      'title': title,
      'titleAuto': false,
    }, touch: false);
    final cover = await _anilist.findCover(title);
    if (cover != null) {
      _library.update(_series.id, {'coverUrl': cover}, touch: false);
    }
  }

  void setChapter(String label) {
    final t = label.trim();
    if (isClosed) return;
    emit(state.copyWith(chapter: t));
    _library.update(_series.id, {'chapter': t}, touch: false);
  }

  String? stepUrl(int delta) => UrlTools.stepChapter(_currentUrl, delta);

  // ---- reading mode -----------------------------------------------------
  void setMode(int mode) {
    emit(state.copyWith(mode: mode));
    _library.update(_series.id, {'mode': mode}, touch: false);
  }

  void setDim(double dim) => emit(state.copyWith(dim: dim));

  void commitDim() =>
      _library.update(_series.id, {'dim': state.dim}, touch: false);

  @override
  Future<void> close() {
    _debounce?.cancel();
    return super.close();
  }
}
