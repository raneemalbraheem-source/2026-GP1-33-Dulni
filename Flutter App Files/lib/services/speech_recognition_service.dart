
import 'dart:async';

import 'package:azure_speech_services/azure_speech_services.dart';
import 'package:flutter/foundation.dart';

import 'voice_backend_service.dart';

typedef SpeechTextCallback = void Function(String text);
typedef SpeechStatusCallback = void Function(String status);
typedef SpeechErrorCallback = void Function(String message);

class SpeechRecognitionService {
  SpeechRecognitionService._();

  static final SpeechRecognitionService instance =
      SpeechRecognitionService._();

  AzureSpeechToText? _azure;
  StreamSubscription<TranscriptionState>? _subscription;

  bool _isStarting = false;

  final String _arabicLocaleId = 'ar-SA';
  final String _englishLocaleId = 'en-US';

  String? get arabicLocaleId => _arabicLocaleId;
  String? get englishLocaleId => _englishLocaleId;

  bool get isListening => _azure?.isListening ?? false;

  SpeechStatusCallback? _onStatus;
  SpeechErrorCallback? _onError;
  SpeechTextCallback? _activeResultCallback;

  int _lastFinalizedCount = 0;
  String? _lastError;

  String? _cachedToken;
  String? _cachedRegion;
  DateTime? _tokenExpiry;

  final List<String> _pendingFinalResults = [];
  Timer? _finalResultTimer;

  static const Duration _finalResultDelay =
      Duration(milliseconds: 1600);

  Future<bool> initialize({
    SpeechStatusCallback? onStatus,
    SpeechErrorCallback? onError,
  }) async {
    _onStatus = onStatus ?? _onStatus;
    _onError = onError ?? _onError;

    return true;
  }

  Future<Map<String, String>> _getAzureCredentials() async {
    final now = DateTime.now();

    if (_cachedToken != null &&
        _cachedRegion != null &&
        _tokenExpiry != null &&
        now.isBefore(_tokenExpiry!)) {
      return {
        'token': _cachedToken!,
        'region': _cachedRegion!,
      };
    }

    final credentials =
        await VoiceBackendService.instance.getSttToken();

    _cachedToken = credentials['token'] as String;
    _cachedRegion = credentials['region'] as String;

    // Azure tokens are valid for 10 minutes.
    // Refresh slightly early to avoid expiration during recognition.
    _tokenExpiry = now.add(const Duration(minutes: 8));

    return {
      'token': _cachedToken!,
      'region': _cachedRegion!,
    };
  }

  String _normalizeLocale(String? localeId) {
    final locale = (localeId ?? 'ar-SA')
        .replaceAll('_', '-')
        .toLowerCase();

    if (locale.startsWith('en')) {
      return 'en-US';
    }

    return 'ar-SA';
  }

  Future<bool> startListening({
    required SpeechTextCallback onResult,
    SpeechStatusCallback? onStatus,
    SpeechErrorCallback? onError,
    String? localeId,
    bool useLastPartialOnStop = false,
  }) async {
    await initialize(onStatus: onStatus, onError: onError);

    if (isListening || _isStarting) {
      return false;
    }

    _isStarting = true;
    _activeResultCallback = onResult;
    _lastFinalizedCount = 0;
    _lastError = null;
    _clearPendingResults();

    try {
      final credentials = await _getAzureCredentials();

      final language = _normalizeLocale(localeId);

      final config = AzureSpeechConfig.authorizationToken(
        region: credentials['region']!,
        token: credentials['token']!,
      );

      final sttConfig = SpeechToTextConfig(
        languages: [language],
        languageIdMode: LanguageIdMode.atStart,
        textClearTimeout: const Duration(seconds: 15),
      );

      final azure = AzureSpeechToText(
        config: config,
        sttConfig: sttConfig,
      );

      _azure = azure;

      _subscription = azure.stream.listen(
        _handleTranscriptionState,
        onError: (error) {
          debugPrint('Azure STT stream error: $error');
          _onError?.call(
            'Speech recognition connection failed.',
          );
        },
      );

      await azure.start();

      if (!azure.isListening) {
        await _disposeAzure();
        return false;
      }

      _onStatus?.call('listening');
      return true;
    } catch (error, stackTrace) {
      debugPrint('Azure STT start error: $error');
      debugPrintStack(stackTrace: stackTrace);

      _onError?.call(
        'Unable to start speech recognition.',
      );

      await _disposeAzure();
      return false;
    } finally {
      _isStarting = false;
    }
  }

  void _handleTranscriptionState(TranscriptionState state) {
    if (state.error != null && state.error != _lastError) {
      _lastError = state.error;
      debugPrint('Azure STT error: ${state.error}');
      _onError?.call(state.error!);
    }

    final finalized = state.finalizedText;

    // Azure may clear finalizedText when a new hypothesis arrives.
    if (finalized.length < _lastFinalizedCount) {
      _lastFinalizedCount = 0;
    }

    if (finalized.length > _lastFinalizedCount) {
      final newResults =
          finalized.skip(_lastFinalizedCount).toList();

      _lastFinalizedCount = finalized.length;

      for (final result in newResults) {
        final text = result.trim();

        if (text.isEmpty) continue;

        debugPrint('Azure STT FINAL: "$text"');
        _queueFinalResult(text);
      }
    }

    if (!state.isListening && !_isStarting) {
      _onStatus?.call('notListening');
    }
  }

  void _queueFinalResult(String text) {
    _pendingFinalResults.add(text);

    _finalResultTimer?.cancel();
    _finalResultTimer = Timer(
      _finalResultDelay,
      _deliverPendingResults,
    );
  }

  void _deliverPendingResults() {
    _finalResultTimer?.cancel();
    _finalResultTimer = null;

    if (_pendingFinalResults.isEmpty) return;

    final combinedText = _pendingFinalResults.join(' ').trim();

    _pendingFinalResults.clear();

    if (combinedText.isEmpty) return;

    debugPrint('Azure STT COMBINED FINAL: "$combinedText"');

    _activeResultCallback?.call(combinedText);
  }

  void _clearPendingResults() {
    _finalResultTimer?.cancel();
    _finalResultTimer = null;
    _pendingFinalResults.clear();
  }

  Future<void> stopListening() async {
    await _disposeAzure(flushPendingResults: true);
    _onStatus?.call('notListening');
  }

  Future<void> cancelListening() async {
    await _disposeAzure();
    _onStatus?.call('notListening');
  }

  Future<void> _disposeAzure({
    bool flushPendingResults = false,
  }) async {
    final subscription = _subscription;
    final azure = _azure;

    if (flushPendingResults) {
      _deliverPendingResults();
    } else {
      _clearPendingResults();
    }

    _subscription = null;
    _azure = null;
    _activeResultCallback = null;
    _lastFinalizedCount = 0;

    await subscription?.cancel();

    if (azure != null) {
      try {
        await azure.stop();
      } catch (error) {
        debugPrint('Azure STT stop error: $error');
      }

      try {
        await azure.dispose();
      } catch (error) {
        debugPrint('Azure STT dispose error: $error');
      }
    }
  }
}
