
import 'dart:async';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';

import 'voice_backend_service.dart';

class VoiceFeedbackService {
  VoiceFeedbackService._();

  static final VoiceFeedbackService instance =
      VoiceFeedbackService._();

  final AudioPlayer _player = AudioPlayer();

  StreamSubscription<void>? _completionSubscription;

  bool _initialized = false;
  bool _isSpeaking = false;
  bool _disposed = false;

  String _voicePersona = 'sara';

  int _generationId = 0;

  Completer<void>? _playbackCompleter;

  String get voicePersona => _voicePersona;
  bool get isSpeaking => _isSpeaking;

  Future<void> initialize({
    double speechRate = 0.45,
  }) async {
    if (_initialized) return;

    _disposed = false;

    await _player.setReleaseMode(ReleaseMode.stop);

    _completionSubscription =
        _player.onPlayerComplete.listen((_) {
      _isSpeaking = false;

      final completer = _playbackCompleter;
      if (completer != null && !completer.isCompleted) {
        completer.complete();
      }

      _playbackCompleter = null;
    });

    _initialized = true;
  }

  void setVoicePersona(String persona) {
    if (persona != 'sara' && persona != 'abdulaziz') {
      throw ArgumentError('Unsupported voice persona.');
    }

    _voicePersona = persona;
  }

  Future<void> speak(String message) async {
    if (message.trim().isEmpty || _disposed) return;

    if (!_initialized) {
      await initialize();
    }

    if (_disposed) return;

    // Invalidate any previous speech request.
    final requestId = ++_generationId;

    await _stopPlaybackOnly();

    try {
      final audioBytes =
          await VoiceBackendService.instance.generateSpeech(
        text: message.trim(),
        voicePersona: _voicePersona,
      );

      // Ignore a response belonging to an old or cancelled request.
      if (_disposed || requestId != _generationId) return;

      if (audioBytes.isEmpty) {
        throw Exception('Empty audio response.');
      }

      final completer = Completer<void>();
      _playbackCompleter = completer;

      _isSpeaking = true;

      await _player.play(
        BytesSource(audioBytes),
      );

      // The player may have completed or been stopped already.
      if (requestId != _generationId || _disposed) {
        if (!completer.isCompleted) {
          completer.complete();
        }
      }

      await completer.future;
    } catch (error, stackTrace) {
      if (requestId == _generationId && !_disposed) {
        _isSpeaking = false;

        debugPrint('HUMAIN TTS error: $error');
        debugPrintStack(stackTrace: stackTrace);

        rethrow;
      }
    } finally {
      if (requestId == _generationId) {
        _isSpeaking = false;
        _playbackCompleter = null;
      }
    }
  }

  Future<void> _stopPlaybackOnly() async {
    final completer = _playbackCompleter;

    _playbackCompleter = null;
    _isSpeaking = false;

    if (completer != null && !completer.isCompleted) {
      completer.complete();
    }

    if (_initialized) {
      await _player.stop();
    }
  }

  Future<void> stop() async {
    // Invalidate pending HTTP responses as well as current playback.
    _generationId++;

    await _stopPlaybackOnly();
  }

  Future<void> dispose() async {
    if (_disposed) return;

    _disposed = true;
    _generationId++;

    await _stopPlaybackOnly();

    await _completionSubscription?.cancel();
    _completionSubscription = null;

    await _player.dispose();

    _initialized = false;
  }
}
