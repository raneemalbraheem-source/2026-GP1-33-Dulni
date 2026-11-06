
import 'package:flutter_tts/flutter_tts.dart';

class VoiceFeedbackService {
  VoiceFeedbackService._();

  static final VoiceFeedbackService instance =
      VoiceFeedbackService._();

  final FlutterTts _tts = FlutterTts();

  bool _initialized = false;
  String? _arabicLocale;

  Future<void> initialize({
    double speechRate = 0.45,
  }) async {
    if (!_initialized) {
      // Get languages available in the device's TTS engine.
      final dynamic availableLanguages = await _tts.getLanguages;

      if (availableLanguages is! List) {
        throw Exception('تعذر الحصول على اللغات المتاحة.');
      }

      final languages = availableLanguages
          .map((language) => language.toString())
          .toList();

      // Select Saudi Arabic when available, otherwise another
      // available Arabic locale.
      final arabicLanguages = languages
          .where(
            (language) =>
                language.toLowerCase().startsWith('ar'),
          )
          .toList();

      if (arabicLanguages.isEmpty) {
        throw Exception(
          'لا يوجد صوت عربي متاح على الجهاز. '
          'يرجى تثبيت صوت عربي من إعدادات تحويل النص إلى كلام.',
        );
      }

      _arabicLocale = arabicLanguages.firstWhere(
        (language) => language.toLowerCase() == 'ar-sa',
        orElse: () => arabicLanguages.first,
      );

      await _tts.setLanguage(_arabicLocale!);
      await _tts.setVolume(1.0);
      await _tts.setPitch(1.0);
      await _tts.awaitSpeakCompletion(true);

      _initialized = true;
    }

    // Current Dulni default speech rate is 1.0.
    await _tts.setSpeechRate(
      speechRate.clamp(0.0, 1.0).toDouble(),
    );
  }

  Future<void> speak(String message) async {
    if (message.trim().isEmpty) return;

    if (!_initialized) {
      await initialize();
    }

    // Stop previous speech before speaking a new message.
    await _tts.stop();
    await _tts.speak(message);
  }

  Future<void> stop() async {
    await _tts.stop();
  }
}
