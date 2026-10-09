import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

class AuthService {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

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

    await _firestore.collection('User').doc(uid).set({
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
}
