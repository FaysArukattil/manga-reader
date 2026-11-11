import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../blocs/unified_reader_cubit.dart';
import '../data/library_repository.dart';
import '../models/series.dart';
import '../services/local_progress_store.dart';
import '../services/page_cache.dart';
import '../services/reader/chapter_source.dart';
import '../services/reader/reader_audio.dart';
import '../services/scrape/cf_session.dart';
import '../services/scrape/scrape_service.dart';
import 'components/physics_page_turn.dart';
import 'components/reading_loader.dart';
import 'cf_verification_sheet.dart';

/// Pure content native book reader:
/// - 100% full-bleed pages on black.
/// - Zero ads, zero website chrome, zero intrusive buttons.
/// - Swiping is the only interaction (3D flippable pages or continuous vertical webtoon).
/// - Seamless chapter-to-chapter streaming without needing to tap "Next".
/// - Minimal hidden long-press settings sheet for reading direction & dimmer.
class UnifiedReaderPage extends StatefulWidget {
  const UnifiedReaderPage({
    super.key,
    required this.series,
    required this.source,
    this.startChapterId,
    this.startPageIndex = 0,
    this.startPageKey,
  });

  final Series series;
  final ChapterSource source;
  final String? startChapterId;
  final int startPageIndex;
  final String? startPageKey;

  static Future<void> openSeries(BuildContext context, Series series) async {
    final scrapeService = context.read<ScrapeService>();
    final localProgress = await LocalProgressStore.get(series.id);

    final chapterId = (localProgress?.chapterUrl.isNotEmpty == true)
        ? localProgress!.chapterUrl
        : (series.chapterUrl ?? series.url);
    final pageIndex = localProgress?.pageIndex ?? series.pageIndex;
    final pageKey = localProgress?.pageKey ?? series.pageKey;

    final source = ScrapedSource(scrapeService: scrapeService);

    if (!context.mounted) return;
    return open(
      context,
      series: series,
      source: source,
      startChapterId: chapterId,
      startPageIndex: pageIndex,
      startPageKey: pageKey,
    );
  }

  static Future<void> open(
    BuildContext context, {
    required Series series,
    required ChapterSource source,
    String? startChapterId,
    int startPageIndex = 0,
    String? startPageKey,
  }) {
    return Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => UnifiedReaderPage(
          series: series,
          source: source,
          startChapterId: startChapterId,
          startPageIndex: startPageIndex,
          startPageKey: startPageKey,
        ),
      ),
    );
  }

  @override
  State<UnifiedReaderPage> createState() => _UnifiedReaderPageState();
}

