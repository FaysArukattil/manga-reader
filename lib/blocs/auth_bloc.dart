import 'dart:async';

import 'package:equatable/equatable.dart';
import 'package:firebase_auth/firebase_auth.dart';
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

class AuthSignOutRequested extends AuthEvent {
  const AuthSignOutRequested();
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
    } catch (_) {
      emit(
        state.copyWith(
          busy: false,
          error: 'Sign-in failed. Check your connection and try again.',
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
