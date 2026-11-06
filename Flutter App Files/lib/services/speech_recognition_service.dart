import 'package:speech_to_text/speech_recognition_result.dart';
import 'package:speech_to_text/speech_to_text.dart';

typedef SpeechTextCallback = void Function(String text);
typedef SpeechStatusCallback = void Function(String status);
typedef SpeechErrorCallback = void Function(String message);

class SpeechRecognitionService {
  SpeechRecognitionService._();

  static final SpeechRecognitionService instance = SpeechRecognitionService._();

  final SpeechToText _speech = SpeechToText();

  bool _initialized = false;
  String? _arabicLocaleId;

  SpeechStatusCallback? _onStatus;
  SpeechErrorCallback? _onError;

  bool get isListening => _speech.isListening;

  Future<bool> initialize({
    SpeechStatusCallback? onStatus,
    SpeechErrorCallback? onError,
  }) async {
    // Keep the callbacks up to date.
    _onStatus = onStatus ?? _onStatus;
    _onError = onError ?? _onError;

    // Initialize only once during the app session.
    if (_initialized) return true;

    final available = await _speech.initialize(
      onStatus: (status) {
        _onStatus?.call(status);
      },
      onError: (error) {
        _onError?.call(error.errorMsg);
      },
    );

    if (!available) {
      _onError?.call('خدمة التعرف على الكلام غير متاحة.');
      return false;
    }

    // Get the speech recognition languages available on this device.
    final locales = await _speech.locales();

    final arabicLocales = locales.where((locale) {
      final id = locale.localeId.replaceAll('_', '-').toLowerCase();

      return id == 'ar' || id.startsWith('ar-');
    }).toList();

    if (arabicLocales.isEmpty) {
      _onError?.call('لا توجد لغة عربية متاحة للتعرف على الكلام في الجهاز.');
      return false;
    }

    // Prefer Saudi Arabic when available.
    final saudiLocale = arabicLocales.where((locale) {
      return locale.localeId.replaceAll('_', '-').toLowerCase() == 'ar-sa';
    }).toList();

    _arabicLocaleId = saudiLocale.isNotEmpty
        ? saudiLocale.first.localeId
        : arabicLocales.first.localeId;

    _initialized = true;
    return true;
  }

  Future<bool> startListening({
    required SpeechTextCallback onResult,
    SpeechStatusCallback? onStatus,
    SpeechErrorCallback? onError,
  }) async {
    final ready = await initialize(onStatus: onStatus, onError: onError);

    if (!ready) return false;

    if (_speech.isListening) {
      return false;
    }

    await _speech.listen(
      onResult: (SpeechRecognitionResult result) {
        final recognizedText = result.recognizedWords.trim();

        if (result.finalResult && recognizedText.isNotEmpty) {
          onResult(recognizedText);
        }
      },
      listenOptions: SpeechListenOptions(
        localeId: _arabicLocaleId,

        // Maximum listening duration.
        listenFor: const Duration(seconds: 30),

        // Wait longer when the user pauses between words.
        pauseFor: const Duration(seconds: 5),

        partialResults: false,
        cancelOnError: true,
      ),
    );

    return true;
  }

  Future<void> stopListening() async {
    await _speech.stop();
  }

  Future<void> cancelListening() async {
    await _speech.cancel();
  }
}
