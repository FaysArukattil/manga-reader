import 'dart:collection';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:url_launcher/url_launcher.dart';

import '../blocs/reader_cubit.dart';
import '../data/library_repository.dart';
import '../models/series.dart';
import '../services/anilist_service.dart';
import '../services/thumbnail_store.dart';
import 'ad_block.dart';
import 'mode_scripts.dart';

/// Full-screen reader: one WebView at a time, restored from saved state.
///
/// Battery/perf notes:
///  - a single WebView exists only while this page is open;
///  - no scroll listeners: scroll position is read once when leaving/pausing;
///  - WebView timers are paused while the app is in the background;
///  - ads/trackers are blocked before they load.
class ReaderPage extends StatefulWidget {
  const ReaderPage({super.key, required this.series});

  final Series series;

  static Future<void> open(BuildContext context, Series series) {
    return Navigator.of(
      context,
    ).push(MaterialPageRoute<void>(builder: (_) => ReaderPage(series: series)));
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
  bool _restored = false;
  bool _leaving = false;
  double _lastScroll = 0;

  @override
  void initState() {
    super.initState();
    _thumbs = context.read<ThumbnailStore>();
    _cubit = ReaderCubit(
      series: widget.series,
      library: context.read<LibraryRepository>(),
      anilist: context.read<AniListService>(),
    );
    _lastScroll = widget.series.scroll;
    _settings = InAppWebViewSettings(
      javaScriptEnabled: true,
      javaScriptCanOpenWindowsAutomatically: false,
      supportMultipleWindows: true, // so onCreateWindow can block popups
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
    _progress.dispose();
    _cubit.close();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused) {
      _saveNow();
      try {
        _web?.pauseTimers();
      } catch (_) {}
    } else if (state == AppLifecycleState.resumed) {
      try {
        _web?.resumeTimers();
      } catch (_) {}
    }
  }

  Future<void> _saveNow() async {
    final scroll = await _readScroll();
    await _cubit.flush(scroll: scroll);
  }

  Future<double> _readScroll() async {
    final web = _web;
    if (web == null) return _lastScroll;
    try {
      final v = await web.evaluateJavascript(
        source:
            '(function(){var e=document.documentElement;'
            'var h=e.scrollHeight-window.innerHeight;'
            'return h>0?window.scrollY/h:0;})()',
      );
      if (v is num) {
        _lastScroll = math.min(1.0, math.max(0.0, v.toDouble()));
      }
    } catch (_) {}
    return _lastScroll;
  }

  Future<void> _restoreScroll() async {
    final pct = widget.series.scroll;
    if (pct < 0.01) return;
    // Two gentle attempts; only scrolls forward so it never fights the user.
    for (final delay in const [450, 1500]) {
      await Future<void>.delayed(Duration(milliseconds: delay));
      if (!mounted) return;
      try {
        await _web?.evaluateJavascript(
          source:
              '(function(){var e=document.documentElement;'
              'var h=Math.max(1,e.scrollHeight-window.innerHeight);'
              'var t=h*$pct;if(window.scrollY<t-50){window.scrollTo(0,t);}})()',
        );
      } catch (_) {}
    }
  }

  Future<void> _applyModeNow() async {
    try {
      await _web?.evaluateJavascript(
        source: ModeScripts.apply(_cubit.state.mode),
      );
    } catch (_) {}
  }

  Future<void> _syncModeUserScript() async {
    final web = _web;
    if (web == null) return;
    try {
      await web.removeAllUserScripts();
      await web.addUserScript(
        userScript: UserScript(
          source: ModeScripts.apply(_cubit.state.mode),
          injectionTime: UserScriptInjectionTime.AT_DOCUMENT_START,
        ),
      );
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

  Future<void> _onBack() async {
    if (_leaving) return;
    final web = _web;
    if (web != null && await web.canGoBack()) {
      await web.goBack();
      return;
    }
    await _leave();
  }

  Future<void> _leave() async {
    if (_leaving) return;
    _leaving = true;
    final scroll = await _readScroll();
    await _captureThumbnail();
    await _cubit.flush(scroll: scroll);
    if (mounted) Navigator.of(context).pop();
  }

  void _loadUrl(String url) {
    _web?.loadUrl(urlRequest: URLRequest(url: WebUri(url)));
  }

  void _showMenu() {
    final prev = _cubit.stepUrl(-1);
    final next = _cubit.stepUrl(1);
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (sheetContext) => BlocProvider.value(
        value: _cubit,
        child: _ReaderMenu(
          title: widget.series.title,
          host: widget.series.host,
          onPrev: prev == null
              ? null
              : () {
                  Navigator.pop(sheetContext);
                  _loadUrl(prev);
                },
          onNext: next == null
              ? null
              : () {
                  Navigator.pop(sheetContext);
                  _loadUrl(next);
                },
          onEditChapter: () {
            Navigator.pop(sheetContext);
            _editChapter();
          },
          onReload: () {
            Navigator.pop(sheetContext);
            _web?.reload();
          },
          onBrowser: () {
            Navigator.pop(sheetContext);
            launchUrl(
              Uri.parse(_cubit.currentUrl),
              mode: LaunchMode.externalApplication,
            );
          },
          onExit: () {
            Navigator.pop(sheetContext);
            _leave();
          },
        ),
      ),
    );
  }

  Future<void> _editChapter() async {
    final controller = TextEditingController(text: _cubit.state.chapter);
    final result = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Current chapter'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(hintText: 'e.g. Ch 124'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, controller.text),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (result != null) _cubit.setChapter(result);
  }

  @override
  Widget build(BuildContext context) {
    final series = widget.series;
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _onBack();
      },
      child: BlocProvider.value(
        value: _cubit,
        child: MultiBlocListener(
          listeners: [
            BlocListener<ReaderCubit, ReaderState>(
              listenWhen: (a, b) => a.mode != b.mode,
              listener: (context, state) {
                _syncModeUserScript();
                _applyModeNow();
              },
            ),
            BlocListener<ReaderCubit, ReaderState>(
              listenWhen: (a, b) => b.blocked != null && a.blocked != b.blocked,
              listener: (context, state) {
                final blocked = state.blocked;
                if (blocked == null) return;
                final host = Uri.tryParse(blocked)?.host ?? blocked;
                ScaffoldMessenger.of(context)
                  ..hideCurrentSnackBar()
                  ..showSnackBar(
                    SnackBar(
                      content: Text('Blocked redirect to $host'),
                      action: SnackBarAction(
                        label: 'Allow',
                        onPressed: () {
                          _cubit.allowHost(host);
                          _loadUrl(blocked);
                        },
                      ),
                    ),
                  );
                _cubit.clearBlocked();
              },
            ),
          ],
          child: Scaffold(
            backgroundColor: Colors.black,
            body: Stack(
              children: [
                Positioned.fill(
                  child: InAppWebView(
                    initialUrlRequest: URLRequest(url: WebUri(series.url)),
                    initialSettings: _settings,
                    initialUserScripts: series.mode == 0
                        ? null
                        : UnmodifiableListView<UserScript>([
                            UserScript(
                              source: ModeScripts.apply(series.mode),
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
                      _applyModeNow();
                      final title = await c.getTitle();
                      if (title != null) _cubit.onPageTitle(title);
                      if (!_restored) {
                        _restored = true;
                        _restoreScroll();
                      }
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
                    onPermissionRequest: (c, request) async =>
                        PermissionResponse(
                          resources: request.resources,
                          action: PermissionResponseAction.DENY,
                        ),
                  ),
                ),
                // Brightness dimmer (GPU-cheap overlay, ignores touches).
                Positioned.fill(
                  child: IgnorePointer(
                    child: BlocBuilder<ReaderCubit, ReaderState>(
                      buildWhen: (a, b) => a.dim != b.dim,
                      builder: (context, s) =>
                          ColoredBox(color: Color.fromRGBO(0, 0, 0, s.dim)),
                    ),
                  ),
                ),
                Positioned(
                  top: 0,
                  left: 0,
                  right: 0,
                  child: ValueListenableBuilder<double>(
                    valueListenable: _progress,
                    builder: (context, v, _) => v > 0
                        ? LinearProgressIndicator(value: v, minHeight: 2)
                        : const SizedBox.shrink(),
                  ),
                ),
                Positioned(
                  right: 10,
                  bottom: 24,
                  child: SafeArea(
                    child: Opacity(
                      opacity: 0.6,
                      child: FloatingActionButton.small(
                        heroTag: null,
                        onPressed: _showMenu,
                        child: const Icon(Icons.tune),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ReaderMenu extends StatelessWidget {
  const _ReaderMenu({
    required this.title,
    required this.host,
    required this.onPrev,
    required this.onNext,
    required this.onEditChapter,
    required this.onReload,
    required this.onBrowser,
    required this.onExit,
  });

  final String title;
  final String host;
  final VoidCallback? onPrev;
  final VoidCallback? onNext;
  final VoidCallback onEditChapter;
  final VoidCallback onReload;
  final VoidCallback onBrowser;
  final VoidCallback onExit;

  @override
  Widget build(BuildContext context) {
    final cubit = context.read<ReaderCubit>();
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
        child: BlocBuilder<ReaderCubit, ReaderState>(
          builder: (context, s) => Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.titleMedium,
              ),
              Text(host, style: Theme.of(context).textTheme.bodySmall),
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: SegmentedButton<int>(
                  segments: const [
                    ButtonSegment(
                      value: 0,
                      label: Text('Off'),
                      icon: Icon(Icons.light_mode_outlined),
                    ),
                    ButtonSegment(
                      value: 1,
                      label: Text('Dark'),
                      icon: Icon(Icons.dark_mode_outlined),
                    ),
                    ButtonSegment(
                      value: 2,
                      label: Text('Warm'),
                      icon: Icon(Icons.wb_twilight),
                    ),
                  ],
                  selected: {s.mode},
                  onSelectionChanged: (v) => cubit.setMode(v.first),
                ),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  const Icon(Icons.brightness_low, size: 20),
                  Expanded(
                    child: Slider(
                      value: s.dim,
                      min: 0,
                      max: 0.7,
                      onChanged: cubit.setDim,
                      onChangeEnd: (_) => cubit.commitDim(),
                    ),
                  ),
                ],
              ),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: onPrev,
                      icon: const Icon(Icons.chevron_left),
                      label: const Text('Previous'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: onNext,
                      icon: const Icon(Icons.chevron_right),
                      label: const Text('Next'),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.bookmark_outline),
                title: Text(s.chapter.isEmpty ? 'Set chapter' : s.chapter),
                subtitle: const Text('Tap to edit current chapter'),
                onTap: onEditChapter,
              ),
              Row(
                children: [
                  TextButton.icon(
                    onPressed: onReload,
                    icon: const Icon(Icons.refresh),
                    label: const Text('Reload'),
                  ),
                  TextButton.icon(
                    onPressed: onBrowser,
                    icon: const Icon(Icons.open_in_browser),
                    label: const Text('Browser'),
                  ),
                  const Spacer(),
                  FilledButton.tonalIcon(
                    onPressed: onExit,
                    icon: const Icon(Icons.grid_view_rounded),
                    label: const Text('Shelf'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
