
import 'dart:async';

import 'package:flutter/material.dart';

import 'speech_recognition_service.dart';
import 'voice_feedback_service.dart';
import 'permission_service.dart';

enum VoiceNavigationPage {
  home,
  favorites,
  profile,
  login,
  signup,
}

enum VoiceNavigationAction {
  home,
  favorites,
  profile,
  login,
  signup,
  logout,
}

enum _VoiceNavigationMode {
  choice,
  commands,
}

class VoiceNavigationService {
  VoiceNavigationService._();

  static final VoiceNavigationService instance =
      VoiceNavigationService._();

  final _speechService = SpeechRecognitionService.instance;
  final _voiceService = VoiceFeedbackService.instance;

  bool _active = false;
  bool _busy = false;
  bool _processing = false;
  bool _restartPending = false;

  bool _isSignedIn = false;

  VoiceNavigationPage? _currentPage;

  _VoiceNavigationMode _mode = _VoiceNavigationMode.choice;

  Timer? _silenceTimer;

  Future<void> Function(VoiceNavigationAction action)? _onNavigate;
  Future<void> Function()? _onComplete;

  String get _availablePages {
    final pages = <String>[];

    if (_currentPage != VoiceNavigationPage.home) {
      pages.add('الرئيسية');
    }

    if (_currentPage != VoiceNavigationPage.favorites) {
      pages.add('الأماكن المفضلة');
    }

    if (_currentPage != VoiceNavigationPage.profile) {
      pages.add('الملف الشخصي');
    }

    if (!_isSignedIn) {
  if (_currentPage != VoiceNavigationPage.login) {
    pages.add('تسجيل الدخول');
  }

  if (_currentPage != VoiceNavigationPage.signup) {
    pages.add('إنشاء حساب');
  }
} else {
  pages.add('تسجيل الخروج');
}

    return pages.join('، ');
  }

  Future<bool> start({
    required BuildContext context,
    required VoiceNavigationPage currentPage,
    required bool isSignedIn,
    required Future<void> Function(VoiceNavigationAction action)
        onNavigate,
    required Future<void> Function() onComplete,
  }) async {
    if (_active) return false;

    _currentPage = currentPage;
    _isSignedIn = isSignedIn;
    _onNavigate = onNavigate;
    _onComplete = onComplete;

    try {
      await _speechService.cancelListening();

      await _voiceService.initialize();

      final ready = await _speechService.initialize(
        onStatus: _handleSpeechStatus,
        onError: (message) {
          debugPrint('Voice navigation speech error: $message');
        },
      );

      if (!context.mounted || !ready) {
        await stop();
        return false;
      }

      final hasPermission =
          await PermissionService.requestMicrophonePermission(context);

      if (!context.mounted || !hasPermission) {
        await stop();
        return false;
      }

      _active = true;
      _mode = _VoiceNavigationMode.choice;

      await _speak(
        'هل ترغب في الانتقال إلى صفحة أخرى، '
        'أم تريد إكمال استخدام الصفحة الحالية؟',
      );

      if (_active) {
        final listening = await _listen();

        if (!listening) {
          await stop();
          return false;
        }
      }

      return true;
    } catch (e) {
      debugPrint('Voice navigation initialization error: $e');
      await stop();
      return false;
    }
  }

  Future<bool> _listen() async {
    if (!_active ||
        _busy ||
        _processing ||
        _speechService.isListening) {
      return false;
    }

    _restartPending = false;

    final started = await _speechService.startListening(
      onResult: _handleVoiceResult,
      onStatus: _handleSpeechStatus,
      onError: (message) {
        debugPrint('Voice navigation listening error: $message');
      },
      localeId: _speechService.arabicLocaleId,
      useLastPartialOnStop: true,
    );

    debugPrint('Voice navigation listening started: $started');

    if (started && _active) {
      _startSilenceTimer();
    }
    return started;
  }

  void _startSilenceTimer() {
    _silenceTimer?.cancel();

    _silenceTimer = Timer(
      const Duration(seconds: 8),
      () async {
        if (!_active || _busy || _processing) return;

        final reminder = _mode == _VoiceNavigationMode.choice
            ? 'هل ترغب في الانتقال إلى صفحة أخرى، '
                'أم تريد إكمال استخدام الصفحة الحالية؟'
            : 'يمكنك قول أحد الأوامر التالية: $_availablePages';

        await _speak(reminder);

        if (_active) {
          await _listen();
        }
      },
    );
  }

  void _handleSpeechStatus(String status) {
    if (!_active || _busy || _processing) return;

    if (status == 'done' || status == 'notListening') {
      if (_restartPending) return;

      _restartPending = true;

      Future.delayed(const Duration(milliseconds: 700), () {
        if (!_active ||
            _busy ||
            _processing ||
            !_restartPending) {
          return;
        }

        _listen();
      });
    }
  }

