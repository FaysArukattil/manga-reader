import 'dart:math' as math;
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';

import '../blocs/unified_reader_cubit.dart';
import '../data/library_repository.dart';
import '../models/series.dart';
import '../services/local_progress_store.dart';
import '../services/page_cache.dart';
import '../services/reader/chapter_source.dart';
import '../services/reader/reader_audio.dart';
import '../services/scrape/scrape_service.dart';
import 'components/brand_logo.dart';
import 'components/physics_page_turn.dart';

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
  bool _leaving = false;

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
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    _pageController?.dispose();
    _cubit.close();
    super.dispose();
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

  void _showHiddenSettings() {
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
            initialChildSize: 0.65,
            minChildSize: 0.4,
            maxChildSize: 0.9,
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
                          _pageController?.jumpToPage(targetIdx);
                          _cubit.onPageChanged(targetIdx);
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
                prev.pages.length != curr.pages.length &&
                _pageController != null,
            listener: (context, state) {
              // Seamless append keeps pageController intact
            },
            builder: (context, state) {
              if (state.loading) {
                return _LoadingBookPlaceholder(series: widget.series);
              }

              if (state.needsVerification) {
                return _VerificationRequiredView(
                  url: state.verificationUrl ?? widget.series.url,
                  seriesTitle: widget.series.title,
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
                        initialPage: state.currentIndex,
                        vertical: state.vertical,
                        rtl: state.rtl,
                        pageFlipEffect: state.pageFlipEffect,
                        soundEffect: state.soundEffect,
                        isAllCaughtUp: state.isAllCaughtUp,
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
    required this.initialPage,
    required this.vertical,
    required this.rtl,
    required this.pageFlipEffect,
    required this.soundEffect,
    required this.isAllCaughtUp,
    required this.onPageChanged,
    required this.onCenterTap,
  });

  final List<ReaderPageItem> pages;
  final PageController controller;
  final int initialPage;
  final bool vertical;
  final bool rtl;
  final bool pageFlipEffect;
  final bool soundEffect;
  final bool isAllCaughtUp;
  final ValueChanged<int> onPageChanged;
  final VoidCallback onCenterTap;

  @override
  State<_StreamPager> createState() => _StreamPagerState();
}

class _StreamPagerState extends State<_StreamPager> {
  int get _count => widget.pages.length + (widget.isAllCaughtUp ? 1 : 0);
  int? _lastSoundPage;
  late final PhysicsPageTurnController _turnController;

  @override
  void initState() {
    super.initState();
    _lastSoundPage = widget.initialPage;
    _turnController = PhysicsPageTurnController();
    widget.controller.addListener(_syncFromPageController);
    ReaderAudio.instance.init();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _prefetch(widget.initialPage);
    });
  }

  @override
  void didUpdateWidget(_StreamPager oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller.removeListener(_syncFromPageController);
      widget.controller.addListener(_syncFromPageController);
    }
  }

  @override
  void dispose() {
    widget.controller.removeListener(_syncFromPageController);
    _turnController.dispose();
    super.dispose();
  }

  void _syncFromPageController() {
    if (widget.controller.hasClients && widget.controller.page != null) {
      final target = widget.controller.page!.round();
      if (_turnController.currentPage != target) {
        _turnController.jumpToPage(target);
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
        precacheImage(
          CachedNetworkImageProvider(
            item.url,
            cacheKey: item.pageKey,
            cacheManager: PageCache.instance,
            headers: {
              'User-Agent': ScrapeService.mobileUserAgent,
              if (item.referer != null) 'Referer': item.referer!,
            },
          ),
          context,
        );
      }
    }
  }

  void _go(int delta) {
    final cur = widget.controller.hasClients
        ? (widget.controller.page?.round() ?? widget.initialPage)
        : widget.initialPage;
    final target = cur + delta;
    if (target < 0 || target >= _count) return;
    widget.controller.animateToPage(
      target,
      duration: const Duration(milliseconds: 280),
      curve: Curves.easeOutCubic,
    );
  }

  Widget _buildPageItem(BuildContext context, int i) {
    if (i == widget.pages.length) {
      return const _CaughtUpCard();
    }

    final item = widget.pages[i];
    final bool isFirstInChapter =
        i > 0 && widget.pages[i - 1].chapterId != item.chapterId;

    return Stack(
      fit: StackFit.expand,
      children: [
        Positioned.fill(child: _PageImage(item: item)),
        // Barely visible chapter seam marker
        if (isFirstInChapter)
          Positioned(
            top: 16,
            left: 0,
            right: 0,
            child: Center(
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.8),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                    color: Colors.white12,
                    width: 0.5,
                  ),
                ),
                child: Text(
                  item.chapterLabel,
                  style: const TextStyle(
                    color: Color(0xFF00B96B),
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
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
          if (frac < 0.28) {
            _go(-1);
          } else if (frac > 0.72) {
            _go(1);
          } else {
            widget.onCenterTap();
          }
        },
        child: PageView.builder(
          controller: widget.controller,
          scrollDirection: Axis.vertical,
          itemCount: _count,
          onPageChanged: _onPageTurned,
          itemBuilder: (context, i) {
            return _AnimatedPage(
              controller: widget.controller,
              index: i,
              vertical: true,
              rtl: false,
              pageFlipEffect: false,
              child: _buildPageItem(context, i),
            );
          },
        ),
      );
    }

    return PhysicsPageTurn(
      controller: _turnController,
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

// ------------------------------------------------------------- 3D page flip

class _AnimatedPage extends StatelessWidget {
  const _AnimatedPage({
    required this.controller,
    required this.index,
    required this.vertical,
    required this.rtl,
    required this.pageFlipEffect,
    required this.child,
  });

  final PageController controller;
  final int index;
  final bool vertical;
  final bool rtl;
  final bool pageFlipEffect;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: controller,
      child: child,
      builder: (context, child) {
        double v;
        if (controller.hasClients && controller.position.haveDimensions) {
          v = (controller.page ?? controller.initialPage.toDouble()) - index;
        } else {
          v = controller.initialPage.toDouble() - index;
        }
        v = v.clamp(-1.0, 1.0).toDouble();
        if (v == 0) return child!;

        if (vertical) {
          return Opacity(
            opacity: 1 - v.abs() * 0.35,
            child: child,
          );
        }

        if (!pageFlipEffect) {
          return Opacity(
            opacity: 1 - v.abs() * 0.25,
            child: child,
          );
        }

        final sign = rtl ? -1.0 : 1.0;
        final progress = v.abs();
        final turningForward = (v * sign) > 0;

        // Realistic 3D physical page curl rotation
        final angle = -v * sign * 1.35;
        final matrix = Matrix4.identity()
          ..setEntry(3, 2, 0.0014)
          ..rotateY(angle);

        return Opacity(
          opacity: (1 - progress * 0.2).clamp(0.0, 1.0),
          child: Transform(
            transform: matrix,
            alignment:
                turningForward ? Alignment.centerLeft : Alignment.centerRight,
            child: Stack(
              fit: StackFit.expand,
              children: [
                child!,
                // Dynamic page fold and spine shadow overlay as the page turns
                IgnorePointer(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.centerLeft,
                        end: Alignment.centerRight,
                        colors: [
                          Colors.black.withValues(alpha: 0.38 * progress),
                          Colors.transparent,
                          Colors.black.withValues(alpha: 0.28 * progress),
                        ],
                        stops: const [0.0, 0.2, 1.0],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

// ------------------------------------------------------------- page image

class _PageImage extends StatefulWidget {
  const _PageImage({required this.item});

  final ReaderPageItem item;

  @override
  State<_PageImage> createState() => _PageImageState();
}

class _PageImageState extends State<_PageImage> {
  final ScrollController _scrollController = ScrollController();

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Colors.black,
      width: double.infinity,
      height: double.infinity,
      child: CachedNetworkImage(
        imageUrl: widget.item.url,
        cacheKey: widget.item.pageKey,
        cacheManager: PageCache.instance,
        httpHeaders: {
          'User-Agent': ScrapeService.mobileUserAgent,
          if (widget.item.referer != null) 'Referer': widget.item.referer!,
        },
        fadeInDuration: Duration.zero,
        imageBuilder: (context, imageProvider) {
          return LayoutBuilder(
            builder: (context, constraints) {
              return InteractiveViewer(
                minScale: 1.0,
                maxScale: 3.5,
                child: SingleChildScrollView(
                  controller: _scrollController,
                  physics: const ClampingScrollPhysics(),
                  child: ConstrainedBox(
                    constraints: BoxConstraints(
                      minWidth: constraints.maxWidth,
                      minHeight: constraints.maxHeight,
                    ),
                    child: Center(
                      child: Image(
                        image: imageProvider,
                        width: constraints.maxWidth,
                        fit: BoxFit.fitWidth,
                        filterQuality: FilterQuality.medium,
                      ),
                    ),
                  ),
                ),
              );
            },
          );
        },
        placeholder: (_, __) => const Center(
          child: SizedBox(
            width: 28,
            height: 28,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              color: Colors.white24,
            ),
          ),
        ),
        errorWidget: (_, __, ___) => const Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.broken_image_rounded, color: Colors.white30, size: 36),
              SizedBox(height: 8),
              Text(
                'Retrying page...',
                style: TextStyle(color: Colors.white38, fontSize: 12),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// -------------------------------------------------------- all caught up card

class _CaughtUpCard extends StatelessWidget {
  const _CaughtUpCard();

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Padding(
        padding: EdgeInsets.symmetric(horizontal: 40),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.auto_stories_rounded,
              color: Colors.white24,
              size: 48,
            ),
            SizedBox(height: 18),
            Text(
              "You're all caught up",
              style: TextStyle(
                color: Colors.white,
                fontSize: 18,
                fontWeight: FontWeight.w600,
                letterSpacing: 0.3,
              ),
            ),
            SizedBox(height: 8),
            Text(
              "Checking quietly for new chapters...",
              style: TextStyle(
                color: Colors.white54,
                fontSize: 13,
              ),
            ),
          ],
        ),
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
    return Stack(
      children: [
        // Ambient soft backdrop
        if (series.coverUrl != null && series.coverUrl!.isNotEmpty)
          Positioned.fill(
            child: Opacity(
              opacity: 0.18,
              child: Image.network(
                series.coverUrl!,
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => const SizedBox.shrink(),
              ),
            ),
          ),
        Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const BrandLogo(size: 72, withGlow: true),
              const SizedBox(height: 20),
              const SizedBox(
                width: 24,
                height: 24,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: Color(0xFF00B96B),
                ),
              ),
              const SizedBox(height: 18),
              Text(
                series.title,
                textAlign: TextAlign.center,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 17,
                  fontWeight: FontWeight.w600,
                ),
              ),
              if (series.chapter.isNotEmpty) ...[
                const SizedBox(height: 6),
                Text(
                  series.chapter,
                  style: const TextStyle(
                    color: Color(0xFF00B96B),
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
              const SizedBox(height: 10),
              const Text(
                'Opening book...',
                style: TextStyle(
                  color: Colors.white54,
                  fontSize: 13,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _VerificationRequiredView extends StatefulWidget {
  const _VerificationRequiredView({
    required this.url,
    required this.seriesTitle,
    required this.onVerified,
    required this.onCancel,
  });

  final String url;
  final String seriesTitle;
  final VoidCallback onVerified;
  final VoidCallback onCancel;

  @override
  State<_VerificationRequiredView> createState() =>
      _VerificationRequiredViewState();
}

class _VerificationRequiredViewState extends State<_VerificationRequiredView> {
  bool _modalOpened = false;

  @override
  void initState() {
    super.initState();
    // Auto-open the verification modal sheet for immediate resolution
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && !_modalOpened) {
        _openModal();
      }
    });
  }

  Future<void> _openModal() async {
    setState(() => _modalOpened = true);
    final verified = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      enableDrag: false,
      builder: (ctx) => _VerificationModalSheet(url: widget.url),
    );

    if (verified == true) {
      widget.onVerified();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: const Color(0xFF00B96B).withValues(alpha: 0.12),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.security_rounded,
                color: Color(0xFF00B96B),
                size: 48,
              ),
            ),
            const SizedBox(height: 20),
            const Text(
              'Security Verification Required',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Colors.white,
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 10),
            Text(
              '${widget.seriesTitle} requires Cloudflare / Turnstile human verification before displaying chapter pages.',
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: Colors.white60,
                fontSize: 13,
                height: 1.4,
              ),
            ),
            const SizedBox(height: 24),
            ElevatedButton.icon(
              onPressed: _openModal,
              icon: const Icon(Icons.verified_user_outlined, size: 18),
              label: const Text('Verify & Open Book'),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF00B96B),
                foregroundColor: Colors.white,
                padding:
                    const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
            const SizedBox(height: 12),
            TextButton(
              onPressed: widget.onCancel,
              child: const Text(
                'Go Back to Library',
                style: TextStyle(color: Colors.white38),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _VerificationModalSheet extends StatefulWidget {
  const _VerificationModalSheet({required this.url});

  final String url;

  @override
  State<_VerificationModalSheet> createState() =>
      _VerificationModalSheetState();
}

class _VerificationModalSheetState extends State<_VerificationModalSheet> {
  InAppWebViewController? _webViewController;
  double _progress = 0;
  bool _verifiedHandled = false;

  void _checkTitleForBypass(String? title) {
    if (_verifiedHandled || title == null) return;
    final lower = title.toLowerCase();
    final isChallenge = lower.contains('just a moment') ||
        lower.contains('turnstile') ||
        lower.contains('cloudflare') ||
        lower.contains('security check') ||
        lower.contains('verifying');
    if (!isChallenge && title.trim().isNotEmpty) {
      _verifiedHandled = true;
      Future.delayed(const Duration(milliseconds: 600), () {
        if (mounted && Navigator.canPop(context)) {
          Navigator.pop(context, true);
        }
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final host = Uri.tryParse(widget.url)?.host ?? widget.url;

    return Container(
      height: MediaQuery.of(context).size.height * 0.88,
      decoration: const BoxDecoration(
        color: Color(0xFF141416),
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
            child: Row(
              children: [
                const Icon(
                  Icons.shield_outlined,
                  color: Color(0xFF00B96B),
                  size: 20,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Security Verification',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      Text(
                        host,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Colors.white38,
                          fontSize: 11,
                        ),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.refresh,
                      color: Colors.white70, size: 20),
                  tooltip: 'Reload',
                  onPressed: () => _webViewController?.reload(),
                ),
                TextButton(
                  onPressed: () {
                    if (Navigator.canPop(context)) {
                      Navigator.pop(context, true);
                    }
                  },
                  child: const Text(
                    'Done',
                    style: TextStyle(
                      color: Color(0xFF00B96B),
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                IconButton(
                  icon:
                      const Icon(Icons.close, color: Colors.white70, size: 20),
                  onPressed: () => Navigator.pop(context, false),
                ),
              ],
            ),
          ),
          if (_progress < 1.0)
            LinearProgressIndicator(
              value: _progress,
              minHeight: 2,
              backgroundColor: Colors.transparent,
              valueColor:
                  const AlwaysStoppedAnimation<Color>(Color(0xFF00B96B)),
            ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            color: Colors.white.withValues(alpha: 0.04),
            child: const Row(
              children: [
                Icon(Icons.info_outline, size: 14, color: Colors.white54),
                SizedBox(width: 6),
                Expanded(
                  child: Text(
                    'Complete the "Verify you are human" check below. It will continue automatically.',
                    style: TextStyle(color: Colors.white70, fontSize: 11),
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: InAppWebView(
              initialUrlRequest: URLRequest(url: WebUri(widget.url)),
              initialSettings: InAppWebViewSettings(
                userAgent: ScrapeService.mobileUserAgent,
                javaScriptEnabled: true,
                domStorageEnabled: true,
                thirdPartyCookiesEnabled: true,
                supportZoom: true,
              ),
              onWebViewCreated: (c) => _webViewController = c,
              onProgressChanged: (_, p) {
                if (mounted) setState(() => _progress = p / 100);
              },
              onTitleChanged: (_, title) => _checkTitleForBypass(title),
              onLoadStop: (controller, uri) async {
                final title = await controller.getTitle();
                _checkTitleForBypass(title);
              },
            ),
          ),
        ],
      ),
    );
  }
}
