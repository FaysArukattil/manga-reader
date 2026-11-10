import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:provider/provider.dart';

import 'blocs/auth_bloc.dart';
import 'blocs/library_bloc.dart';
import 'data/auth_repository.dart';
import 'data/library_repository.dart';
import 'services/anilist_service.dart';
import 'services/share_service.dart';
import 'services/thumbnail_store.dart';
import 'ui/library_page.dart';
import 'ui/login_page.dart';

class ShelfmarkApp extends StatelessWidget {
  const ShelfmarkApp({super.key, required this.thumbs, required this.share});

  final ThumbnailStore thumbs;
  final ShareService share;

  static ThemeData _theme(Brightness brightness) => ThemeData(
    useMaterial3: true,
    colorSchemeSeed: const Color(0xFF00B96B),
    brightness: brightness,
  );

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider<ShareService>.value(
      value: share,
      child: MultiRepositoryProvider(
        providers: [
          RepositoryProvider<AuthRepository>(create: (_) => AuthRepository()),
          RepositoryProvider<AniListService>(create: (_) => AniListService()),
          RepositoryProvider<ThumbnailStore>.value(value: thumbs),
        ],
        child: BlocProvider<AuthBloc>(
          create: (c) => AuthBloc(c.read<AuthRepository>()),
          child: MaterialApp(
            title: 'Shelfmark',
            debugShowCheckedModeBanner: false,
            theme: _theme(Brightness.light),
            darkTheme: _theme(Brightness.dark),
            themeMode: ThemeMode.system,
            // Library providers sit ABOVE the Navigator so every pushed route
            // (reader, sheets, dialogs) can read them.
            builder: (context, child) =>
                _LibraryScope(child: child ?? const SizedBox.shrink()),
            home: const _AuthGate(),
          ),
        ),
      ),
    );
  }
}

class _LibraryScope extends StatelessWidget {
  const _LibraryScope({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return BlocSelector<AuthBloc, AuthState, String?>(
      selector: (s) => s.user?.uid,
      builder: (context, uid) {
        if (uid == null) return child;
        return RepositoryProvider<LibraryRepository>(
          key: ValueKey(uid),
          create: (_) => LibraryRepository(uid),
          child: BlocProvider<LibraryBloc>(
            create: (c) => LibraryBloc(
              c.read<LibraryRepository>(),
              c.read<AniListService>(),
              c.read<ThumbnailStore>(),
            )..add(const LibraryStarted()),
            child: child,
          ),
        );
      },
    );
  }
}

class _AuthGate extends StatelessWidget {
  const _AuthGate();

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<AuthBloc, AuthState>(
      buildWhen: (a, b) => a.status != b.status,
      builder: (context, state) {
        switch (state.status) {
          case AuthStatus.unknown:
            return const Scaffold(
              body: Center(child: CircularProgressIndicator()),
            );
          case AuthStatus.unauthenticated:
            return const LoginPage();
          case AuthStatus.authenticated:
            return const LibraryPage();
        }
      },
    );
  }
}
