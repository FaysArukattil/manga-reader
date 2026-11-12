import 'dart:async';

import 'package:equatable/equatable.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../data/auth_repository.dart';

enum AuthStatus { unknown, authenticated, unauthenticated }

class AuthState extends Equatable {
  const AuthState({
    this.status = AuthStatus.unknown,
    this.user,
    this.busy = false,
    this.error,
  });

  final AuthStatus status;
  final User? user;
  final bool busy;
  final String? error;

  AuthState copyWith({bool? busy, String? error, bool clearError = false}) =>
      AuthState(
        status: status,
        user: user,
        busy: busy ?? this.busy,
        error: clearError ? null : (error ?? this.error),
      );

  @override
  List<Object?> get props => [status, user?.uid, busy, error];
}

abstract class AuthEvent {
  const AuthEvent();
}

class _UserChanged extends AuthEvent {
  const _UserChanged(this.user);
  final User? user;
}

class AuthSignInRequested extends AuthEvent {
  const AuthSignInRequested();
}

class AuthSignInGuestRequested extends AuthEvent {
  const AuthSignInGuestRequested();
}

class AuthSignOutRequested extends AuthEvent {
  const AuthSignOutRequested();
}

class AuthDeleteRequested extends AuthEvent {
  const AuthDeleteRequested();
}

class AuthBloc extends Bloc<AuthEvent, AuthState> {
  AuthBloc(this._repo) : super(const AuthState()) {
    on<_UserChanged>((e, emit) {
      emit(
        e.user == null
            ? const AuthState(status: AuthStatus.unauthenticated)
            : AuthState(status: AuthStatus.authenticated, user: e.user),
      );
    });
    on<AuthSignInRequested>(_onSignIn);
    on<AuthSignInGuestRequested>(_onSignInGuest);
    on<AuthDeleteRequested>(_onDelete);
    on<AuthSignOutRequested>((e, emit) async {
      await _repo.signOut();
    });
    _sub = _repo.userChanges.listen((u) => add(_UserChanged(u)));
  }

  final AuthRepository _repo;
  StreamSubscription<User?>? _sub;

  Future<void> _onSignIn(AuthSignInRequested e, Emitter<AuthState> emit) async {
    if (state.busy) return;
    emit(state.copyWith(busy: true, clearError: true));
    try {
      await _repo.signInWithGoogle();
      emit(state.copyWith(busy: false));
    } on AuthCancelled {
      emit(state.copyWith(busy: false));
    } catch (e, st) {
      debugPrint('Auth error: $e\n$st');
      String msg = 'Sign-in failed. Check your connection and try again.';
      final str = e.toString();
      if (e is FirebaseAuthException) {
        msg = e.message ?? 'Authentication failed (${e.code}).';
      } else if (str.contains('10:') || str.contains('ApiException: 10')) {
        msg = 'Sign-in setup error: Keystore SHA-1 not registered in Firebase (ApiException 10).';
      } else if (str.contains('12500:') || str.contains('ApiException: 12500')) {
        msg = 'Sign-in failed: Google Play Services configuration error (12500).';
      } else if (str.contains('network_error')) {
        msg = 'Sign-in failed. Check your internet connection.';
      }
      emit(state.copyWith(busy: false, error: msg));
    }
  }

  Future<void> _onSignInGuest(
    AuthSignInGuestRequested e,
    Emitter<AuthState> emit,
  ) async {
    if (state.busy) return;
    emit(state.copyWith(busy: true, clearError: true));
    try {
      await _repo.signInAnonymously();
      emit(state.copyWith(busy: false));
    } catch (_) {
      emit(
        state.copyWith(
          busy: false,
          error: 'Guest sign-in failed. Check connection.',
        ),
      );
    }
  }

  Future<void> _onDelete(AuthDeleteRequested e, Emitter<AuthState> emit) async {
    if (state.busy) return;
    emit(state.copyWith(busy: true, clearError: true));
    try {
      await _repo.deleteAccount();
      // authStateChanges moves the app to the sign-in screen.
    } on AuthCancelled {
      emit(state.copyWith(busy: false, error: 'Account deletion cancelled.'));
    } catch (_) {
      emit(
        state.copyWith(
          busy: false,
          error: 'Could not delete the account. Sign out, sign in and retry.',
        ),
      );
    }
  }

  @override
  Future<void> close() {
    _sub?.cancel();
    return super.close();
  }
}
