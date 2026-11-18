import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

class VoicePreferences {
  const VoicePreferences({
    this.voicePersona = 'default',
    this.speechRate = 1.0,
  });

  final String voicePersona;
  final double speechRate;

  factory VoicePreferences.fromMap(Map<String, dynamic> data) {
    const supportedPersonas = {'default', 'male', 'female'};
    final persona = data['voicePersona'];
    final rate = data['speechRate'];

    return VoicePreferences(
      voicePersona: persona is String && supportedPersonas.contains(persona)
          ? persona
          : 'default',
      speechRate: rate is num && rate > 0 && rate <= 1
          ? rate.toDouble()
          : 1.0,
    );
  }
}

class VoicePreferencesService {
  VoicePreferencesService({
    FirebaseAuth? auth,
    FirebaseFirestore? firestore,
  }) : _auth = auth ?? FirebaseAuth.instance,
       _firestore = firestore ?? FirebaseFirestore.instance;

  final FirebaseAuth _auth;
  final FirebaseFirestore _firestore;

  CollectionReference<Map<String, dynamic>> get _users =>
      _firestore.collection('User');

  Future<VoicePreferences> load() async {
    final user = _auth.currentUser;
    if (user == null) {
      throw StateError('يجب تسجيل الدخول لعرض تفضيلات الصوت.');
    }

    final snapshot = await _users.doc(user.uid).get();
    return VoicePreferences.fromMap(snapshot.data() ?? const {});
  }

  Future<void> save(VoicePreferences preferences) async {
    final user = _auth.currentUser;
    if (user == null) {
      throw StateError('يجب تسجيل الدخول لحفظ تفضيلات الصوت.');
    }

    const supportedPersonas = {'default', 'male', 'female'};
    if (!supportedPersonas.contains(preferences.voicePersona)) {
      throw ArgumentError.value(
        preferences.voicePersona,
        'voicePersona',
        'اختيار الصوت غير صالح.',
      );
    }
    if (preferences.speechRate <= 0 || preferences.speechRate > 1) {
      throw ArgumentError.value(
        preferences.speechRate,
        'speechRate',
        'سرعة التحدث يجب أن تكون أكبر من صفر ولا تتجاوز واحدًا.',
      );
    }

    await _users.doc(user.uid).update({
      'voicePersona': preferences.voicePersona,
      'speechRate': preferences.speechRate,
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }
}
