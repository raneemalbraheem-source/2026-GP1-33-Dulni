import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';

/// Firebase operations used by sign-in, sign-up, and the profile page.
class AuthService {
  AuthService({FirebaseAuth? auth, FirebaseFirestore? firestore})
      : _auth = auth ?? FirebaseAuth.instance,
        _firestore = firestore ?? FirebaseFirestore.instance;

  final FirebaseAuth _auth;
  final FirebaseFirestore _firestore;

  CollectionReference<Map<String, dynamic>> get _users =>
      _firestore.collection('User');

  Future<UserCredential> signIn({
    required String email,
    required String password,
  }) {
    return _auth.signInWithEmailAndPassword(
      email: email.trim(),
      password: password,
    );
  }

  Future<UserCredential> createAccount({
    required String fullName,
    required String email,
    required String password,
  }) async {
    final credential = await _auth.createUserWithEmailAndPassword(
      email: email.trim(),
      password: password,
    );

    final uid = credential.user!.uid;
    final now = FieldValue.serverTimestamp();
    await _users.doc(uid).set({
      'fullName': fullName.trim(),
      'createdAt': now,
      'updatedAt': now,
      'accountStatus': 'active',
      'voicePersona': 'default',
      'speechRate': 1.0,
      'instructionFrequency': 'normal',
      'alertRepetitionCount': 0,
      'vibrationEnabled': true,
    });

    return credential;
  }

  Future<void> sendPasswordReset(String email) {
    return _auth.sendPasswordResetEmail(email: email.trim());
  }

  User? get currentUser => _auth.currentUser;

  Future<String?> getFullName() async {
    final user = _auth.currentUser;
    if (user == null) return null;
    final snapshot = await _users.doc(user.uid).get();
    return snapshot.data()?['fullName'] as String?;
  }

  Future<void> updateFullName(String fullName) async {
    final user = _requireCurrentUser();
    await _users.doc(user.uid).update({
      'fullName': fullName.trim(),
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  Future<void> changePassword({
    required String currentPassword,
    required String newPassword,
  }) async {
    final user = _requireCurrentUser();
    await _reauthenticate(user, currentPassword);
    await user.updatePassword(newPassword);
  }

  Future<void> signOut() => _auth.signOut();

  /// Deletes the current user's profile document and Firebase Auth account.
  /// Reauthentication is required before any data is removed.
  Future<void> deleteAccount({required String password}) async {
    final user = _requireCurrentUser();
    await _reauthenticate(user, password);

    // This project currently stores the user's account data in this one
    // document. Add any future user-owned collections here before release.
    await _users.doc(user.uid).delete();
    await user.delete();
  }

  User _requireCurrentUser() {
    final user = _auth.currentUser;
    if (user == null) {
      throw FirebaseAuthException(
        code: 'no-current-user',
        message: 'No signed-in user is available.',
      );
    }
    return user;
  }

  Future<void> _reauthenticate(User user, String password) async {
    final email = user.email;
    if (email == null || email.isEmpty) {
      throw FirebaseAuthException(
        code: 'email-not-available',
        message: 'The signed-in account has no email address.',
      );
    }
    await user.reauthenticateWithCredential(
      EmailAuthProvider.credential(email: email, password: password),
    );
  }
}
