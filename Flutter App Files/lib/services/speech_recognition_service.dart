import 'package:speech_to_text/speech_recognition_result.dart';
import 'package:speech_to_text/speech_to_text.dart';
import 'package:flutter/foundation.dart';

typedef SpeechTextCallback = void Function(String text);
typedef SpeechStatusCallback = void Function(String status);
typedef SpeechErrorCallback = void Function(String message);

class SpeechRecognitionService {
  SpeechRecognitionService._();

  static final SpeechRecognitionService instance = SpeechRecognitionService._();

  final SpeechToText _speech = SpeechToText();

  bool _initialized = false;
  String? _arabicLocaleId;
  String? _englishLocaleId;

  String? get arabicLocaleId => _arabicLocaleId;
  String? get englishLocaleId => _englishLocaleId;

  SpeechStatusCallback? _onStatus;
  SpeechErrorCallback? _onError;

  String _lastPartialText = '';
  SpeechTextCallback? _activeResultCallback;
  bool _useLastPartialOnStop = false;
  bool _resultDelivered = false;

  bool get isListening => _speech.isListening;

  Future<bool> initialize({
    SpeechStatusCallback? onStatus,
    SpeechErrorCallback? onError,
  }) async {
    _onStatus = onStatus ?? _onStatus;
    _onError = onError ?? _onError;

    if (_initialized) return true;

    final available = await _speech.initialize(
      onStatus: (status) {
        if (status == 'done' || status == 'notListening') {
          _deliverLastPartialResult();
        }

        _onStatus?.call(status);
      },
      onError: (error) {
        debugPrint('STT ERROR: ${error.errorMsg}');

        // تسليم آخر نتيجة جزئية قبل معالجة الخطأ.
        _deliverLastPartialResult();

        _onError?.call(error.errorMsg);
      },
    );

    if (!available) {
      _onError?.call('خدمة التعرف على الكلام غير متاحة.');
      return false;
    }

    final locales = await _speech.locales();

    final arabicLocales = locales.where((locale) {
      final id = locale.localeId.replaceAll('_', '-').toLowerCase();
      return id == 'ar' || id.startsWith('ar-');
    }).toList();

    final englishLocales = locales.where((locale) {
      final id = locale.localeId.replaceAll('_', '-').toLowerCase();
      return id == 'en' || id.startsWith('en-');
    }).toList();

    final preferredEnglishLocale = englishLocales.where((locale) {
      return locale.localeId.replaceAll('_', '-').toLowerCase() == 'en-us';
    }).toList();

    final britishEnglishLocale = englishLocales.where((locale) {
      return locale.localeId.replaceAll('_', '-').toLowerCase() == 'en-gb';
    }).toList();

    if (preferredEnglishLocale.isNotEmpty) {
      _englishLocaleId = preferredEnglishLocale.first.localeId;
    } else if (britishEnglishLocale.isNotEmpty) {
      _englishLocaleId = britishEnglishLocale.first.localeId;
    } else if (englishLocales.isNotEmpty) {
      _englishLocaleId = englishLocales.first.localeId;
    }

    debugPrint('STT Arabic locale: $_arabicLocaleId');
    debugPrint('STT English locale: $_englishLocaleId');

    if (arabicLocales.isEmpty) {
      _onError?.call('لا توجد لغة عربية متاحة للتعرف على الكلام في الجهاز.');
      return false;
    }

    final saudiLocale = arabicLocales.where((locale) {
      return locale.localeId.replaceAll('_', '-').toLowerCase() == 'ar-sa';
    }).toList();

    _arabicLocaleId = saudiLocale.isNotEmpty
        ? saudiLocale.first.localeId
        : arabicLocales.first.localeId;

    _initialized = true;
    return true;
  }

  void _deliverLastPartialResult() {
    if (!_useLastPartialOnStop ||
        _resultDelivered ||
        _lastPartialText.isEmpty ||
        _activeResultCallback == null) {
      return;
    }

    _resultDelivered = true;

    debugPrint('STT FINAL FROM PARTIAL: "$_lastPartialText"');

    _activeResultCallback!.call(_lastPartialText);
  }

  Future<bool> startListening({
    required SpeechTextCallback onResult,
    SpeechStatusCallback? onStatus,
    SpeechErrorCallback? onError,
    String? localeId,
    bool useLastPartialOnStop = false,
  }) async {
    final ready = await initialize(onStatus: onStatus, onError: onError);

    if (!ready) return false;
    if (_speech.isListening) return false;

    _lastPartialText = '';
    _activeResultCallback = onResult;
    _useLastPartialOnStop = useLastPartialOnStop;
    _resultDelivered = false;

    await _speech.listen(
      onResult: (SpeechRecognitionResult result) {
        final recognizedText = result.recognizedWords.trim();

        debugPrint(
          'STT RESULT: "$recognizedText" | '
          'finalResult: ${result.finalResult}',
        );

        if (recognizedText.isEmpty) return;

        if (result.finalResult) {
          if (!_resultDelivered) {
            _resultDelivered = true;
            onResult(recognizedText);
          }
        } else if (useLastPartialOnStop) {
          _lastPartialText = recognizedText;
        }
      },
      listenOptions: SpeechListenOptions(
        localeId: localeId ?? _arabicLocaleId,
        listenFor: const Duration(seconds: 30),
        pauseFor: const Duration(seconds: 5),
        partialResults: true,
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
