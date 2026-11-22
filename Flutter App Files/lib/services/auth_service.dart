import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';
import 'package:http/http.dart' as http;

/// Firebase operations used by sign-in, sign-up, and the profile page.
class AuthService {
  AuthService({FirebaseAuth? auth, FirebaseFirestore? firestore})
    : _auth = auth ?? FirebaseAuth.instance,
      _firestore = firestore ?? FirebaseFirestore.instance;
      static const String _authApiBaseUrl ='http://10.0.2.2:3000/api/auth';

  final FirebaseAuth _auth;
  final FirebaseFirestore _firestore;

  CollectionReference<Map<String, dynamic>> get _users =>
      _firestore.collection('User');

  static const String _pendingEmailKey = 'pendingEmailLinkEmail';
  static const String _pendingNameKey = 'pendingEmailLinkName';
  static const String _pendingActionKey = 'pendingEmailLinkAction';

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
      'updatedAt': now,
      'accountStatus': 'active',
      'voicePersona': 'sara',
      'speechRate': 1.0,
      'instructionFrequency': 'normal',
      'alertRepetitionCount': 0,
      'vibrationEnabled': true,
    });

    return credential;
  }


Future<void> sendSignUpLink({
  required String fullName,
  required String email,
}) async {
  final normalizedEmail = email.trim();

  final actionCodeSettings = ActionCodeSettings(
    url: 'https://dulni-d2dd1.web.app',
    handleCodeInApp: true,
    androidPackageName: 'com.example.dulni_project',
    androidInstallApp: false,
  );

  await _auth.sendSignInLinkToEmail(
    email: normalizedEmail,
    actionCodeSettings: actionCodeSettings,
  );

  final prefs = await SharedPreferences.getInstance();

  await prefs.setString(_pendingEmailKey, normalizedEmail);
  await prefs.setString(_pendingNameKey, fullName.trim());
  await prefs.remove(_pendingActionKey);
}


  Future<String?> getPendingEmail() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_pendingEmailKey);
  }

  Future<String?> getPendingName() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_pendingNameKey);
  }

  Future<bool> isEmailSignInLink(String emailLink) async {
    return _auth.isSignInWithEmailLink(emailLink);
  }

  Future<UserCredential> completeEmailLinkSignIn({
    required String email,
    required String emailLink,
  }) async {
    if (!_auth.isSignInWithEmailLink(emailLink)) {
      throw FirebaseAuthException(
        code: 'invalid-email-link',
        message: 'The provided link is not a valid email sign-in link.',
      );
    }

    return _auth.signInWithEmailLink(
      email: email.trim(),
      emailLink: emailLink,
    );
  }

  Future<void> createUserProfileIfMissing({
    required String fullName,
  }) async {
    final user = _requireCurrentUser();
    final profile = _users.doc(user.uid);
    final snapshot = await profile.get();

    // لا نستبدل إعدادات المستخدم إذا كان ملفه موجودًا.
    if (snapshot.exists) return;

    await profile.set({
      'fullName': fullName.trim(),
      'updatedAt': FieldValue.serverTimestamp(),
      'accountStatus': 'active',
      'voicePersona': 'sara',
      'speechRate': 1.0,
      'instructionFrequency': 'normal',
      'alertRepetitionCount': 0,
      'vibrationEnabled': true,
    });
  }

  Future<void> clearPendingEmailLinkData() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_pendingEmailKey);
    await prefs.remove(_pendingNameKey);
    await prefs.remove(_pendingActionKey);
  }

  Future<String?> getPendingEmailLinkAction() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_pendingActionKey);
  }

  Future<void> sendAccountDeletionLink() async {
    final email = _requireCurrentUser().email;
    if (email == null || email.trim().isEmpty) {
      throw FirebaseAuthException(
        code: 'email-not-available',
        message: 'The signed-in account has no email address.',
      );
    }

    final normalizedEmail = email.trim().toLowerCase();
    final actionCodeSettings = ActionCodeSettings(
      url: 'https://dulni-d2dd1.web.app',
      handleCodeInApp: true,
      androidPackageName: 'com.example.dulni_project',
      androidInstallApp: false,
    );

    await _auth.sendSignInLinkToEmail(
      email: normalizedEmail,
      actionCodeSettings: actionCodeSettings,
    );

    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_pendingEmailKey, normalizedEmail);
    await prefs.remove(_pendingNameKey);
    await prefs.setString(_pendingActionKey, 'deleteAccount');
  }

  Future<void> completeAccountDeletionWithEmailLink({
    required String email,
    required String emailLink,
  }) async {
    final user = _requireCurrentUser();
    final normalizedEmail = email.trim().toLowerCase();
    if (user.email?.trim().toLowerCase() != normalizedEmail) {
      throw FirebaseAuthException(
        code: 'email-mismatch',
        message: 'The email link does not match the signed-in account.',
      );
    }

    await user.reauthenticateWithCredential(
      EmailAuthProvider.credentialWithLink(
        email: normalizedEmail,
        emailLink: emailLink,
      ),
    );

    await _users.doc(user.uid).delete();
    await user.delete();
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
    final profile = _users.doc(user.uid);
    final snapshot = await profile.get();
    final nameUpdate = {
      'fullName': fullName.trim(),
      'updatedAt': FieldValue.serverTimestamp(),
    };

    if (snapshot.exists) {
      await profile.update(nameUpdate);
      return;
    }

    await profile.set({
      ...nameUpdate,
      'accountStatus': 'active',
      'voicePersona': 'sara',
      'speechRate': 1.0,
      'instructionFrequency': 'normal',
      'alertRepetitionCount': 0,
      'vibrationEnabled': true,
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

  Future<bool> canSendSignInLink(String email) async {
  final normalizedEmail = email.trim().toLowerCase();

  final response = await http
      .post(
        Uri.parse('$_authApiBaseUrl/check-email'),
        headers: {
          'Content-Type': 'application/json',
        },
        body: jsonEncode({
          'email': normalizedEmail,
        }),
      )
      .timeout(const Duration(seconds: 15));

  if (response.statusCode != 200) {
    throw Exception('Unable to verify email. Please try again.');
  }

  final data = jsonDecode(response.body) as Map<String, dynamic>;

  if (data['success'] != true) {
    throw Exception('Unable to verify email. Please try again.');
  }

  return data['canSendLink'] == true;
}

Future<void> sendSignInLink({
  required String email,
}) async {
  final normalizedEmail = email.trim().toLowerCase();

  final actionCodeSettings = ActionCodeSettings(
    url: 'https://dulni-d2dd1.web.app',
    handleCodeInApp: true,
    androidPackageName: 'com.example.dulni_project',
    androidInstallApp: false,
  );

  await _auth.sendSignInLinkToEmail(
    email: normalizedEmail,
    actionCodeSettings: actionCodeSettings,
  );

  final prefs = await SharedPreferences.getInstance();

  await prefs.setString(_pendingEmailKey, normalizedEmail);
  await prefs.remove(_pendingNameKey);
  await prefs.remove(_pendingActionKey);
}
}