  Future<void> _handleVoiceResult(String text) async {
    if (!_active || _processing) return;

    _silenceTimer?.cancel();
    _processing = true;
    _restartPending = false;

    try {
      if (_mode == _VoiceNavigationMode.choice) {
        await _handleNavigationChoice(text);
      } else {
        await _handleNavigationCommand(text);
      }
    } finally {
      _processing = false;

      if (_active && !_busy && !_speechService.isListening) {
        _restartPending = false;
        await _listen();
      }
    }
  }

  String _normalizeArabic(String text) {
    return text
        .replaceAll(RegExp(r'[ًٌٍَُِّْـ]'), '')
        .replaceAll('أ', 'ا')
        .replaceAll('إ', 'ا')
        .replaceAll('آ', 'ا')
        .replaceAll('ى', 'ي')
        .replaceAll(RegExp(r'[.,،؛:!?؟"“”()[\]{}]'), '')
        .trim()
        .toLowerCase();
  }

  Future<void> _handleNavigationChoice(String text) async {
    final command = _normalizeArabic(text);

    if (command.contains('انتقال') ||
        command.contains('صفحه اخرى') ||
        command.contains('صفحة اخرى') ||
        command.contains('التنقل')) {
      _mode = _VoiceNavigationMode.commands;

      await _speak(
        'التنقل الصوتي يتيح لك الانتقال بين صفحات تطبيق دُلّني. '
        'يمكنك استخدام الأوامر التالية: $_availablePages. '
        'ما الصفحة أو الإجراء الذي ترغب فيه؟',
      );

      return;
    }

    if (command.contains('اكمال') ||
        command.contains('اكمل') ||
        command.contains('الصفحه الحاليه') ||
        command.contains('الصفحة الحالية')) {
      await _finishAndContinue();
      return;
    }

    await _speak(
      'لم أفهم اختيارك. '
      'قل الانتقال إلى صفحة أخرى، أو إكمال استخدام الصفحة الحالية.',
    );
  }

  Future<void> _handleNavigationCommand(String text) async {
    final command = _normalizeArabic(text);

    VoiceNavigationAction? action;

    if (command.contains('الرئيسيه') ||
        command.contains('الرئيسية') ||
        command.contains('الخريطه') ||
        command.contains('الخريطة')) {
      action = VoiceNavigationAction.home;
    } else if (command.contains('الاماكن المفضله') ||
        command.contains('الأماكن المفضلة') ||
        command.contains('المفضله') ||
        command.contains('المفضلة')) {
      action = VoiceNavigationAction.favorites;
    } else if (command.contains('الملف الشخصي') ||
        command.contains('الحساب')) {
      action = VoiceNavigationAction.profile;
    } else if (_isSignedIn &&
        (command.contains('تسجيل الخروج') ||
            command.contains('سجل خروج'))) {
      action = VoiceNavigationAction.logout;
    } else if (!_isSignedIn &&
        (command.contains('تسجيل الدخول') ||
            command.contains('سجل الدخول'))) {
      action = VoiceNavigationAction.login;
    } else if (!_isSignedIn &&
        (command.contains('انشاء حساب') ||
            command.contains('انشئ حساب'))) {
      action = VoiceNavigationAction.signup;
    }

    if (action == null || !_isActionAvailable(action)) {
      await _speak(
        'لم أفهم الأمر أو أن هذا الخيار غير متاح هنا. '
        'يمكنك الاختيار من: $_availablePages',
      );
      return;
    }

    final callback = _onNavigate;

    await stop();

    await callback?.call(action);
  }

  bool _isActionAvailable(VoiceNavigationAction action) {
    switch (action) {
      case VoiceNavigationAction.home:
        return _currentPage != VoiceNavigationPage.home;

      case VoiceNavigationAction.favorites:
        return _currentPage != VoiceNavigationPage.favorites;

      case VoiceNavigationAction.profile:
        return _currentPage != VoiceNavigationPage.profile;

      case VoiceNavigationAction.login:
          return !_isSignedIn &&
              _currentPage != VoiceNavigationPage.login;

        case VoiceNavigationAction.signup:
          return !_isSignedIn &&
          _currentPage != VoiceNavigationPage.signup;

      case VoiceNavigationAction.logout:
        return _isSignedIn;
    }
  }

  Future<void> _finishAndContinue() async {
    final callback = _onComplete;

    await stop();

    await callback?.call();
  }

  Future<void> _speak(String message) async {
    if (!_active && _currentPage == null) return;

    _busy = true;
    _silenceTimer?.cancel();

    try {
      await _speechService.stopListening();
      await _voiceService.speak(message);
    } catch (e) {
      debugPrint('Voice navigation speech error: $e');
    } finally {
      _busy = false;
    }
  }

  Future<void> stop() async {
    _active = false;
    _busy = true;
    _restartPending = false;

    _silenceTimer?.cancel();
    _silenceTimer = null;

    await _speechService.cancelListening();
    await _voiceService.stop();

    _busy = false;
    _processing = false;
    _currentPage = null;
    _onNavigate = null;
    _onComplete = null;
  }
}