class _UnifiedReaderPageState extends State<UnifiedReaderPage>
    with WidgetsBindingObserver {
  late final UnifiedReaderCubit _cubit;
  PageController? _pageController;
  final PhysicsPageTurnController _turnController = PhysicsPageTurnController();
  bool _leaving = false;
  bool _showSettingsHint = true;
  Timer? _hintTimer;

  @override
  void initState() {
    super.initState();
    _cubit = UnifiedReaderCubit(
      source: widget.source,
      series: widget.series,
      library: context.read<LibraryRepository>(),
      startChapterId: widget.startChapterId,
      startPageIndex: widget.startPageIndex,
      startPageKey: widget.startPageKey,
    )..init();

    WidgetsBinding.instance.addObserver(this);
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);

    _hintTimer = Timer(const Duration(milliseconds: 2500), () {
      if (mounted) setState(() => _showSettingsHint = false);
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    _hintTimer?.cancel();
    _pageController?.dispose();
    _turnController.dispose();
    _cubit.close();
    super.dispose();
  }

  void _jumpTo(int targetIdx) {
    if (targetIdx < 0 || targetIdx >= _cubit.state.pages.length) return;
    if (_pageController?.hasClients ?? false) {
      _pageController!.jumpToPage(targetIdx);
    }
    _turnController.jumpToPage(targetIdx);
    _cubit.onPageChanged(targetIdx);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.inactive ||
        state == AppLifecycleState.detached) {
      _cubit.flush();
    }
  }

  Future<void> _leave() async {
    if (_leaving) return;
    _leaving = true;
    await _cubit.flush();
    if (mounted) Navigator.of(context).pop();
  }

  Future<void> _verifyNext(String url) async {
    final scrape = context.read<ScrapeService>();
    final result = await Navigator.of(context).push<dynamic>(
      MaterialPageRoute(
        builder: (ctx) => CfVerificationSheet(
          url: url,
          seriesTitle: widget.series.title,
          isFullScreen: true,
        ),
      ),
    );
    if (result is CfVerifiedPage && result.pages.length >= 2) {
      await scrape.cacheVerified(
        result.url,
        pages: result.pages,
        title: result.title,
        nextUrl: result.nextUrl,
        prevUrl: result.prevUrl,
        chapters: result.chapters,
      );
      if (mounted) _cubit.onNextVerified();
    } else if (result is CfVerifiedPage) {
      if (mounted) _cubit.onNextVerified();
    }
  }

  void _showHiddenSettings() {
    _hintTimer?.cancel();
    if (_showSettingsHint && mounted) {
      setState(() => _showSettingsHint = false);
    }
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF141416),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      showDragHandle: true,
      builder: (_) => BlocProvider.value(
        value: _cubit,
        child: SafeArea(
          child: DraggableScrollableSheet(
            expand: false,
            initialChildSize: 0.92,
            minChildSize: 0.4,
            maxChildSize: 0.95,
            builder: (context, scrollController) =>
                BlocBuilder<UnifiedReaderCubit, UnifiedReaderState>(
              builder: (context, state) => ListView(
                controller: scrollController,
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
                children: [
                  // Title & Current chapter
                  Text(
                    widget.series.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  if (state.currentChapterLabel.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text(
                      state.currentChapterLabel,
                      style: const TextStyle(
                        color: Color(0xFF00B96B),
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],

                  // Quick Page Jump
                  if (state.totalPagesInChapter > 1) ...[
                    const SizedBox(height: 18),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text(
                          'Jump to Page',
                          style: TextStyle(
                            color: Colors.white70,
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 10, vertical: 3),
                          decoration: BoxDecoration(
                            color:
                                const Color(0xFF00B96B).withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Text(
                            'Page ${state.currentPageInChapter} / ${state.totalPagesInChapter}',
                            style: const TextStyle(
                              color: Color(0xFF00B96B),
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ],
                    ),
                    Slider(
                      value: state.currentPageInChapter
                          .clamp(1, state.totalPagesInChapter)
                          .toDouble(),
                      min: 1,
                      max: state.totalPagesInChapter.toDouble(),
                      divisions: state.totalPagesInChapter > 1
                          ? state.totalPagesInChapter - 1
                          : null,
                      activeColor: const Color(0xFF00B96B),
                      inactiveColor: Colors.white24,
                      onChanged: (val) {
                        final pageNum = val.round();
                        final offsetInChapter = pageNum - 1;
                        // Find the index in loaded pages matching this chapter & page offset
                        final targetIdx = state.pages.indexWhere(
                          (p) =>
                              p.chapterId == state.currentPageItem?.chapterId &&
                              p.pageIndex == offsetInChapter,
                        );
                        if (targetIdx >= 0) {
                          _jumpTo(targetIdx);
                        }
                      },
                    ),
                  ],

                  // Chapter Catalogue
                  if (state.availableChapters.isNotEmpty) ...[
                    const SizedBox(height: 14),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text(
                          'Chapter Catalogue',
                          style: TextStyle(
                            color: Colors.white70,
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        Text(
                          '${state.availableChapters.length} available',
                          style: const TextStyle(
                            color: Colors.white38,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    SizedBox(
                      height: 40,
                      child: ListView.separated(
                        scrollDirection: Axis.horizontal,
                        itemCount: state.availableChapters.length,
                        separatorBuilder: (_, __) => const SizedBox(width: 8),
                        itemBuilder: (context, i) {
                          final ch = state.availableChapters[i];
                          final isCurrent =
                              ch.label == state.currentChapterLabel ||
                                  ch.url == state.currentPageItem?.chapterId;
                          return ChoiceChip(
                            label: Text(ch.label),
                            selected: isCurrent,
                            selectedColor:
                                const Color(0xFF00B96B).withValues(alpha: 0.25),
                            side: BorderSide(
                              color: isCurrent
                                  ? const Color(0xFF00B96B)
                                  : Colors.white12,
                            ),
                            labelStyle: TextStyle(
                              color: isCurrent
                                  ? const Color(0xFF00B96B)
                                  : Colors.white70,
                              fontWeight: isCurrent
                                  ? FontWeight.w700
                                  : FontWeight.normal,
                              fontSize: 12,
                            ),
                            onSelected: (_) {
                              Navigator.pop(context);
                              _cubit.jumpToChapter(ch.url);
                            },
                          );
                        },
                      ),
                    ),
                  ],

                  // Reading Direction
                  const SizedBox(height: 20),
                  const Text(
                    'Reading Direction & Gesture',
                    style: TextStyle(
                      color: Colors.white70,
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Column(
                    children: [
                      _DirectionTile(
                        icon: Icons.auto_stories_rounded,
                        title: 'Standard Book',
                        subtitle:
                            'Swipe Left to Next Page (Right to Left turn)',
                        selected: !state.vertical && !state.rtl,
                        onTap: () {
                          _cubit.setDirection(vertical: false, rtl: false);
                        },
                      ),
                      const SizedBox(height: 6),
                      _DirectionTile(
                        icon: Icons.menu_book_rounded,
                        title: 'Japanese Manga',
                        subtitle:
                            'Swipe Right to Next Page (Left to Right turn)',
                        selected: !state.vertical && state.rtl,
                        onTap: () {
                          _cubit.setDirection(vertical: false, rtl: true);
                        },
                      ),
                      const SizedBox(height: 6),
                      _DirectionTile(
                        icon: Icons.swap_vert_rounded,
                        title: 'Vertical Reel (Webtoon)',
                        subtitle: 'Continuous scroll from top to bottom',
                        selected: state.vertical,
                        onTap: () {
                          _cubit.setDirection(vertical: true, rtl: false);
                        },
                      ),
                    ],
                  ),

                  // Page Turn Animation & Sound
                  const SizedBox(height: 18),
                  const Text(
                    'Page Turn Experience',
                    style: TextStyle(
                      color: Colors.white70,
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 6),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text(
                      '3D Page Turn Animation',
                      style: TextStyle(color: Colors.white, fontSize: 14),
                    ),
                    subtitle: const Text(
                      'Realistic page curl, curve & fold shadow tracking finger',
                      style: TextStyle(color: Colors.white54, fontSize: 12),
                    ),
                    value: state.pageFlipEffect,
                    activeTrackColor: const Color(0xFF00B96B),
                    onChanged: _cubit.setPageFlipEffect,
                  ),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text(
                      'Page Turn Sound',
                      style: TextStyle(color: Colors.white, fontSize: 14),
                    ),
                    subtitle: const Text(
                      'Subtle physical paper flip sound on page turn',
                      style: TextStyle(color: Colors.white54, fontSize: 12),
                    ),
                    value: state.soundEffect,
                    activeTrackColor: const Color(0xFF00B96B),
                    onChanged: _cubit.setSoundEffect,
                  ),

                  // Dimmer
                  const SizedBox(height: 12),
                  const Text(
                    'Brightness Dimmer',
                    style: TextStyle(
                      color: Colors.white70,
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  Row(
                    children: [
                      const Icon(
                        Icons.brightness_low,
                        size: 20,
                        color: Colors.white54,
                      ),
                      Expanded(
                        child: Slider(
                          value: state.dim,
                          min: 0,
                          max: 0.7,
                          activeColor: const Color(0xFF00B96B),
                          inactiveColor: Colors.white24,
                          onChanged: _cubit.setDim,
                        ),
                      ),
                      const Icon(
                        Icons.brightness_2,
                        size: 18,
                        color: Colors.white54,
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _leave();
      },
      child: BlocProvider.value(
        value: _cubit,
        child: Scaffold(
          backgroundColor: Colors.black,
          body: BlocConsumer<UnifiedReaderCubit, UnifiedReaderState>(
            listenWhen: (prev, curr) =>
                prev.currentIndex != curr.currentIndex ||
                prev.pages.length != curr.pages.length,
            listener: (context, state) {
              if (_pageController?.hasClients ?? false) {
                if (_pageController!.page?.round() != state.currentIndex) {
                  _pageController!.jumpToPage(state.currentIndex);
                }
              }
              if (_turnController.currentPage != state.currentIndex) {
                _turnController.jumpToPage(state.currentIndex);
              }
            },
            builder: (context, state) {
              if (state.loading) {
                return _LoadingBookPlaceholder(series: widget.series);
              }

              if (state.needsVerification) {
                final targetUrl = state.verificationUrl ?? widget.series.url;
                return _VerificationRequiredView(
                  url: targetUrl,
                  seriesTitle: widget.series.title,
                  onPagesResolved: (pages) {
                    _cubit.onVerificationCompleted(
                      verifiedPages: pages,
                      chapterUrl: targetUrl,
                    );
                  },
                  onVerified: () => _cubit.retry(),
                  onCancel: _leave,
                );
              }

              if (state.error != null && state.pages.isEmpty) {
                return Center(
                  child: Padding(
                    padding: const EdgeInsets.all(32),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(
                          Icons.menu_book_rounded,
                          color: Colors.white30,
                          size: 48,
                        ),
                        const SizedBox(height: 16),
                        Text(
                          state.error!,
                          textAlign: TextAlign.center,
                          style: const TextStyle(color: Colors.white70),
                        ),
                        const SizedBox(height: 16),
                        OutlinedButton(
                          onPressed: () => _cubit.init(),
                          child: const Text('Try Again'),
                        ),
                      ],
                    ),
                  ),
                );
              }

              // Initialize page controller once initial index is resolved
              _pageController ??= PageController(
                initialPage: state.currentIndex,
              );

              return Stack(
                children: [
                  // Full-bleed flippable book or continuous stream
                  Positioned.fill(
                    child: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onLongPress: _showHiddenSettings,
                      child: _StreamPager(
                        pages: state.pages,
                        controller: _pageController!,
                        turnController: _turnController,
                        initialPage: state.currentIndex,
                        vertical: state.vertical,
                        rtl: state.rtl,
                        pageFlipEffect: state.pageFlipEffect,
                        soundEffect: state.soundEffect,
                        isAllCaughtUp: state.isAllCaughtUp,
                        loadingNextChapter: state.loadingNextChapter,
                        series: widget.series,
                        caughtUp: _CaughtUpCard(
                          checking: state.checkingForNew,
                          needsVerification: state.nextVerificationUrl != null,
                          onCheck: () => _cubit.checkForNewChapters(),
                          onVerify: () =>
                              _verifyNext(state.nextVerificationUrl!),
                        ),
                        onPageChanged: _cubit.onPageChanged,
                        onCenterTap: _showHiddenSettings,
                      ),
                    ),
                  ),

                  // Dimmer overlay
                  if (state.dim > 0)
                    Positioned.fill(
                      child: IgnorePointer(
                        child: ColoredBox(
                          color: Color.fromRGBO(0, 0, 0, state.dim),
                        ),
                      ),
                    ),

                  // Subtle discreet page pill in the corner (barely visible)
                  Positioned(
                    bottom: 12,
                    right: 16,
                    child: IgnorePointer(
                      child: AnimatedOpacity(
                        opacity: 0.6,
                        duration: const Duration(milliseconds: 300),
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 3,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.black.withValues(alpha: 0.7),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Text(
                            '${state.currentPageInChapter} / ${state.totalPagesInChapter}',
                            style: const TextStyle(
                              color: Colors.white70,
                              fontSize: 11,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),

                  // Floating press-and-hold tutorial banner (translucent, subtle, non-intrusive)
                  if (_showSettingsHint)
                    Positioned(
                      top: MediaQuery.paddingOf(context).top + 12,
                      left: 20,
                      right: 20,
                      child: Center(
                        child: GestureDetector(
                          onTap: () {
                            setState(() => _showSettingsHint = false);
                            _showHiddenSettings();
                          },
                          child: AnimatedOpacity(
                            opacity: _showSettingsHint ? 1.0 : 0.0,
                            duration: const Duration(milliseconds: 350),
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(20),
                              child: BackdropFilter(
                                filter:
                                    ui.ImageFilter.blur(sigmaX: 8, sigmaY: 8),
                                child: Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 12,
                                    vertical: 5.5,
                                  ),
                                  decoration: BoxDecoration(
                                    color: Colors.black.withValues(alpha: 0.32),
                                    borderRadius: BorderRadius.circular(20),
                                    border: Border.all(
                                      color:
                                          Colors.white.withValues(alpha: 0.12),
                                      width: 0.5,
                                    ),
                                    boxShadow: [
                                      BoxShadow(
                                        color:
                                            Colors.black.withValues(alpha: 0.2),
                                        blurRadius: 10,
                                        offset: const Offset(0, 2),
                                      ),
                                    ],
                                  ),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Icon(
                                        Icons.touch_app_rounded,
                                        color: const Color(0xFF00B96B)
                                            .withValues(alpha: 0.8),
                                        size: 13,
                                      ),
                                      const SizedBox(width: 6),
                                      Text(
                                        'Press & hold for settings',
                                        style: TextStyle(
                                          color: Colors.white
                                              .withValues(alpha: 0.75),
                                          fontSize: 11,
                                          fontWeight: FontWeight.w500,
                                          letterSpacing: 0.1,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}

// ------------------------------------------------------------- direction tile

class _DirectionTile extends StatelessWidget {
  const _DirectionTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.selected,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: selected
              ? const Color(0xFF00B96B).withValues(alpha: 0.12)
              : Colors.white.withValues(alpha: 0.04),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: selected ? const Color(0xFF00B96B) : Colors.white10,
            width: selected ? 1.2 : 0.6,
          ),
        ),
        child: Row(
          children: [
            Icon(
              icon,
              size: 22,
              color: selected ? const Color(0xFF00B96B) : Colors.white60,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      color: selected ? Colors.white : Colors.white70,
                      fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                      fontSize: 14,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: TextStyle(
                      color:
                          selected ? const Color(0xFF00B96B) : Colors.white38,
                      fontSize: 11,
                    ),
                  ),
                ],
              ),
            ),
            if (selected)
              const Icon(
                Icons.check_circle_rounded,
                size: 18,
                color: Color(0xFF00B96B),
              ),
          ],
        ),
      ),
    );
  }
}

// ------------------------------------------------------------- stream pager

class _StreamPager extends StatefulWidget {
  const _StreamPager({
    required this.pages,
    required this.controller,
    required this.turnController,
    required this.initialPage,
    required this.vertical,
    required this.rtl,
    required this.pageFlipEffect,
    required this.soundEffect,
    required this.isAllCaughtUp,
    required this.loadingNextChapter,
    required this.series,
    required this.caughtUp,
    required this.onPageChanged,
    required this.onCenterTap,
  });

  final List<ReaderPageItem> pages;
  final PageController controller;
  final PhysicsPageTurnController turnController;
  final int initialPage;
  final bool vertical;
  final bool rtl;
  final bool pageFlipEffect;
  final bool soundEffect;
  final bool isAllCaughtUp;
  final bool loadingNextChapter;
  final Series series;
  final Widget caughtUp;
  final ValueChanged<int> onPageChanged;
  final VoidCallback onCenterTap;

  @override
  State<_StreamPager> createState() => _StreamPagerState();
}

class _StreamPagerState extends State<_StreamPager> {
  final ScrollController _verticalScrollController = ScrollController();
  int get _count =>
      widget.pages.length +
      ((widget.isAllCaughtUp || widget.loadingNextChapter) ? 1 : 0);
  int? _lastSoundPage;

  @override
  void initState() {
    super.initState();
    _lastSoundPage = widget.initialPage;
    widget.controller.addListener(_syncFromPageController);
    _verticalScrollController.addListener(_onVerticalScroll);
    ReaderAudio.instance.init();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _prefetch(widget.initialPage);
        if (widget.vertical && widget.initialPage > 0 && widget.pages.isNotEmpty) {
          _scrollToIndex(widget.initialPage);
        }
      }
    });
  }

  @override
  void didUpdateWidget(_StreamPager oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller.removeListener(_syncFromPageController);
      widget.controller.addListener(_syncFromPageController);
    }
    // If next chapter pages arrived while reader was on the loading card
    if (widget.pages.length > oldWidget.pages.length) {
      final currentPos = widget.vertical
          ? (widget.controller.hasClients
              ? widget.controller.page?.round()
              : null)
          : widget.turnController.currentPage;
      if (currentPos != null && currentPos >= oldWidget.pages.length) {
        widget.onPageChanged(oldWidget.pages.length);
      }
    }
  }

  @override
  void dispose() {
    widget.controller.removeListener(_syncFromPageController);
    _verticalScrollController.removeListener(_onVerticalScroll);
    _verticalScrollController.dispose();
    super.dispose();
  }

  void _onVerticalScroll() {
    if (!_verticalScrollController.hasClients || widget.pages.isEmpty) return;
    final pos = _verticalScrollController.position;
    final max = pos.maxScrollExtent;
    if (max > 0) {
      final frac = (pos.pixels / max).clamp(0.0, 1.0);
      final page = (frac * (widget.pages.length - 1)).round();
      if (page != _lastSoundPage) {
        _lastSoundPage = page;
        widget.onPageChanged(page);
      }
    }
    if (pos.pixels >= max - 300) {
      widget.onPageChanged(widget.pages.length - 1);
    }
  }

  void _scrollToIndex(int idx) {
    if (_verticalScrollController.hasClients && widget.pages.isNotEmpty) {
      final max = _verticalScrollController.position.maxScrollExtent;
      final target = (idx / widget.pages.length) * max;
      _verticalScrollController.jumpTo(target.clamp(0.0, max));
    }
  }

  void _syncFromPageController() {
    if (widget.controller.hasClients && widget.controller.page != null) {
      final target = widget.controller.page!.round();
      if (widget.vertical) {
        _scrollToIndex(target);
      } else if (widget.turnController.currentPage != target) {
        widget.turnController.jumpToPage(target);
      }
    }
  }

  void _onPageTurned(int p) {
    if (p != _lastSoundPage) {
      _lastSoundPage = p;
      ReaderAudio.instance.playPageTurn(soundEnabled: widget.soundEffect);
    }
    widget.onPageChanged(math.min(p, widget.pages.length - 1));
    _prefetch(p);
  }

  void _prefetch(int page) {
    for (var i = 1; i <= 4; i++) {
      final n = page + i;
      if (n < widget.pages.length) {
        final item = widget.pages[n];
        for (final u in item.allUrls) {
          precacheImage(
            CachedNetworkImageProvider(
              u,
              cacheKey: PageCache.keyFor(u),
              cacheManager: PageCache.instance,
              headers: CfSession.imageHeaders(u, item.referer),
            ),
            context,
          );
        }
      }
    }
  }

  bool _isAnimatingPage = false;
  void _go(int delta) {
    if (_isAnimatingPage) return;
    if (widget.vertical) {
      if (_verticalScrollController.hasClients) {
        final pos = _verticalScrollController.position;
        final target = (_verticalScrollController.offset +
                delta * (pos.viewportDimension * 0.75))
            .clamp(0.0, pos.maxScrollExtent);
        _isAnimatingPage = true;
        try {
          HapticFeedback.lightImpact();
        } catch (_) {}
        _verticalScrollController
            .animateTo(
              target,
              duration: const Duration(milliseconds: 250),
              curve: Curves.easeOutCubic,
            )
            .then((_) => _isAnimatingPage = false);
      }
    } else {
      if (delta > 0) {
        widget.turnController.nextPage();
      } else {
        widget.turnController.prevPage();
      }
    }
  }

  Widget _buildPageItem(BuildContext context, int i) {
    if (i == widget.pages.length) {
      if (widget.loadingNextChapter) {
        return _NextChapterLoadingCard(
          series: widget.series,
          vertical: widget.vertical,
        );
      }
      return widget.caughtUp;
    }

    final item = widget.pages[i];
    final bool isFirstInChapter =
        i > 0 && widget.pages[i - 1].chapterId != item.chapterId;

    return Stack(
      fit: StackFit.expand,
      children: [
        Positioned.fill(
          child: _PageImage(
            item: item,
            isVertical: widget.vertical,
            onNextPage: () => _go(1),
            onPrevPage: () => _go(-1),
          ),
        ),
        // Chapter seam marker / popup indicator (positioned below camera/notch)
        if (isFirstInChapter && item.chapterLabel.isNotEmpty)
          Positioned(
            top: (MediaQuery.paddingOf(context).top > 0
                    ? MediaQuery.paddingOf(context).top
                    : 24.0) +
                16.0,
            left: 0,
            right: 0,
            child: Center(
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 7,
                ),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.85),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: Colors.white.withValues(alpha: 0.15),
                    width: 0.8,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.5),
                      blurRadius: 10,
                      offset: const Offset(0, 3),
                    ),
                  ],
                ),
                child: Text(
                  item.chapterLabel,
                  style: const TextStyle(
                    color: Color(0xFF00FFA3),
                    fontSize: 12.5,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.2,
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    if (widget.vertical) {
      return GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapUp: (d) {
          final size = context.size;
          if (size == null) return;
          final frac = d.localPosition.dy / size.height;
          if (frac < 0.22) {
            _go(-1);
          } else if (frac > 0.78) {
            _go(1);
          } else {
            widget.onCenterTap();
          }
        },
        child: ListView.builder(
          controller: _verticalScrollController,
          padding: EdgeInsets.zero,
          physics: const BouncingScrollPhysics(),
          itemCount: _count,
          itemBuilder: (context, i) {
            if (i == widget.pages.length) {
              if (widget.loadingNextChapter) {
                return _NextChapterLoadingCard(
                  series: widget.series,
                  vertical: true,
                );
              }
              return widget.caughtUp;
            }

            final item = widget.pages[i];
            final bool isFirstInChapter =
                i > 0 && widget.pages[i - 1].chapterId != item.chapterId;

            return Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (isFirstInChapter && item.chapterLabel.isNotEmpty)
                  Container(
                    margin: const EdgeInsets.symmetric(vertical: 20),
                    alignment: Alignment.center,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 7,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.85),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(
                          color: Colors.white.withValues(alpha: 0.15),
                          width: 0.8,
                        ),
                      ),
                      child: Text(
                        item.chapterLabel,
                        style: const TextStyle(
                          color: Color(0xFF00FFA3),
                          fontSize: 12.5,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ),
                _ContinuousWebtoonSlice(
                  key: ValueKey(item.url),
                  item: item,
                ),
              ],
            );
          },
        ),
      );
    }

    return PhysicsPageTurn(
      controller: widget.turnController,
      itemCount: _count,
      initialPage: widget.initialPage,
      rtl: widget.rtl,
      pageFlipEffect: widget.pageFlipEffect,
      onPageChanged: _onPageTurned,
      onPageTurnStart: (speed) {
        ReaderAudio.instance.playPageTurn(
          speed: speed,
          soundEnabled: widget.soundEffect,
        );
      },
      onPagePeel: (speed) {
        ReaderAudio.instance.playPagePeel(
          speed: speed,
          soundEnabled: widget.soundEffect,
        );
      },
      onTurnCancel: () {
        ReaderAudio.instance.stop();
      },
      onCenterTap: widget.onCenterTap,
      itemBuilder: _buildPageItem,
    );
  }
}

// ------------------------------------------------------------- page image

class _PageImage extends StatefulWidget {
  const _PageImage({
    required this.item,
    this.isVertical = false,
    this.onNextPage,
    this.onPrevPage,
  });

  final ReaderPageItem item;
  final bool isVertical;
  final VoidCallback? onNextPage;
  final VoidCallback? onPrevPage;

  @override
  State<_PageImage> createState() => _PageImageState();
}

class _PageImageState extends State<_PageImage> {
  final ScrollController _scrollController = ScrollController();
  int _retryNonce = 0;
  int _autoRetries = 0;
  double _dragStartY = 0;
  DateTime _dragStartTime = DateTime.now();

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
  }

  void _onScroll() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Colors.black,
      width: double.infinity,
      height: double.infinity,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final hasScroll = _scrollController.hasClients &&
              _scrollController.position.haveDimensions &&
              _scrollController.position.maxScrollExtent > 40;
          final atBottom = !hasScroll ||
              (_scrollController.hasClients &&
                  _scrollController.offset >=
                      _scrollController.position.maxScrollExtent - 25);
          final showHint = hasScroll && !atBottom;

          return Stack(
            children: [
              // Scrollable content (single image or multiple seamless slices)
              Positioned.fill(
                child: Listener(
                  behavior: HitTestBehavior.translucent,
                  onPointerDown: (e) {
                    _dragStartY = e.position.dy;
                    _dragStartTime = DateTime.now();
                  },
                  onPointerUp: (e) {
                    if (!widget.isVertical) return;
                    final dy = e.position.dy - _dragStartY;
                    final dt = math.max(
                        1,
                        DateTime.now()
                            .difference(_dragStartTime)
                            .inMilliseconds);
                    final vy = (dy / dt) * 1000.0;

                    final atTop = !hasScroll ||
                        (_scrollController.hasClients &&
                            _scrollController.offset <= 20);

                    if ((dy < -40 || vy < -200) && atBottom) {
                      widget.onNextPage?.call();
                    } else if ((dy > 40 || vy > 200) && atTop) {
                      widget.onPrevPage?.call();
                    }
                  },
                  child: InteractiveViewer(
                    minScale: 1.0,
                    maxScale: 3.5,
                    child: SingleChildScrollView(
                      controller: _scrollController,
                      physics: widget.isVertical
                          ? const BouncingScrollPhysics()
                          : const ClampingScrollPhysics(),
                      child: ConstrainedBox(
                        constraints: BoxConstraints(
                          minWidth: constraints.maxWidth,
                          minHeight: constraints.maxHeight,
                        ),
                        child: Center(
                          child: widget.item.allUrls.length <= 1
                              ? CachedNetworkImage(
                                  key: ValueKey('${widget.item.pageKey}#$_retryNonce'),
                                  imageUrl: widget.item.url,
                                  cacheKey: widget.item.pageKey,
                                  cacheManager: PageCache.instance,
                                  httpHeaders: CfSession.imageHeaders(
                                    widget.item.url,
                                    widget.item.referer,
                                  ),
                                  fadeInDuration: Duration.zero,
                                  fadeOutDuration: Duration.zero,
                                  width: constraints.maxWidth,
                                  fit: BoxFit.fitWidth,
                                  imageBuilder: (context, imageProvider) {
                                    return Image(
                                      image: imageProvider,
                                      width: constraints.maxWidth,
                                      fit: BoxFit.fitWidth,
                                      filterQuality: FilterQuality.medium,
                                    );
                                  },
                                  placeholder: (_, __) => SizedBox(
                                    height: constraints.maxHeight,
                                    child: const Center(
                                      child: SizedBox(
                                        width: 28,
                                        height: 28,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2,
                                          color: Colors.white24,
                                        ),
                                      ),
                                    ),
                                  ),
                                  errorWidget: (_, url, error) {
                                    CfDiag.log('image failed ${Uri.tryParse(url)?.host}: $error');
                                    if (_autoRetries < 1) {
                                      _autoRetries++;
                                      WidgetsBinding.instance.addPostFrameCallback((_) async {
                                        await PageCache.instance.removeFile(widget.item.pageKey);
                                        if (mounted) setState(() => _retryNonce++);
                                      });
                                      return SizedBox(
                                        height: constraints.maxHeight,
                                        child: const Center(
                                          child: SizedBox(
                                            width: 28,
                                            height: 28,
                                            child: CircularProgressIndicator(
                                              strokeWidth: 2,
                                              color: Colors.white24,
                                            ),
                                          ),
                                        ),
                                      );
                                    }
                                    return Center(
                                      child: Padding(
                                        padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 32),
                                        child: Column(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            const Icon(Icons.broken_image_rounded, color: Colors.white30, size: 36),
                                            const SizedBox(height: 8),
                                            const Text("This page didn't load", style: TextStyle(color: Colors.white54, fontSize: 13)),
                                            const SizedBox(height: 12),
                                            OutlinedButton(
                                              onPressed: () async {
                                                await PageCache.instance.removeFile(widget.item.pageKey);
                                                if (mounted) setState(() => _retryNonce++);
                                              },
                                              style: OutlinedButton.styleFrom(
                                                foregroundColor: Colors.white70,
                                                side: const BorderSide(color: Colors.white24),
                                              ),
                                              child: const Text('Retry'),
                                            ),
                                          ],
                                        ),
                                      ),
                                    );
                                  },
                                )
                              : Column(
                                  mainAxisSize: MainAxisSize.min,
                                  crossAxisAlignment: CrossAxisAlignment.stretch,
                                  children: [
                                    for (final sliceUrl in widget.item.allUrls)
                                      _PageSliceImage(
                                        key: ValueKey(sliceUrl),
                                        url: sliceUrl,
                                        width: constraints.maxWidth,
                                        referer: widget.item.referer,
                                      ),
                                  ],
                                ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),

              // Right-side scrollbar rail indicating content below
              if (hasScroll)
                Positioned(
                  right: 4,
                  top: 50,
                  bottom: 50,
                  child: LayoutBuilder(
                    builder: (context, railConstraints) {
                      final trackHeight = railConstraints.maxHeight;
                      final maxExtent =
                          _scrollController.position.maxScrollExtent;
                      final offset =
                          _scrollController.offset.clamp(0.0, maxExtent);
                      final viewport =
                          _scrollController.position.viewportDimension;
                      final totalHeight = maxExtent + viewport;

                      final thumbHeight = (viewport / totalHeight * trackHeight)
                          .clamp(28.0, trackHeight);
                      final thumbTop = maxExtent > 0
                          ? (offset / maxExtent) * (trackHeight - thumbHeight)
                          : 0.0;

                      return IgnorePointer(
                        child: Container(
                          width: 3.5,
                          height: trackHeight,
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.08),
                            borderRadius: BorderRadius.circular(3),
                          ),
                          child: Stack(
                            children: [
                              Positioned(
                                top: thumbTop,
                                left: 0,
                                right: 0,
                                height: thumbHeight,
                                child: Container(
                                  decoration: BoxDecoration(
                                    color: const Color(0xFF00B96B),
                                    borderRadius: BorderRadius.circular(3),
                                    boxShadow: [
                                      BoxShadow(
                                        color: const Color(0xFF00B96B)
                                            .withValues(alpha: 0.7),
                                        blurRadius: 4,
                                        spreadRadius: 0.5,
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                ),

              // Floating bottom pill hint: "Scroll down for more ↓" (glass-like translucent)
              Positioned(
                bottom: 20,
                left: 0,
                right: 0,
                child: IgnorePointer(
                  ignoring: !showHint,
                  child: AnimatedOpacity(
                    opacity: showHint ? 1.0 : 0.0,
                    duration: const Duration(milliseconds: 250),
                    child: Center(
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(20),
                        child: BackdropFilter(
                          filter: ui.ImageFilter.blur(sigmaX: 10, sigmaY: 10),
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 5.5,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.black.withValues(alpha: 0.28),
                              borderRadius: BorderRadius.circular(20),
                              border: Border.all(
                                color: Colors.white.withValues(alpha: 0.14),
                                width: 0.6,
                              ),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withValues(alpha: 0.15),
                                  blurRadius: 12,
                                  offset: const Offset(0, 2),
                                ),
                              ],
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  Icons.keyboard_arrow_down_rounded,
                                  size: 15,
                                  color: const Color(0xFF00B96B)
                                      .withValues(alpha: 0.85),
                                ),
                                const SizedBox(width: 4),
                                Text(
                                  'Scroll down for more',
                                  style: TextStyle(
                                    color: Colors.white.withValues(alpha: 0.8),
                                    fontSize: 11,
                                    fontWeight: FontWeight.w500,
                                    letterSpacing: 0.2,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _PageSliceImage extends StatefulWidget {
  const _PageSliceImage({
    super.key,
    required this.url,
    required this.width,
    this.referer,
  });

  final String url;
  final double width;
  final String? referer;

  @override
  State<_PageSliceImage> createState() => _PageSliceImageState();
}

class _PageSliceImageState extends State<_PageSliceImage> {
  int _retryNonce = 0;
  int _autoRetries = 0;

  @override
  Widget build(BuildContext context) {
    final pageKey = PageCache.keyFor(widget.url);
    return CachedNetworkImage(
      key: ValueKey('$pageKey#$_retryNonce'),
      imageUrl: widget.url,
      cacheKey: pageKey,
      cacheManager: PageCache.instance,
      httpHeaders: CfSession.imageHeaders(widget.url, widget.referer),
      fadeInDuration: Duration.zero,
      fadeOutDuration: Duration.zero,
      width: widget.width,
      fit: BoxFit.fitWidth,
      imageBuilder: (context, imageProvider) {
        return Image(
          image: imageProvider,
          width: widget.width,
          fit: BoxFit.fitWidth,
          filterQuality: FilterQuality.medium,
        );
      },
      placeholder: (_, __) => Container(
        width: widget.width,
        height: math.min(widget.width * 1.3, 360),
        color: Colors.black,
        alignment: Alignment.center,
        child: const SizedBox(
          width: 24,
          height: 24,
          child: CircularProgressIndicator(
            strokeWidth: 2,
            color: Colors.white24,
          ),
        ),
      ),
      errorWidget: (_, url, error) {
        CfDiag.log('image slice failed ${Uri.tryParse(url)?.host}: $error');
        if (_autoRetries < 1) {
          _autoRetries++;
          WidgetsBinding.instance.addPostFrameCallback((_) async {
            await PageCache.instance.removeFile(pageKey);
            if (mounted) setState(() => _retryNonce++);
          });
          return Container(
            width: widget.width,
            height: 180,
            alignment: Alignment.center,
            child: const SizedBox(
              width: 24,
              height: 24,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: Colors.white24,
              ),
            ),
          );
        }
        return Container(
          width: widget.width,
          padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 16),
          color: Colors.black,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.broken_image_rounded,
                  color: Colors.white30, size: 28),
              const SizedBox(height: 6),
              const Text(
                "Image slice failed to load",
                style: TextStyle(color: Colors.white54, fontSize: 12),
              ),
              const SizedBox(height: 8),
              OutlinedButton(
                onPressed: () async {
                  await PageCache.instance.removeFile(pageKey);
                  if (mounted) setState(() => _retryNonce++);
                },
                style: OutlinedButton.styleFrom(
                  foregroundColor: Colors.white70,
                  side: const BorderSide(color: Colors.white24),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                ),
                child: const Text('Retry', style: TextStyle(fontSize: 12)),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _ContinuousWebtoonSlice extends StatefulWidget {
  const _ContinuousWebtoonSlice({
    super.key,
    required this.item,
  });

  final ReaderPageItem item;

  @override
  State<_ContinuousWebtoonSlice> createState() =>
      _ContinuousWebtoonSliceState();
}

class _ContinuousWebtoonSliceState extends State<_ContinuousWebtoonSlice> {
  int _retryNonce = 0;
  int _autoRetries = 0;

  @override
  Widget build(BuildContext context) {
    final pageKey = PageCache.keyFor(widget.item.url);
    final screenWidth = MediaQuery.sizeOf(context).width;

    return CachedNetworkImage(
      key: ValueKey('$pageKey#$_retryNonce'),
      imageUrl: widget.item.url,
      cacheKey: pageKey,
      cacheManager: PageCache.instance,
      httpHeaders:
          CfSession.imageHeaders(widget.item.url, widget.item.referer),
      fadeInDuration: Duration.zero,
      fadeOutDuration: Duration.zero,
      width: screenWidth,
      fit: BoxFit.fitWidth,
      imageBuilder: (context, imageProvider) {
        return Image(
          image: imageProvider,
          width: screenWidth,
          fit: BoxFit.fitWidth,
          filterQuality: FilterQuality.medium,
        );
      },
      placeholder: (_, __) => Container(
        width: screenWidth,
        height: 260,
        color: Colors.black,
        alignment: Alignment.center,
        child: const SizedBox(
          width: 24,
          height: 24,
          child: CircularProgressIndicator(
            strokeWidth: 2,
            color: Colors.white24,
          ),
        ),
      ),
      errorWidget: (_, url, error) {
        CfDiag.log('image slice failed ${Uri.tryParse(url)?.host}: $error');
        if (_autoRetries < 1) {
          _autoRetries++;
          WidgetsBinding.instance.addPostFrameCallback((_) async {
            await PageCache.instance.removeFile(pageKey);
            if (mounted) setState(() => _retryNonce++);
          });
          return Container(
            width: screenWidth,
            height: 180,
            alignment: Alignment.center,
            child: const SizedBox(
              width: 24,
              height: 24,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: Colors.white24,
              ),
            ),
          );
        }
        return Container(
          width: screenWidth,
          padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 16),
          color: Colors.black,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.broken_image_rounded,
                  color: Colors.white30, size: 28),
              const SizedBox(height: 6),
              const Text(
                "Image slice failed to load",
                style: TextStyle(color: Colors.white54, fontSize: 12),
              ),
              const SizedBox(height: 8),
              OutlinedButton(
                onPressed: () async {
                  await PageCache.instance.removeFile(pageKey);
                  if (mounted) setState(() => _retryNonce++);
                },
                style: OutlinedButton.styleFrom(
                  foregroundColor: Colors.white70,
                  side: const BorderSide(color: Colors.white24),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                ),
                child: const Text('Retry', style: TextStyle(fontSize: 12)),
              ),
            ],
          ),
        );
      },
    );
  }
}

// -------------------------------------------------------- all caught up card

class _CaughtUpCard extends StatelessWidget {
  const _CaughtUpCard({
    required this.checking,
    required this.needsVerification,
    required this.onCheck,
    required this.onVerify,
  });

  final bool checking;
  final bool needsVerification;
  final VoidCallback onCheck;
  final VoidCallback onVerify;

  @override
  Widget build(BuildContext context) {
    const green = Color(0xFF00B96B);
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 40),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              needsVerification
                  ? Icons.shield_outlined
                  : Icons.auto_stories_rounded,
              color: needsVerification ? green : Colors.white24,
              size: 48,
            ),
            const SizedBox(height: 18),
            Text(
              needsVerification
                  ? 'Next chapter is ready'
                  : "You're all caught up",
              style: const TextStyle(
                color: Colors.white,
                fontSize: 18,
                fontWeight: FontWeight.w600,
                letterSpacing: 0.3,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              needsVerification
                  ? 'This site needs a quick one-time verification to open it.'
                  : (checking
                      ? 'Checking for new chapters...'
                      : "We'll keep an eye out for the next chapter."),
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.white54, fontSize: 13),
            ),
            const SizedBox(height: 20),
            if (needsVerification)
              ElevatedButton.icon(
                onPressed: onVerify,
                icon: const Icon(Icons.verified_user_outlined, size: 18),
                label: const Text('Verify & continue'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: green,
                  foregroundColor: Colors.white,
                ),
              )
            else if (checking)
              const SizedBox(
                width: 22,
                height: 22,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  valueColor: AlwaysStoppedAnimation<Color>(green),
                ),
              )
            else
              OutlinedButton.icon(
                onPressed: onCheck,
                icon: const Icon(Icons.refresh, size: 18),
                label: const Text('Check for new chapters'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: Colors.white70,
                  side: const BorderSide(color: Colors.white24),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

// --------------------------------------------- next chapter loading card

class _NextChapterLoadingCard extends StatefulWidget {
  const _NextChapterLoadingCard({
    required this.series,
    this.vertical = false,
  });

  final Series series;
  final bool vertical;

  @override
  State<_NextChapterLoadingCard> createState() => _NextChapterLoadingCardState();
}

class _NextChapterLoadingCardState extends State<_NextChapterLoadingCard>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulseController;
  Timer? _stageTimer;
  int _stageIndex = 0;

  static const List<({String title, String detail, IconData icon})> _stages = [
    (
      title: 'Connecting to host',
      detail: 'Establishing secure content pipeline...',
      icon: Icons.wifi_tethering_rounded,
    ),
    (
      title: 'Bypassing site protection',
      detail: 'Verifying Cloudflare clearance tokens...',
      icon: Icons.shield_rounded,
    ),
    (
      title: 'Stripping advertisements',
      detail: 'Purifying layout & filtering rogue trackers...',
      icon: Icons.auto_awesome_rounded,
    ),
    (
      title: 'Decrypting chapter stream',
      detail: 'Extracting high-definition manga pages...',
      icon: Icons.menu_book_rounded,
    ),
  ];

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1800),
    )..repeat(reverse: true);

    _stageTimer = Timer.periodic(const Duration(milliseconds: 1600), (t) {
      if (mounted) {
        setState(() {
          _stageIndex = (_stageIndex + 1) % _stages.length;
        });
      }
    });
  }

  @override
  void dispose() {
    _stageTimer?.cancel();
    _pulseController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    const mint = Color(0xFF00FFA3);
    final currentStage = _stages[_stageIndex];

    return Scaffold(
      backgroundColor: const Color(0xFF07080C),
      body: Stack(
        fit: StackFit.expand,
        children: [
          // Background cover artwork blur
          if (widget.series.coverUrl?.isNotEmpty == true)
            Positioned.fill(
              child: Opacity(
                opacity: 0.16,
                child: CachedNetworkImage(
                  imageUrl: widget.series.coverUrl!,
                  cacheKey: widget.series.coverUrl!,
                  cacheManager: PageCache.instance,
                  httpHeaders: CfSession.imageHeaders(
                    widget.series.coverUrl!,
                    widget.series.url.isNotEmpty ? widget.series.url : null,
                  ),
                  fit: BoxFit.cover,
                  errorWidget: (_, __, ___) => const SizedBox.shrink(),
                ),
              ),
            ),

          // Vignette & gradient background
          const Positioned.fill(
            child: IgnorePointer(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: RadialGradient(
                    center: Alignment(0, -0.15),
                    radius: 1.15,
                    colors: [
                      Color(0x7507080C),
                      Color(0xDD07080C),
                      Color(0xFF07080C),
                    ],
                    stops: [0.0, 0.65, 1.0],
                  ),
                ),
              ),
            ),
          ),

          // Main HUD
          SafeArea(
            child: Center(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 32),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 380),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // Top Security Badge
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 6,
                        ),
                        decoration: BoxDecoration(
                          color: mint.withValues(alpha: 0.08),
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(
                            color: mint.withValues(alpha: 0.3),
                            width: 1,
                          ),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Container(
                              width: 7,
                              height: 7,
                              decoration: const BoxDecoration(
                                color: mint,
                                shape: BoxShape.circle,
                                boxShadow: [
                                  BoxShadow(
                                    color: mint,
                                    blurRadius: 6,
                                    spreadRadius: 1,
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(width: 8),
                            const Text(
                              'AUTOMATED PIPELINE',
                              style: TextStyle(
                                color: mint,
                                fontSize: 10.5,
                                fontWeight: FontWeight.w800,
                                letterSpacing: 1.2,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 28),

                      // Pulsing Security Shield Icon
                      AnimatedBuilder(
                        animation: _pulseController,
                        builder: (context, child) {
                          final scale = 1.0 + (_pulseController.value * 0.06);
                          final glowAlpha =
                              0.2 + (_pulseController.value * 0.25);
                          return Transform.scale(
                            scale: scale,
                            child: Container(
                              width: 88,
                              height: 88,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: const Color(0xFF0E131F),
                                border: Border.all(
                                  color: mint.withValues(alpha: 0.5),
                                  width: 1.5,
                                ),
                                boxShadow: [
                                  BoxShadow(
                                    color: mint.withValues(alpha: glowAlpha),
                                    blurRadius: 28,
                                    spreadRadius: 2,
                                  ),
                                ],
                              ),
                              child: Center(
                                child: Icon(
                                  currentStage.icon,
                                  color: mint,
                                  size: 40,
                                ),
                              ),
                            ),
                          );
                        },
                      ),
                      const SizedBox(height: 28),

                      // Title
                      const Text(
                        'Loading Next Chapter...',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 20,
                          fontWeight: FontWeight.w700,
                          letterSpacing: -0.3,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        widget.series.title,
                        textAlign: TextAlign.center,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.5),
                          fontSize: 13,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      const SizedBox(height: 24),

                      // Dynamic Progress / Stage status with smooth transition
                      AnimatedSwitcher(
                        duration: const Duration(milliseconds: 350),
                        transitionBuilder: (child, anim) => FadeTransition(
                          opacity: anim,
                          child: SlideTransition(
                            position: Tween<Offset>(
                              begin: const Offset(0, 0.15),
                              end: Offset.zero,
                            ).animate(anim),
                            child: child,
                          ),
                        ),
                        child: Column(
                          key: ValueKey(_stageIndex),
                          children: [
                            Text(
                              currentStage.title,
                              textAlign: TextAlign.center,
                              style: const TextStyle(
                                color: Color(0xFFE6E8EE),
                                fontSize: 14.5,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              currentStage.detail,
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                color: Colors.white.withValues(alpha: 0.45),
                                fontSize: 12.5,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 22),

                      // Glowing Shimmer Progress Bar
                      ClipRRect(
                        borderRadius: BorderRadius.circular(6),
                        child: Container(
                          height: 4,
                          width: 220,
                          color: Colors.white10,
                          child: const LinearProgressIndicator(
                            backgroundColor: Colors.transparent,
                            valueColor: AlwaysStoppedAnimation<Color>(mint),
                          ),
                        ),
                      ),
                      const SizedBox(height: 20),

                      Text(
                        widget.vertical
                            ? 'Scroll back up to return to current chapter'
                            : 'Swipe back to return to current chapter',
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.28),
                          fontSize: 11.5,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ------------------------------------------------- loading book placeholder

class _LoadingBookPlaceholder extends StatelessWidget {
  const _LoadingBookPlaceholder({required this.series});

  final Series series;

  @override
  Widget build(BuildContext context) {
    return ReadingLoader(series: series);
  }
}

class _VerificationRequiredView extends StatelessWidget {
  const _VerificationRequiredView({
    required this.url,
    required this.seriesTitle,
    required this.onVerified,
    required this.onCancel,
    this.onPagesResolved,
  });

  final String url;
  final String seriesTitle;
  final VoidCallback onVerified;
  final VoidCallback onCancel;
  final ValueChanged<List<String>>? onPagesResolved;

  @override
  Widget build(BuildContext context) {
    return CfVerificationSheet(
      url: url,
      seriesTitle: seriesTitle,
      isFullScreen: true,
      onClose: onCancel,
      onVerified: (verified) async {
        if (verified.pages.length >= 2) {
          await context.read<ScrapeService>().cacheVerified(
                verified.url,
                pages: verified.pages,
                title: verified.title,
                nextUrl: verified.nextUrl,
                prevUrl: verified.prevUrl,
                chapters: verified.chapters,
              );
          onPagesResolved?.call(verified.pages);
        } else {
          onVerified();
        }
      },
    );
  }
}
