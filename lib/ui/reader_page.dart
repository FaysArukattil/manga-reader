import 'dart:collection';
import 'dart:math' as math;

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';

import '../blocs/reader_cubit.dart';
import '../data/library_repository.dart';
import '../models/series.dart';
import '../services/anilist_service.dart';
import '../services/page_cache.dart';
import '../services/thumbnail_store.dart';
import '../services/web_scraper.dart';
import 'ad_block.dart';
import 'mode_scripts.dart';

/// Clean native book reader: strips website chrome, scripts, popups, and ads.
/// Automatically scrapes chapter images from any manga/comic website and renders
/// them as a sleek 3D-flippable book.
class ReaderPage extends StatefulWidget {
  const ReaderPage({super.key, required this.series});

  final Series series;

  static Future<void> open(BuildContext context, Series series) {
    return Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => ReaderPage(series: series)),
    );
  }

  @override
  State<ReaderPage> createState() => _ReaderPageState();
}

class _ReaderPageState extends State<ReaderPage> with WidgetsBindingObserver {
  late final ReaderCubit _cubit;
  late final ThumbnailStore _thumbs;
  late final InAppWebViewSettings _settings;
  InAppWebViewController? _web;

  final ValueNotifier<double> _progress = ValueNotifier<double>(0);
  bool _leaving = false;

  // Book Reader State
  bool _bookMode = true; // Book mode by default
  bool _scraping = true;
  List<String> _pages = [];
  int _currentPage = 0;
  bool _vertical = false;
  bool _rtl = true; // Manga is right-to-left by default
  bool _showControls = false;
  PageController? _pageController;

  String? _nextChapterUrl;
  String? _prevChapterUrl;

