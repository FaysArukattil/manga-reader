import 'dart:math' as math;

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../blocs/md_blocs.dart';
import '../data/library_repository.dart';
import '../services/mangadex_service.dart';
import '../services/page_cache.dart';

/// Native reader: pages come straight from MangaDex, so there is no website
/// chrome, no ads and no popups. Horizontal "book" mode with a page-turn
/// effect, or vertical "reels" mode.
class MdReaderPage extends StatefulWidget {
  const MdReaderPage({
    super.key,
    required this.title,
    required this.chapters,
    required this.startIndex,
    this.startPage = 0,
    this.seriesId,
  });

  final String title;
  final List<MdChapter> chapters; // oldest first
  final int startIndex;
  final int startPage;
  final String? seriesId; // shelf id; progress is saved only when set

  static Future<void> open(
    BuildContext context, {
    required String title,
    required List<MdChapter> chapters,
    required int startIndex,
    int startPage = 0,
    String? seriesId,
  }) {
    return Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => MdReaderPage(
          title: title,
          chapters: chapters,
          startIndex: startIndex,
          startPage: startPage,
          seriesId: seriesId,
        ),
      ),
    );
  }

  @override
  State<MdReaderPage> createState() => _MdReaderPageState();
}

class _MdReaderPageState extends State<MdReaderPage>
    with WidgetsBindingObserver {
  late final MdReaderCubit _cubit;

  @override
  void initState() {
    super.initState();
    _cubit = MdReaderCubit(
      service: context.read<MangaDexService>(),
      store: context.read<ChapterStore>(),
      chapters: widget.chapters,
      startIndex: widget.startIndex,
      startPage: widget.startPage,
      library:
          widget.seriesId == null ? null : context.read<LibraryRepository>(),
      seriesId: widget.seriesId,
    );
    WidgetsBinding.instance.addObserver(this);
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    _cubit.close();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused) _cubit.flush();
  }

  void _showSettings() {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (_) =>
          BlocProvider.value(value: _cubit, child: const _SettingsSheet()),
    );
  }

  @override
  Widget build(BuildContext context) {
    return BlocProvider.value(
      value: _cubit,
      child: BlocListener<MdReaderCubit, MdReaderState>(
        listenWhen: (a, b) => b.message != null && a.message != b.message,
        listener: (context, s) {
          ScaffoldMessenger.of(context)
            ..hideCurrentSnackBar()
            ..showSnackBar(SnackBar(content: Text(s.message!)));
          _cubit.clearMessage();
        },
        child: Scaffold(
          backgroundColor: Colors.black,
          body: Stack(
            children: [
              Positioned.fill(
                child: BlocBuilder<MdReaderCubit, MdReaderState>(
                  buildWhen: (a, b) =>
                      a.index != b.index ||
                      a.loading != b.loading ||
                      a.error != b.error ||
                      a.urls != b.urls ||
                      a.vertical != b.vertical ||
                      a.rtl != b.rtl,
                  builder: (context, s) {
                    if (s.loading) {
                      return const Center(child: CircularProgressIndicator());
                    }
                    if (s.error != null) {
                      return Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              s.error!,
                              textAlign: TextAlign.center,
                              style: const TextStyle(color: Colors.white70),
                            ),
                            const SizedBox(height: 12),
                            FilledButton(
                              onPressed: () => _cubit.loadChapter(s.index),
                              child: const Text('Retry'),
                            ),
                          ],
                        ),
                      );
                    }
                    return _Pager(
                      key: ValueKey('${s.index}|${s.vertical}|${s.rtl}'),
                      urls: s.urls,
                      initialPage: s.page,
                      vertical: s.vertical,
                      rtl: s.rtl,
                      onPage: _cubit.setPage,
                      onTapCenter: _cubit.toggleUi,
                      endBuilder: (_) => _EndCard(
                        chapter: _cubit.current,
                        hasNext: _cubit.hasNext,
                        onNext: _cubit.next,
                      ),
                    );
                  },
                ),
              ),
              _Overlay(
                title: widget.title,
                onBack: () => Navigator.of(context).maybePop(),
                onSettings: _showSettings,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ------------------------------------------------------------------ pager

class _Pager extends StatefulWidget {
  const _Pager({
    super.key,
    required this.urls,
    required this.initialPage,
    required this.vertical,
    required this.rtl,
    required this.onPage,
    required this.onTapCenter,
    required this.endBuilder,
  });

  final List<String> urls;
  final int initialPage;
  final bool vertical;
  final bool rtl;
  final ValueChanged<int> onPage;
  final VoidCallback onTapCenter;
  final WidgetBuilder endBuilder;

  @override
  State<_Pager> createState() => _PagerState();
}

class _PagerState extends State<_Pager> {
  late final PageController _c = PageController(
    initialPage: widget.initialPage,
  );

  int get _count => widget.urls.length + 1; // + end card

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => mounted ? _prefetch(widget.initialPage) : null,
    );
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  /// Download the next few pages to disk before the reader gets there.
  void _prefetch(int page) {
    for (var i = 1; i <= 3; i++) {
      final n = page + i;
      if (n < widget.urls.length) {
        final u = widget.urls[n];
        precacheImage(
          CachedNetworkImageProvider(
            u,
            cacheKey: PageCache.keyFor(u),
            cacheManager: PageCache.instance,
          ),
          context,
        );
      }
    }
  }

  void _go(int delta) {
    final current =
        _c.hasClients ? (_c.page?.round() ?? 0) : widget.initialPage;
    final target = current + delta;
    if (target < 0 || target >= _count) return;
    _c.animateToPage(
      target,
      duration: const Duration(milliseconds: 320),
      curve: Curves.easeOutCubic,
    );
  }

  @override
  Widget build(BuildContext context) {
    final flip = widget.rtl && !widget.vertical;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapUp: (d) {
        final size = context.size;
        if (size == null) return;
        final frac = widget.vertical
            ? d.localPosition.dy / size.height
            : d.localPosition.dx / size.width;
        if (frac < 0.25) {
          _go(flip ? 1 : -1);
        } else if (frac > 0.75) {
          _go(flip ? -1 : 1);
        } else {
          widget.onTapCenter();
        }
      },
      child: PageView.builder(
        controller: _c,
        scrollDirection: widget.vertical ? Axis.vertical : Axis.horizontal,
        reverse: flip,
        itemCount: _count,
        onPageChanged: (p) {
          widget.onPage(math.min(p, widget.urls.length - 1));
          _prefetch(p);
        },
        itemBuilder: (context, i) => _AnimatedPage(
          controller: _c,
          index: i,
          vertical: widget.vertical,
          rtl: widget.rtl,
          child: i == widget.urls.length
              ? widget.endBuilder(context)
              : _PageImage(url: widget.urls[i]),
        ),
      ),
    );
  }
}

/// Page-turn (horizontal) / depth-fade (vertical) transition driven by the
/// PageController, so it follows the finger.
class _AnimatedPage extends StatelessWidget {
  const _AnimatedPage({
    required this.controller,
    required this.index,
    required this.vertical,
    required this.rtl,
    required this.child,
  });

  final PageController controller;
  final int index;
  final bool vertical;
  final bool rtl;
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
            opacity: 1 - v.abs() * 0.6,
            child: Transform.scale(scale: 1 - v.abs() * 0.12, child: child),
          );
        }
        final sign = rtl ? -1.0 : 1.0;
        final matrix = Matrix4.identity()
          ..setEntry(3, 2, 0.0012)
          ..rotateY(-v * sign * 1.2);
        return Opacity(
          opacity: 1 - v.abs() * 0.35,
          child: Transform(
            transform: matrix,
            alignment:
                (v * sign) > 0 ? Alignment.centerLeft : Alignment.centerRight,
            child: child,
          ),
        );
      },
    );
  }
}

