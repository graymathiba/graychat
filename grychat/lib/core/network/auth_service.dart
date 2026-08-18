import 'package:firebase_auth/firebase_auth.dart';

class AuthService {
  FirebaseAuth get _auth => FirebaseAuth.instance;

  User? get currentUser => _auth.currentUser;

  Stream<User?> get authStateChanges => _auth.authStateChanges();

  bool get isAvailable => true;

  Future<String?> get accessToken async {
    final user = _auth.currentUser;
    if (user == null) return null;
    return user.getIdToken();
  }

  Future<UserCredential> signUp({
    required String email,
    required String password,
    required String username,
    String firstName = '',
    String lastName = '',
  }) async {
    final credential = await _auth.createUserWithEmailAndPassword(
      email: email,
      password: password,
    );

    await credential.user?.updateDisplayName('$firstName $lastName'.trim());

    return credential;
  }

  Future<UserCredential> signIn({
    required String email,
    required String password,
  }) async {
    return _auth.signInWithEmailAndPassword(
      email: email,
      password: password,
    );
  }

  Future<void> signOut() async {
    await _auth.signOut();
  }

  Future<void> resetPassword(String email) async {
    await _auth.sendPasswordResetEmail(email: email);
  }

  String? getUsername() {
    return currentUser?.displayName;
  }

  String? getDisplayName() {
    return currentUser?.displayName;
  }
}

final authService = AuthService();
