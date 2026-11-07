import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_sign_in/google_sign_in.dart';

class AuthService extends ChangeNotifier {
  static final AuthService _instance = AuthService._internal();
  static AuthService get instance => _instance;

  FirebaseAuth? get _auth {
    try {
      if (Firebase.apps.isNotEmpty) {
        return FirebaseAuth.instance;
      }
    } catch (_) {}
    return null;
  }

  final GoogleSignIn _googleSignIn = GoogleSignIn(
    scopes: ['email', 'profile'],
  );

  bool _isSigningIn = false;
  String? _authError;

  AuthService._internal() {
    try {
      if (Firebase.apps.isNotEmpty) {
        _auth?.authStateChanges().listen((_) {
          notifyListeners();
        });
      }
    } catch (_) {}
  }

  bool get isSigningIn => _isSigningIn;
  String? get authError => _authError;
  User? get currentUser => _auth?.currentUser;
  bool get isAuthenticated => _auth?.currentUser != null;
  Stream<User?> get authStateChanges =>
      _auth?.authStateChanges() ?? const Stream.empty();

  String get displayName =>
      currentUser?.displayName ??
      currentUser?.email?.split('@').first ??
      'Guest Reader';

  String get email => currentUser?.email ?? 'Not signed in';

  String? get photoUrl => currentUser?.photoURL;

  Future<UserCredential?> signInWithGoogle() async {
    final auth = _auth;
    if (auth == null) {
      _authError = 'Firebase is not initialized';
      notifyListeners();
      return null;
    }

    _isSigningIn = true;
    _authError = null;
    notifyListeners();

    try {
      final GoogleSignInAccount? googleUser = await _googleSignIn.signIn();
      if (googleUser == null) {
        // User cancelled the sign-in flow
        _isSigningIn = false;
        notifyListeners();
        return null;
      }

      final GoogleSignInAuthentication googleAuth = await googleUser.authentication;

      if (googleAuth.idToken == null && googleAuth.accessToken == null) {
        throw 'No identity token or access token received from Google.';
      }

      final OAuthCredential credential = GoogleAuthProvider.credential(
        accessToken: googleAuth.accessToken,
        idToken: googleAuth.idToken,
      );

      final UserCredential userCredential =
          await auth.signInWithCredential(credential);

      _isSigningIn = false;
      _authError = null;
      notifyListeners();
      return userCredential;
    } catch (e) {
      debugPrint('[AUTH] Google Sign-In error: $e');
      final errStr = e.toString();
      if (errStr.contains('10') || errStr.contains('developer_error')) {
        _authError = 'Google Sign-In configuration error. Please ensure the Google provider is enabled in Firebase Console.';
      } else if (errStr.contains('network') || errStr.contains('7:')) {
        _authError = 'Network error during Google Sign-In. Please check your internet connection.';
      } else {
        _authError = 'Sign-in failed: $errStr';
      }
      _isSigningIn = false;
      notifyListeners();
      return null;
    }
  }

  Future<UserCredential?> signInWithEmail(String email, String password) async {
    final auth = _auth;
    if (auth == null) {
      _authError = 'Firebase is not initialized';
      notifyListeners();
      return null;
    }

    _isSigningIn = true;
    _authError = null;
    notifyListeners();

    try {
      final credential = await auth.signInWithEmailAndPassword(
        email: email.trim(),
        password: password,
      );
      _isSigningIn = false;
      notifyListeners();
      return credential;
    } catch (e) {
      _authError = e.toString();
      _isSigningIn = false;
      notifyListeners();
      return null;
    }
  }

  Future<UserCredential?> signUpWithEmail(String email, String password) async {
    final auth = _auth;
    if (auth == null) {
      _authError = 'Firebase is not initialized';
      notifyListeners();
      return null;
    }

    _isSigningIn = true;
    _authError = null;
    notifyListeners();

    try {
      final credential = await auth.createUserWithEmailAndPassword(
        email: email.trim(),
        password: password,
      );
      _isSigningIn = false;
      notifyListeners();
      return credential;
    } catch (e) {
      _authError = e.toString();
      _isSigningIn = false;
      notifyListeners();
      return null;
    }
  }

  Future<void> signOut() async {
    try {
      await _googleSignIn.signOut();
    } catch (_) {}
    try {
      await _auth?.signOut();
    } catch (_) {}
    notifyListeners();
  }
}