class _PageImage extends StatefulWidget {
  const _PageImage({required this.url});
  final String url;

  @override
  State<_PageImage> createState() => _PageImageState();
}

class _PageImageState extends State<_PageImage> {
  int _attempt = 0;

  @override
  Widget build(BuildContext context) {
    final px = MediaQuery.sizeOf(context).width *
        MediaQuery.devicePixelRatioOf(context);
    return CachedNetworkImage(
      key: ValueKey('${widget.url}#$_attempt'),
      imageUrl: widget.url,
      cacheKey: PageCache.keyFor(widget.url),
      cacheManager: PageCache.instance,
      fit: BoxFit.contain,
      memCacheWidth: math.min(1600, px.round()),
      fadeInDuration: Duration.zero,
      placeholder: (_, __) => const Center(
        child: SizedBox(
          width: 28,
          height: 28,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
      ),
      errorWidget: (_, __, ___) => Center(
        child: IconButton(
          iconSize: 40,
          color: Colors.white70,
          icon: const Icon(Icons.refresh),
          tooltip: 'Retry',
          onPressed: () => setState(() => _attempt++),
        ),
      ),
    );
  }
}

class _EndCard extends StatelessWidget {
  const _EndCard({
    required this.chapter,
    required this.hasNext,
    required this.onNext,
  });