  @override
  void initState() {
    super.initState();
    _thumbs = context.read<ThumbnailStore>();
    _cubit = ReaderCubit(
      series: widget.series,
      library: context.read<LibraryRepository>(),
      anilist: context.read<AniListService>(),
    );

    _settings = InAppWebViewSettings(
      javaScriptEnabled: true,
      javaScriptCanOpenWindowsAutomatically: false,
      supportMultipleWindows: true,
      useShouldOverrideUrlLoading: true,
      mediaPlaybackRequiresUserGesture: true,
      cacheEnabled: true,
      domStorageEnabled: true,
      mixedContentMode: MixedContentMode.MIXED_CONTENT_COMPATIBILITY_MODE,
      useHybridComposition: true,
      supportZoom: true,
      builtInZoomControls: false,
      displayZoomControls: false,
      thirdPartyCookiesEnabled: true,
      verticalScrollBarEnabled: false,
      allowsBackForwardNavigationGestures: true,
      contentBlockers: buildContentBlockers(),
    );

    WidgetsBinding.instance.addObserver(this);
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    _pageController?.dispose();
    _progress.dispose();
    _cubit.close();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused) {
      _saveProgress();
      try {
        _web?.pauseTimers();
      } catch (_) {}
    } else if (state == AppLifecycleState.resumed) {
      try {
        _web?.resumeTimers();
      } catch (_) {}
    }
  }

  void _saveProgress() {
    if (_pages.isNotEmpty) {
      _cubit.flush(scroll: _currentPage.toDouble());
    }
  }

  Future<void> _extractPages() async {
    final web = _web;
    if (web == null) return;

    try {
      // 1. Strip ads and popups from DOM
      await web.evaluateJavascript(source: WebScraper.stripAdsJs);

      // 2. Extract reader image URLs
      final res = await web.evaluateJavascript(
        source: WebScraper.extractImagesJs,
      );

      if (res is List && res.isNotEmpty) {
        final list = res.map((e) => e.toString()).toList();
        if (list.length >= 2 && mounted) {
          int initialPage = 0;
          if (widget.series.scroll >= 1.0) {
            initialPage =
                widget.series.scroll.toInt().clamp(0, list.length - 1);
          } else if (widget.series.scroll > 0.0) {
            initialPage = (widget.series.scroll * list.length).round().clamp(
                  0,
                  list.length - 1,
                );
          }

          setState(() {
            _pages = list;
            _currentPage = initialPage;
            _scraping = false;
            _pageController?.dispose();
            _pageController = PageController(initialPage: initialPage);
          });
          _saveProgress();
        }
      }

      // 3. Extract next/prev chapter URLs
      final nav = await web.evaluateJavascript(
        source: WebScraper.extractNavigationJs,
      );
      if (nav is Map && mounted) {
        setState(() {
          _nextChapterUrl = nav['next']?.toString();
          _prevChapterUrl = nav['prev']?.toString();
        });
      }
    } catch (_) {}
  }

  Future<void> _captureThumbnail() async {
    final web = _web;
    if (web == null) return;
    try {
      final bytes = await web
          .takeScreenshot(
            screenshotConfiguration: ScreenshotConfiguration(
              compressFormat: CompressFormat.JPEG,
              quality: 45,
              snapshotWidth: 360,
            ),
          )
          .timeout(const Duration(seconds: 2));
      if (bytes != null && bytes.isNotEmpty) {
        await _thumbs.save(widget.series.id, bytes);
      }
    } catch (_) {}
  }

  Future<void> _leave() async {
    if (_leaving) return;
    _leaving = true;
    _saveProgress();
    await _captureThumbnail();
    if (mounted) Navigator.of(context).pop();
  }

  void _loadUrl(String url) {
    setState(() {
      _scraping = true;
      _pages = [];
      _currentPage = 0;
    });
    _web?.loadUrl(urlRequest: URLRequest(url: WebUri(url)));
  }

  void _onNextChapter() {
    if (_nextChapterUrl != null) {
      _loadUrl(_nextChapterUrl!);
    } else {
      final next = _cubit.stepUrl(1);
      if (next != null) _loadUrl(next);
    }
  }

  void _onPrevChapter() {
    if (_prevChapterUrl != null) {
      _loadUrl(_prevChapterUrl!);
    } else {
      final prev = _cubit.stepUrl(-1);
      if (prev != null) _loadUrl(prev);
    }
  }

  void _showSettings() {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) => BlocProvider.value(
        value: _cubit,
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
            child: BlocBuilder<ReaderCubit, ReaderState>(
              builder: (context, s) => Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    widget.series.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  Text(
                    widget.series.host,
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'Reading Direction',
                    style: Theme.of(context).textTheme.labelMedium,
                  ),
                  const SizedBox(height: 6),
                  SizedBox(
                    width: double.infinity,
                    child: SegmentedButton<String>(
                      segments: const [
                        ButtonSegment(
                          value: 'rtl',
                          label: Text('Manga (RTL)'),
                          icon: Icon(Icons.arrow_back),
                        ),
                        ButtonSegment(
                          value: 'ltr',
                          label: Text('Book (LTR)'),
                          icon: Icon(Icons.arrow_forward),
                        ),
                        ButtonSegment(
                          value: 'vertical',
                          label: Text('Webtoon'),
                          icon: Icon(Icons.swap_vert),
                        ),
                      ],
                      selected: {
                        _vertical ? 'vertical' : (_rtl ? 'rtl' : 'ltr'),
                      },
                      onSelectionChanged: (val) {
                        setState(() {
                          final v = val.first;
                          if (v == 'vertical') {
                            _vertical = true;
                          } else {
                            _vertical = false;
                            _rtl = (v == 'rtl');
                          }
                          _pageController?.dispose();
                          _pageController = PageController(
                            initialPage: _currentPage,
                          );
                        });
                        Navigator.pop(sheetContext);
                      },
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'Screen Dimmer',
                    style: Theme.of(context).textTheme.labelMedium,
                  ),
                  Row(
                    children: [
                      const Icon(Icons.brightness_low, size: 20),
                      Expanded(
                        child: Slider(
                          value: s.dim,
                          min: 0,
                          max: 0.7,
                          onChanged: _cubit.setDim,
                          onChangeEnd: (_) => _cubit.commitDim(),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: () {
                            Navigator.pop(sheetContext);
                            setState(() => _bookMode = !_bookMode);
                          },
                          icon: Icon(
                            _bookMode
                                ? Icons.public
                                : Icons.auto_stories_rounded,
                          ),
                          label: Text(
                            _bookMode ? 'Web View' : 'Book Reader',
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: FilledButton.tonalIcon(
                          onPressed: () {
                            Navigator.pop(sheetContext);
                            _leave();
                          },
                          icon: const Icon(Icons.grid_view_rounded),
                          label: const Text('Back to Shelf'),
                        ),
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
          body: Stack(
            children: [
              // Offstage background WebView keeps scraping & JS running without ads showing
              Offstage(
                offstage: _bookMode && _pages.isNotEmpty,
                child: InAppWebView(
                  initialUrlRequest: URLRequest(url: WebUri(widget.series.url)),
                  initialSettings: _settings,
                  initialUserScripts: UnmodifiableListView<UserScript>([
                    UserScript(
                      source: WebScraper.stripAdsJs,
                      injectionTime: UserScriptInjectionTime.AT_DOCUMENT_START,
                    ),
                    if (widget.series.mode != 0)
                      UserScript(
                        source: ModeScripts.apply(widget.series.mode),
                        injectionTime:
                            UserScriptInjectionTime.AT_DOCUMENT_START,
                      ),
                  ]),
                  onWebViewCreated: (c) => _web = c,
                  onProgressChanged: (c, p) {
                    _progress.value = p >= 100 ? 0 : p / 100;
                  },
                  onUpdateVisitedHistory: (c, url, isReload) {
                    if (url != null) _cubit.onUrl(url.toString());
                  },
                  onLoadStop: (c, url) async {
                    _progress.value = 0;
                    if (url != null) _cubit.onUrl(url.toString());
                    final title = await c.getTitle();
                    if (title != null) _cubit.onPageTitle(title);
                    await _extractPages();
                    // Retry once more after brief delay for dynamic/lazy-loaded sites
                    Future.delayed(
                      const Duration(milliseconds: 1000),
                      _extractPages,
                    );
                  },
                  shouldOverrideUrlLoading: (c, action) async {
                    final uri = action.request.url?.uriValue;
                    if (uri == null) return NavigationActionPolicy.ALLOW;
                    if (uri.scheme != 'http' && uri.scheme != 'https') {
                      return NavigationActionPolicy.CANCEL;
                    }
                    if (action.isForMainFrame &&
                        !_cubit.isAllowedHost(uri.host)) {
                      _cubit.reportBlocked(uri.toString());
                      return NavigationActionPolicy.CANCEL;
                    }
                    return NavigationActionPolicy.ALLOW;
                  },
                  onCreateWindow: (c, action) async => false,
                  onPermissionRequest: (c, request) async => PermissionResponse(
                    resources: request.resources,
                    action: PermissionResponseAction.DENY,
                  ),
                ),
              ),

              // Native Book Reader
              if (_bookMode && _pages.isNotEmpty)
                Positioned.fill(
                  child: _BookPager(
                    urls: _pages,
                    initialPage: _currentPage,
                    vertical: _vertical,
                    rtl: _rtl,
                    pageController: _pageController!,
                    onPageChanged: (idx) {
                      setState(() => _currentPage = idx);
                      _saveProgress();
                    },
                    onTapCenter: () =>
                        setState(() => _showControls = !_showControls),
                    onNextChapter: _onNextChapter,
                    hasNext:
                        _nextChapterUrl != null || _cubit.stepUrl(1) != null,
                  ),
                )
              else if (_bookMode && _scraping)
                // Extraction loading state
                Positioned.fill(
                  child: Container(
                    color: Colors.black,
                    child: Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const SizedBox(
                            width: 36,
                            height: 36,
                            child: CircularProgressIndicator(
                              strokeWidth: 2.5,
                              color: Color(0xFF00B96B),
                            ),
                          ),
                          const SizedBox(height: 20),
                          const Text(
                            'Stripping ads & opening book...',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            widget.series.title,
                            style: const TextStyle(
                              color: Colors.white60,
                              fontSize: 13,
                            ),
                          ),
                          const SizedBox(height: 24),
                          TextButton.icon(
                            onPressed: () => setState(() => _bookMode = false),
                            icon: const Icon(Icons.public, size: 18),
                            label: const Text('View Web Page'),
                            style: TextButton.styleFrom(
                              foregroundColor: Colors.white70,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),

              // Brightness Dimmer Overlay
              Positioned.fill(
                child: IgnorePointer(
                  child: BlocBuilder<ReaderCubit, ReaderState>(
                    buildWhen: (a, b) => a.dim != b.dim,
                    builder: (context, s) =>
                        ColoredBox(color: Color.fromRGBO(0, 0, 0, s.dim)),
                  ),
                ),
              ),

              // Top & Bottom Immersive Controls Overlay
              if (_bookMode && _pages.isNotEmpty)
                _ReaderOverlay(
                  visible: _showControls,
                  title: widget.series.title,
                  chapter: _cubit.state.chapter,
                  currentPage: _currentPage,
                  totalPages: _pages.length,
                  onBack: _leave,
                  onSettings: _showSettings,
                  onPrevChapter: _onPrevChapter,
                  onNextChapter: _onNextChapter,
                  onSeekPage: (page) {
                    _pageController?.animateToPage(
                      page,
                      duration: const Duration(milliseconds: 300),
                      curve: Curves.easeInOutCubic,
                    );
                  },
                ),

              // Floating indicator when controls hidden
              if (_bookMode && _pages.isNotEmpty && !_showControls)
                Positioned(
                  bottom: 12,
                  right: 16,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.65),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      '${_currentPage + 1} / ${_pages.length}',
                      style: const TextStyle(
                        color: Colors.white70,
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                ),

              // Progress bar when loading Web View
              Positioned(
                top: 0,
                left: 0,
                right: 0,
                child: ValueListenableBuilder<double>(
                  valueListenable: _progress,
                  builder: (context, v, _) => v > 0
                      ? LinearProgressIndicator(
                          value: v,
                          minHeight: 2,
                          backgroundColor: Colors.transparent,
                          color: const Color(0xFF00B96B),
                        )
                      : const SizedBox.shrink(),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ------------------------------------------------------------------ book pager

class _BookPager extends StatefulWidget {
  const _BookPager({
    required this.urls,
    required this.initialPage,
    required this.vertical,
    required this.rtl,
    required this.pageController,
    required this.onPageChanged,
    required this.onTapCenter,
    required this.onNextChapter,
    required this.hasNext,
  });

  final List<String> urls;
  final int initialPage;
  final bool vertical;
  final bool rtl;
  final PageController pageController;
  final ValueChanged<int> onPageChanged;
  final VoidCallback onTapCenter;
  final VoidCallback onNextChapter;
  final bool hasNext;

  @override
  State<_BookPager> createState() => _BookPagerState();
}

class _BookPagerState extends State<_BookPager> {
  int get _count => widget.urls.length + 1; // + chapter end card

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _prefetch(widget.initialPage);
    });
  }

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
    final current = widget.pageController.hasClients
        ? (widget.pageController.page?.round() ?? widget.initialPage)
        : widget.initialPage;
    final target = current + delta;
    if (target < 0 || target >= _count) return;
    widget.pageController.animateToPage(
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
        controller: widget.pageController,
        scrollDirection: widget.vertical ? Axis.vertical : Axis.horizontal,
        reverse: flip,
        itemCount: _count,
        onPageChanged: (p) {
          widget.onPageChanged(math.min(p, widget.urls.length - 1));
          _prefetch(p);
        },
        itemBuilder: (context, i) => _AnimatedPage(
          controller: widget.pageController,
          index: i,
          vertical: widget.vertical,
          rtl: widget.rtl,
          child: i == widget.urls.length
              ? _ChapterEndCard(
                  onNextChapter: widget.onNextChapter,
                  hasNext: widget.hasNext,
                )
              : _PageImage(url: widget.urls[i]),
        ),
      ),
    );
  }
}

// ----------------------------------------------------------- 3D page animation

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
            opacity: 1 - v.abs() * 0.5,
            child: Transform.scale(scale: 1 - v.abs() * 0.1, child: child),
          );
        }
        final sign = rtl ? -1.0 : 1.0;
        final matrix = Matrix4.identity()
          ..setEntry(3, 2, 0.0012)
          ..rotateY(-v * sign * 1.15);
        return Opacity(
          opacity: 1 - v.abs() * 0.3,
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

// ------------------------------------------------------------------ page image

class _PageImage extends StatelessWidget {
  const _PageImage({required this.url});
  final String url;

  @override
  Widget build(BuildContext context) {
    return InteractiveViewer(
      minScale: 1.0,
      maxScale: 3.5,
      child: Center(
        child: CachedNetworkImage(
          imageUrl: url,
          cacheKey: PageCache.keyFor(url),
          cacheManager: PageCache.instance,
          fit: BoxFit.contain,
          fadeInDuration: Duration.zero,
          placeholder: (_, __) => const Center(
            child: SizedBox(
              width: 24,
              height: 24,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: Colors.white30,
              ),
            ),
          ),
          errorWidget: (_, __, ___) => const Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.broken_image, color: Colors.white38, size: 36),
                SizedBox(height: 8),
                Text(
                  'Failed to load page',
                  style: TextStyle(color: Colors.white38, fontSize: 12),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ------------------------------------------------------------ chapter end card

class _ChapterEndCard extends StatelessWidget {
  const _ChapterEndCard({
    required this.onNextChapter,
    required this.hasNext,
  });

  final VoidCallback onNextChapter;
  final bool hasNext;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.check_circle_outline,
              color: Color(0xFF00B96B),
              size: 54,
            ),
            const SizedBox(height: 16),
            const Text(
              'End of Chapter',
              style: TextStyle(
                color: Colors.white,
                fontSize: 20,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'You have finished reading this chapter.',
              style: TextStyle(color: Colors.white60, fontSize: 14),
            ),
            const SizedBox(height: 24),
            if (hasNext)
              FilledButton.icon(
                onPressed: onNextChapter,
                icon: const Icon(Icons.arrow_forward),
                label: const Text('Next Chapter'),
                style: FilledButton.styleFrom(
                  backgroundColor: const Color(0xFF00B96B),
                ),
              )
            else
              const Text(
                'No more chapters available',
                style: TextStyle(color: Colors.white38, fontSize: 13),
              ),
          ],
        ),
      ),
    );
  }
}

// ------------------------------------------------------------- reader controls

class _ReaderOverlay extends StatelessWidget {
  const _ReaderOverlay({
    required this.visible,
    required this.title,
    required this.chapter,
    required this.currentPage,
    required this.totalPages,
    required this.onBack,
    required this.onSettings,
    required this.onPrevChapter,
    required this.onNextChapter,
    required this.onSeekPage,
  });

  final bool visible;
  final String title;
  final String chapter;
  final int currentPage;
  final int totalPages;
  final VoidCallback onBack;
  final VoidCallback onSettings;
  final VoidCallback onPrevChapter;
  final VoidCallback onNextChapter;
  final ValueChanged<int> onSeekPage;

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      ignoring: !visible,
      child: AnimatedOpacity(
        opacity: visible ? 1.0 : 0.0,
        duration: const Duration(milliseconds: 200),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            // Top Bar
            Container(
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  colors: [Colors.black87, Colors.transparent],
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                ),
              ),
              child: SafeArea(
                bottom: false,
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 8,
                  ),
                  child: Row(
                    children: [
                      IconButton(
                        icon: const Icon(Icons.arrow_back, color: Colors.white),
                        onPressed: onBack,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 15,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            if (chapter.isNotEmpty)
                              Text(
                                chapter,
                                style: const TextStyle(
                                  color: Color(0xFF00B96B),
                                  fontSize: 12,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                          ],
                        ),
                      ),
                      IconButton(
                        icon: const Icon(
                          Icons.tune_rounded,
                          color: Colors.white,
                        ),
                        onPressed: onSettings,
                      ),
                    ],
                  ),
                ),
              ),
            ),

            // Bottom Bar
            Container(
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  colors: [Colors.transparent, Colors.black87],
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                ),
              ),
              child: SafeArea(
                top: false,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          IconButton(
                            icon: const Icon(
                              Icons.skip_previous_rounded,
                              color: Colors.white,
                            ),
                            onPressed: onPrevChapter,
                          ),
                          Text(
                            'Page ${currentPage + 1} of $totalPages',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          IconButton(
                            icon: const Icon(
                              Icons.skip_next_rounded,
                              color: Colors.white,
                            ),
                            onPressed: onNextChapter,
                          ),
                        ],
                      ),
                      if (totalPages > 1)
                        SliderTheme(
                          data: SliderTheme.of(context).copyWith(
                            activeTrackColor: const Color(0xFF00B96B),
                            inactiveTrackColor: Colors.white24,
                            thumbColor: const Color(0xFF00B96B),
                            trackHeight: 3,
                          ),
                          child: Slider(
                            value: currentPage.toDouble().clamp(
                                  0,
                                  (totalPages - 1).toDouble(),
                                ),
                            min: 0,
                            max: (totalPages - 1).toDouble(),
                            divisions: totalPages > 1 ? totalPages - 1 : 1,
                            onChanged: (v) => onSeekPage(v.round()),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
