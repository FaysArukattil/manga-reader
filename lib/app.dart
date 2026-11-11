import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:provider/provider.dart';

import 'blocs/auth_bloc.dart';
import 'blocs/library_bloc.dart';
import 'data/auth_repository.dart';
import 'data/library_repository.dart';
import 'services/anilist_service.dart';
import 'services/mangadex_service.dart';
import 'services/page_cache.dart';
import 'services/scrape/scrape_service.dart';
import 'services/share_service.dart';
import 'services/thumbnail_store.dart';
import 'theme/app_theme.dart';
import 'ui/library_page.dart';
import 'ui/login_page.dart';

class ShelfmarkApp extends StatelessWidget {
  const ShelfmarkApp({
    super.key,
    required this.thumbs,
    required this.share,
    required this.chapterStore,
  });

  final ThumbnailStore thumbs;
  final ShareService share;
  final ChapterStore chapterStore;

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider<ShareService>.value(
      value: share,
      child: MultiRepositoryProvider(
        providers: [
          RepositoryProvider<AuthRepository>(create: (_) => AuthRepository()),
          RepositoryProvider<AniListService>(create: (_) => AniListService()),
          RepositoryProvider<MangaDexService>(create: (_) => MangaDexService()),
          RepositoryProvider<ScrapeService>(create: (_) => ScrapeService()),
          RepositoryProvider<ThumbnailStore>.value(value: thumbs),
          RepositoryProvider<ChapterStore>.value(value: chapterStore),
        ],
        child: BlocProvider<AuthBloc>(
          create: (c) => AuthBloc(c.read<AuthRepository>()),
          child: MaterialApp(
            title: 'Shelfmark',
            debugShowCheckedModeBanner: false,
            theme: AppTheme.lightTheme,
            darkTheme: AppTheme.darkTheme,
            themeMode: ThemeMode.system,
            // Library providers sit ABOVE the Navigator so every pushed route
            // (readers, sheets, dialogs) can read them.
            builder: (context, child) =>
                _LibraryScope(child: child ?? const SizedBox.shrink()),
            home: const _AuthGate(),
          ),
        ),
      ),
    );
  }
}

class _AuthGate extends StatelessWidget {
  const _AuthGate();

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<AuthBloc, AuthState>(
      builder: (context, state) {
        if (state.status == AuthStatus.authenticated && state.user != null) {
          return const LibraryPage();
        }
        return const LoginPage();
      },
    );
  }
}

/// Holds the single [LibraryBloc] instance for the lifetime of the authenticated
/// session, keyed to the current Firebase user id.
class _LibraryScope extends StatefulWidget {
  const _LibraryScope({required this.child});

  final Widget child;

  @override
  State<_LibraryScope> createState() => _LibraryScopeState();
}

class _LibraryScopeState extends State<_LibraryScope> {
  LibraryRepository? _repo;
  LibraryBloc? _bloc;
  String? _userId;

  void _syncBloc(String? nextUserId) {
    if (_userId == nextUserId) return;
    _userId = nextUserId;
    _bloc?.close();
    if (nextUserId == null) {
      _repo = null;
      _bloc = null;
    } else {
      final repo = LibraryRepository(nextUserId);
      _repo = repo;
      _bloc = LibraryBloc(
        repo,
        context.read<AniListService>(),
        context.read<ThumbnailStore>(),
        context.read<MangaDexService>(),
        context.read<ScrapeService>(),
      )..add(const LibraryStarted());
    }
  }

  @override
  void dispose() {
    _bloc?.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return BlocListener<AuthBloc, AuthState>(
      listenWhen: (prev, curr) => prev.user?.uid != curr.user?.uid,
      listener: (context, state) {
        setState(() => _syncBloc(state.user?.uid));
      },
      child: Builder(
        builder: (context) {
          final auth = context.watch<AuthBloc>().state;
          if (_bloc == null && auth.user != null) {
            _syncBloc(auth.user?.uid);
          }
          final bloc = _bloc;
          final repo = _repo;
          if (bloc == null || repo == null) return widget.child;
          return MultiRepositoryProvider(
            providers: [
              RepositoryProvider<LibraryRepository>.value(value: repo),
            ],
            child: BlocProvider<LibraryBloc>.value(
              value: bloc,
              child: widget.child,
            ),
          );
        },
      ),
    );
  }
}