  final MdChapter chapter;
  final bool hasNext;
  final VoidCallback onNext;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'End of ${chapter.label}',
              style: const TextStyle(color: Colors.white, fontSize: 22),
            ),
            const SizedBox(height: 8),
            Text(
              chapter.group.isEmpty
                  ? 'Provided by MangaDex'
                  : 'Scanlated by ${chapter.group}\nProvided by MangaDex',
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.white60),
            ),
            const SizedBox(height: 24),
            if (hasNext)
              FilledButton.icon(
                onPressed: onNext,
                icon: const Icon(Icons.skip_next),
                label: const Text('Next chapter'),
              )
            else
              const Text(
                "You're all caught up",
                style: TextStyle(color: Colors.white70),
              ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------- overlay

class _Overlay extends StatelessWidget {
  const _Overlay({
    required this.title,
    required this.onBack,
    required this.onSettings,
  });

  final String title;
  final VoidCallback onBack;
  final VoidCallback onSettings;

  @override
  Widget build(BuildContext context) {
    final cubit = context.read<MdReaderCubit>();
    return BlocBuilder<MdReaderCubit, MdReaderState>(
      buildWhen: (a, b) =>
          a.showUi != b.showUi ||
          a.page != b.page ||
          a.index != b.index ||
          a.urls != b.urls,
      builder: (context, s) {
        final chapter = cubit.current;
        return IgnorePointer(
          ignoring: !s.showUi,
          child: AnimatedOpacity(
            opacity: s.showUi ? 1 : 0,
            duration: const Duration(milliseconds: 180),
            child: Column(
              children: [
                Container(
                  color: const Color(0xCC000000),
                  child: SafeArea(
                    bottom: false,
                    child: Row(
                      children: [
                        IconButton(
                          color: Colors.white,
                          icon: const Icon(Icons.arrow_back),
                          onPressed: onBack,
                        ),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                title,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              Text(
                                chapter.group.isEmpty
                                    ? '${chapter.label} · MangaDex'
                                    : '${chapter.label} · ${chapter.group} · MangaDex',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  color: Colors.white60,
                                  fontSize: 12,
                                ),
                              ),
                            ],
                          ),
                        ),
                        IconButton(
                          color: Colors.white,
                          icon: const Icon(Icons.tune),
                          onPressed: onSettings,
                        ),
                      ],
                    ),
                  ),
                ),
                const Spacer(),
                Container(
                  color: const Color(0xCC000000),
                  padding: const EdgeInsets.fromLTRB(8, 4, 8, 8),
                  child: SafeArea(
                    top: false,
                    child: Row(
                      children: [
                        IconButton(
                          color: Colors.white,
                          icon: const Icon(Icons.skip_previous),
                          onPressed: cubit.hasPrev ? cubit.prev : null,
                        ),
                        Expanded(
                          child: LinearProgressIndicator(
                            value: s.urls.isEmpty
                                ? 0
                                : (s.page + 1) / s.urls.length,
                            minHeight: 3,
                          ),
                        ),
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 10),
                          child: Text(
                            '${s.page + 1} / ${s.urls.length}',
                            style: const TextStyle(color: Colors.white),
                          ),
                        ),
                        IconButton(
                          color: Colors.white,
                          icon: const Icon(Icons.skip_next),
                          onPressed: cubit.hasNext ? cubit.next : null,
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
    );
  }
}

class _SettingsSheet extends StatelessWidget {
  const _SettingsSheet();

  @override
  Widget build(BuildContext context) {
    final cubit = context.read<MdReaderCubit>();
    return SafeArea(
      child: BlocBuilder<MdReaderCubit, MdReaderState>(
        buildWhen: (a, b) =>
            a.vertical != b.vertical ||
            a.rtl != b.rtl ||
            a.dataSaver != b.dataSaver ||
            a.download != b.download,
        builder: (context, s) => Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                width: double.infinity,
                child: SegmentedButton<bool>(
                  segments: const [
                    ButtonSegment(
                      value: false,
                      icon: Icon(Icons.auto_stories),
                      label: Text('Book'),
                    ),
                    ButtonSegment(
                      value: true,
                      icon: Icon(Icons.swipe_vertical),
                      label: Text('Reels'),
                    ),
                  ],
                  selected: {s.vertical},
                  onSelectionChanged: (v) => cubit.setVertical(v.first),
                ),
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Right-to-left (manga)'),
                value: s.rtl,
                onChanged: s.vertical ? null : cubit.setRtl,
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Data saver (smaller, faster images)'),
                value: s.dataSaver,
                onChanged: cubit.setDataSaver,
              ),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.download_for_offline_outlined),
                title: const Text('Save this chapter for offline'),
                subtitle: s.download == null
                    ? null
                    : LinearProgressIndicator(value: s.download),
                onTap: s.download == null ? cubit.downloadCurrent : null,
              ),
              const SizedBox(height: 4),
              Text(
                'Chapters are provided by MangaDex and uploaded by scanlation groups.',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
