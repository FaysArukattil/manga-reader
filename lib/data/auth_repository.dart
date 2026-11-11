import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_sign_in/google_sign_in.dart';

class AuthCancelled implements Exception {
  const AuthCancelled();
}

class AuthRepository {
  AuthRepository({FirebaseAuth? auth, GoogleSignIn? google})
      : _auth = auth ?? FirebaseAuth.instance,
        _google = google ??
            GoogleSignIn(
              serverClientId:
                  '356770181005-2bs6ir063l5j5poikie5qtkmssma9h0s.apps.googleusercontent.com',
            );

  final FirebaseAuth _auth;
  final GoogleSignIn _google;

  Stream<User?> get userChanges => _auth.authStateChanges();

  Future<void> signInWithGoogle() async {
    final account = await _google.signIn();
    if (account == null) throw const AuthCancelled();
    final tokens = await account.authentication;
    final credential = GoogleAuthProvider.credential(
      accessToken: tokens.accessToken,
      idToken: tokens.idToken,
    );
    await _auth.signInWithCredential(credential);
  }

  Future<void> signInAnonymously() async {
    await _auth.signInAnonymously();
  }

  /// Permanently deletes the Firebase account. Re-authenticates with Google
  /// if Firebase asks for a recent login.
  Future<void> deleteAccount() async {
    final user = _auth.currentUser;
    if (user == null) return;
    try {
      await user.delete();
    } on FirebaseAuthException catch (e) {
      if (e.code != 'requires-recent-login') rethrow;
      final account = await _google.signIn();
      if (account == null) throw const AuthCancelled();
      final tokens = await account.authentication;
      await user.reauthenticateWithCredential(
        GoogleAuthProvider.credential(
          accessToken: tokens.accessToken,
          idToken: tokens.idToken,
        ),
      );
      await user.delete();
    }
    try {
      await _google.signOut();
    } catch (_) {}
  }

  Future<void> signOut() async {
    await _google.signOut();
    await _auth.signOut();
  }
}
