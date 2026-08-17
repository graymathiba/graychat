import 'package:firebase_auth/firebase_auth.dart';

class AuthService {
  FirebaseAuth? get _auth {
    try {
      return FirebaseAuth.instance;
    } catch (_) {
      return null;
    }
  }

  User? get currentUser => _auth?.currentUser;

  Stream<User?> get authStateChanges {
    final auth = _auth;
    if (auth == null) return Stream<User?>.empty();
    return auth.authStateChanges();
  }

  bool get isAvailable => _auth != null;

  Future<UserCredential> signUp({
    required String email,
    required String password,
    required String username,
  }) async {
    final auth = _auth;
    if (auth == null) throw Exception('Firebase Auth not available');
    final cred = await auth.createUserWithEmailAndPassword(
      email: email,
      password: password,
    );
    await cred.user?.updateDisplayName(username);
    return cred;
  }

  Future<UserCredential> signIn({
    required String email,
    required String password,
  }) async {
    final auth = _auth;
    if (auth == null) throw Exception('Firebase Auth not available');
    return auth.signInWithEmailAndPassword(
      email: email,
      password: password,
    );
  }

  Future<void> signOut() async {
    final auth = _auth;
    if (auth != null) await auth.signOut();
  }

  Future<void> resetPassword(String email) async {
    final auth = _auth;
    if (auth == null) throw Exception('Firebase Auth not available');
    await auth.sendPasswordResetEmail(email: email);
  }

  Future<void> updatePassword(String newPassword) async {
    await _auth?.currentUser?.updatePassword(newPassword);
  }

  String? getUsername() {
    return _auth?.currentUser?.displayName;
  }
}

final authService = AuthService();
