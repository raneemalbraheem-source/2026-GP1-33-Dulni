import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';

import '../services/speech_recognition_service.dart';
import '../services/voice_feedback_service.dart';
import '../services/permission_service.dart';
import '../services/voice_navigation_service.dart';
import '../widgets/app_bottom_navigation.dart';
import 'login_page.dart';
import 'signup_page.dart';

enum GuestFeature { favorites, profile }

enum _GuestVoiceMode {
  manual,
  commands,
  confirmation,
}

enum _GuestAuthChoice {
  login,
  signup,
}

class GuestAccessPage extends StatefulWidget {
  const GuestAccessPage({super.key, required this.feature});

  final GuestFeature feature;

  @override
  State<GuestAccessPage> createState() => _GuestAccessPageState();
}

class _GuestAccessPageState extends State<GuestAccessPage> {
  final _speechService = SpeechRecognitionService.instance;
  final _voiceService = VoiceFeedbackService.instance;
  final _voiceNavigationService = VoiceNavigationService.instance;

  _GuestVoiceMode _voiceMode = _GuestVoiceMode.manual;

  _GuestAuthChoice? _selectedChoice;

  bool _voiceEnabled = false;
  bool _voiceBusy = false;
  bool _voiceProcessing = false;
  bool _voiceRestartPending = false;
  bool _awaitingVoiceChoice = false;
  bool _screenReaderActive = false;

  Timer? _silenceTimer;

  bool get _isFavorites =>
      widget.feature == GuestFeature.favorites;

  String get _pageTitle =>
      _isFavorites ? 'الأماكن المفضلة' : 'الملف الشخصي';

  String get _pageRequirement => _isFavorites
      ? 'يتطلب استخدام الأماكن المفضلة تسجيل الدخول إلى حسابك.'
      : 'يتطلب الوصول إلى ملفك الشخصي تسجيل الدخول إلى حسابك.';

  String get _voicePreferenceQuestion =>
    'هل ترغب في استخدام التوجيه الصوتي؟ '
    'قل نعم لاستخدامه، أو لا للانتقال إلى الإدخال اليدوي.';

  String get _authChoiceQuestion =>
      'هل ترغب في تسجيل الدخول أو إنشاء حساب؟ '
      'قل تسجيل الدخول أو إنشاء حساب.';

  String get _confirmationQuestion =>
      _selectedChoice == _GuestAuthChoice.login
          ? 'هل تؤكد اختيار تسجيل الدخول؟ '
              'قل نعم للتأكيد، أو لا للرجوع إلى الاختيارات.'
          : 'هل تؤكد اختيار إنشاء حساب؟ '
              'قل نعم للتأكيد، أو لا للرجوع إلى الاختيارات.';

  @override
  void initState() {
    super.initState();

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _startGuestVoiceGuide();
    });
  }

  @override
  void dispose() {
    _voiceEnabled = false;
    _silenceTimer?.cancel();

    unawaited(_speechService.cancelListening());
    unawaited(_voiceService.stop());

    super.dispose();
  }

  Future<void> _startGuestVoiceGuide() async {
    if (!mounted) return;

    _screenReaderActive =
        MediaQuery.maybeOf(context)?.accessibleNavigation ?? false;

    // لا نشغل صوت التطبيق تلقائيًا أثناء استخدام قارئ الشاشة.
    if (_screenReaderActive) return;

    await _initializeVoice(
      askVoicePreference: true,
    );
  }

  Future<void> _enableVoiceMode() async {
    if (!mounted || _voiceEnabled) return;

    await _initializeVoice(
      askVoicePreference: false,
    );
  }

  Future<void> _initializeVoice({
    required bool askVoicePreference,
  }) async {
    try {
      await _voiceService.initialize();

      final ready = await _speechService.initialize(
        onStatus: _handleSpeechStatus,
        onError: (message) {
          debugPrint('Guest speech error: $message');
        },
      );

      if (!mounted || !ready) return;

      setState(() {
        _voiceEnabled = true;
        _voiceMode = _GuestVoiceMode.commands;
        _awaitingVoiceChoice = askVoicePreference;
      });

      final introduction = askVoicePreference
        ? 'مرحبًا بك في صفحة $_pageTitle في تطبيق دُلّني. '
            '$_pageRequirement '
            '$_voicePreferenceQuestion'
        : 'مرحبًا بك في صفحة $_pageTitle في تطبيق دُلّني. '
            '$_pageRequirement '
            '$_authChoiceQuestion';

      await _speakAndResume(introduction);
    } catch (e) {
      debugPrint('Guest voice initialization error: $e');

      if (!mounted) return;

      setState(() {
        _voiceEnabled = false;
        _voiceMode = _GuestVoiceMode.manual;
      });
    }
  }

Future<void> _startGeneralVoiceNavigation() async {
  if (!mounted || !_voiceEnabled) return;

  _silenceTimer?.cancel();
  _voiceRestartPending = false;
  _voiceEnabled = false;

  await _speechService.stopListening();

  if (!mounted) return;

  final started = await _voiceNavigationService.start(
    context: context,
    currentPage: _isFavorites
        ? VoiceNavigationPage.favorites
        : VoiceNavigationPage.profile,
    isSignedIn: false,
    onNavigate: _handleVoiceNavigation,
    onComplete: _resumeGuestVoice,
  );

  if (!started && mounted) {
    await _resumeGuestVoice();
  }
}

Future<void> _resumeGuestVoice() async {
  if (!mounted) return;

  await _initializeVoice(
    askVoicePreference: false,
  );
}

Future<void> _handleVoiceNavigation(
  VoiceNavigationAction action,
) async {
  if (!mounted) return;

  final navigator = Navigator.of(context);

  switch (action) {
    case VoiceNavigationAction.home:
      navigator.popUntil((route) => route.isFirst);
      break;

    case VoiceNavigationAction.favorites:
      navigator.popUntil((route) => route.isFirst);
      navigator.push(
        MaterialPageRoute<void>(
          builder: (_) => const GuestAccessPage(
            feature: GuestFeature.favorites,
          ),
        ),
      );
      break;

    case VoiceNavigationAction.profile:
      navigator.popUntil((route) => route.isFirst);
      navigator.push(
        MaterialPageRoute<void>(
          builder: (_) => const GuestAccessPage(
            feature: GuestFeature.profile,
          ),
        ),
      );
      break;

    case VoiceNavigationAction.login:
      navigator.push(
        MaterialPageRoute<void>(
          builder: (_) => const LoginPage(),
        ),
      );
      break;

    case VoiceNavigationAction.signup:
      navigator.push(
        MaterialPageRoute<void>(
          builder: (_) => const SignupPage(),
        ),
      );
      break;

    case VoiceNavigationAction.logout:
      break;
  }
}

  Future<void> _listenForVoice() async {
    if (!mounted ||
        !_voiceEnabled ||
        _voiceBusy ||
        _voiceProcessing ||
        _speechService.isListening) {
      return;
    }

    _voiceRestartPending = false;

    final hasMicrophonePermission =
        await PermissionService.requestMicrophonePermission(context);

    if (!mounted) return;

    if (!hasMicrophonePermission) {
      await _switchToManual();
      return;
    }

    final started = await _speechService.startListening(
      onResult: (recognizedText) {
        debugPrint('GUEST RECOGNIZED: "$recognizedText"');
        _silenceTimer?.cancel();
        _handleVoiceResult(recognizedText);
      },
      onStatus: _handleSpeechStatus,
      onError: (message) {
        debugPrint('GUEST SPEECH ERROR: $message');
      },
      localeId: _speechService.arabicLocaleId,
      useLastPartialOnStop: true,
    );

    debugPrint('GUEST: Listening started = $started');

    if (started && mounted && _voiceEnabled) {
      _startSilenceTimer();
    }
  }

  void _startSilenceTimer() {
    _silenceTimer?.cancel();

    if (!mounted ||
        !_voiceEnabled ||
        _voiceBusy ||
        _voiceProcessing ||
        _voiceMode == _GuestVoiceMode.manual) {
      return;
    }

    _silenceTimer = Timer(const Duration(seconds: 8), () async {
      if (!mounted ||
          !_voiceEnabled ||
          _voiceBusy ||
          _voiceProcessing) {
        return;
      }

      String reminder;

        if (_awaitingVoiceChoice) {
          reminder = _voicePreferenceQuestion;
        } else if (_voiceMode == _GuestVoiceMode.confirmation) {
          reminder = _confirmationQuestion;
        } else {
          reminder = _authChoiceQuestion;
        }

      await _speakAndResume(reminder);
    });
  }

  void _handleSpeechStatus(String status) {
    debugPrint('GUEST SPEECH STATUS: $status');

    if (!mounted || !_voiceEnabled || _voiceBusy) return;

    if (status == 'done' || status == 'notListening') {
      if (_voiceProcessing || _voiceRestartPending) return;

      _voiceRestartPending = true;

      Future.delayed(const Duration(milliseconds: 700), () {
        if (!mounted ||
            !_voiceEnabled ||
            _voiceBusy ||
            _voiceProcessing ||
            !_voiceRestartPending) {
          return;
        }

        _listenForVoice();
      });
    }
  }

  Future<void> _handleVoiceResult(String text) async {
    if (!mounted || _voiceProcessing) return;

    _silenceTimer?.cancel();
    _voiceProcessing = true;
    _voiceRestartPending = false;

    try {
      if (_voiceMode == _GuestVoiceMode.commands) {
        await _handleVoiceCommand(text);
      } else if (_voiceMode == _GuestVoiceMode.confirmation) {
        await _handleConfirmationCommand(text);
      }
    } finally {
      _voiceProcessing = false;

      if (mounted && _voiceEnabled && !_voiceBusy) {
        await _listenForVoice();
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

  bool _isYesCommand(String command) {
    return command == 'نعم' ||
        command == 'اي' ||
        command == 'ايوه' ||
        command == 'أيوه' ||
        command == 'صحيح' ||
        command == 'اكد' ||
        command == 'تأكيد';
  }

  bool _isNoCommand(String command) {
    return command == 'لا' ||
        command == 'لأ' ||
        command == 'الغاء' ||
        command == 'إلغاء';
  }

  Future<void> _handleVoiceCommand(String text) async {
    final command = _normalizeArabic(text);

    if (command.contains('الانتقال الى الادخال اليدوي') ||
        command.contains('ايقاف التوجيه الصوتي') ||
        command.contains('الغاء التوجيه الصوتي')) {
      await _speakAndResume(
        'حسنًا، يمكنك استخدام الأزرار الموجودة على الشاشة.',
      );
      await _switchToManual();
      return;
    }

    if (_awaitingVoiceChoice) {
      if (_isYesCommand(command)) {
        _awaitingVoiceChoice = false;

        await _startGeneralVoiceNavigation();
        return;
      }

      if (_isNoCommand(command)) {
        _awaitingVoiceChoice = false;

        await _speakAndResume(
          'حسنًا، يمكنك استخدام الأزرار الموجودة على الشاشة للتنقل يدوياً.',
        );
        await _switchToManual();
        return;
      }

      await _speakAndResume(
          'لم أفهم اختيارك. $_voicePreferenceQuestion',
        );
      return;
    }

    if (command.contains('تسجيل الدخول') ||
        command.contains('سجل الدخول')) {
      _selectedChoice = _GuestAuthChoice.login;
      _voiceMode = _GuestVoiceMode.confirmation;

      await _speakAndResume(
        'اخترت تسجيل الدخول. هل تؤكد اختيارك؟ '
        'قل نعم للتأكيد، أو لا للرجوع إلى الاختيارات.',
      );
      return;
    }

    if (command.contains('انشاء حساب') ||
        command.contains('انشئ حساب') ||
        command.contains('إنشاء حساب')) {
      _selectedChoice = _GuestAuthChoice.signup;
      _voiceMode = _GuestVoiceMode.confirmation;

      await _speakAndResume(
        'اخترت إنشاء حساب. هل تؤكد اختيارك؟ '
        'قل نعم للتأكيد، أو لا للرجوع إلى الاختيارات.',
      );
      return;
    }

    await _speakAndResume(
      'لم أفهم اختيارك. $_authChoiceQuestion',
    );
  }

  Future<void> _handleConfirmationCommand(String text) async {
    final command = _normalizeArabic(text);

    if (_isYesCommand(command)) {
      final choice = _selectedChoice;

      if (choice == null) return;

      await _navigateToAuthPage(choice);
      return;
    }

    if (_isNoCommand(command)) {
      _selectedChoice = null;
      _voiceMode = _GuestVoiceMode.commands;

      await _speakAndResume(
        'حسنًا، يمكنك الاختيار من جديد. $_authChoiceQuestion',
      );
      return;
    }

    await _speakAndResume(
      'لم أفهم اختيارك. $_confirmationQuestion',
    );
  }

  Future<void> _navigateToAuthPage(
    _GuestAuthChoice choice,
  ) async {
    _silenceTimer?.cancel();
    _voiceRestartPending = false;
    _voiceEnabled = false;

    await _speechService.cancelListening();
    await _voiceService.stop();

    if (!mounted) return;

    if (choice == _GuestAuthChoice.login) {
      Navigator.push(
        context,
        MaterialPageRoute<void>(
          builder: (_) => const LoginPage(),
        ),
      );
    } else {
      Navigator.push(
        context,
        MaterialPageRoute<void>(
          builder: (_) => const SignupPage(),
        ),
      );
    }
  }

  Future<void> _switchToManual() async {
    if (!mounted) return;

    _silenceTimer?.cancel();
    _voiceRestartPending = false;
    _awaitingVoiceChoice = false;
    _voiceEnabled = false;
    _voiceBusy = true;

    await _speechService.cancelListening();
    await _voiceService.stop();

    if (!mounted) return;

    setState(() {
      _voiceMode = _GuestVoiceMode.manual;
      _voiceEnabled = false;
      _voiceBusy = false;
      _selectedChoice = null;
    });

    final screenReaderActive =
        MediaQuery.maybeOf(context)?.accessibleNavigation ??
            _screenReaderActive;

    if (screenReaderActive) {
      SemanticsService.sendAnnouncement(
        View.of(context),
        'تم إيقاف التوجيه الصوتي. يمكنك استخدام الأزرار الموجودة على الشاشة.',
        Directionality.of(context),
      );
    }
  }

  Future<void> _speakAndResume(String message) async {
    if (!mounted || !_voiceEnabled) return;

    _voiceBusy = true;
    _silenceTimer?.cancel();

    try {
      await _speechService.stopListening();

      if (!mounted) return;

      final screenReaderActive =
          MediaQuery.maybeOf(context)?.accessibleNavigation ??
              _screenReaderActive;

      if (screenReaderActive) {
        SemanticsService.sendAnnouncement(
          View.of(context),
          message,
          Directionality.of(context),
        );

        final estimatedSpeechTime = Duration(
          milliseconds:
              (message.length * 75).clamp(1200, 9000).toInt(),
        );

        await Future<void>.delayed(estimatedSpeechTime);
      } else {
        await _voiceService.speak(message);
      }
    } catch (e) {
      debugPrint('Guest voice feedback error: $e');
    } finally {
      _voiceBusy = false;
    }

    if (mounted && _voiceEnabled && !_voiceProcessing) {
      await _listenForVoice();
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    final title = _pageTitle;

    final message = _pageRequirement;

    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        appBar: AppBar(
          title: Semantics(
            customSemanticsActions: {
              if (_voiceEnabled)
                const CustomSemanticsAction(
                  label: 'إيقاف التوجيه الصوتي',
                ): _switchToManual
              else
                const CustomSemanticsAction(
                  label: 'تفعيل التوجيه الصوتي',
                ): _enableVoiceMode,
            },
            child: Text(title),
          ),
        ),
        body: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 420),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Icon(
                      _isFavorites
                          ? Icons.favorite_border
                          : Icons.account_circle_outlined,
                      size: 72,
                      color: theme.colorScheme.primary,
                    ),
                    const SizedBox(height: 20),
                    Text(
                      title,
                      textAlign: TextAlign.center,
                      style: theme.textTheme.headlineSmall,
                    ),
                    const SizedBox(height: 12),
                    Text(
                      message,
                      textAlign: TextAlign.center,
                      style: theme.textTheme.bodyLarge,
                    ),
                    const SizedBox(height: 28),
                    FilledButton(
                      onPressed: () => _navigateToAuthPage(
                          _GuestAuthChoice.login,
                        ),
                      child: const Text('تسجيل الدخول'),
                    ),
                    const SizedBox(height: 12),
                    OutlinedButton(
                      onPressed: () => _navigateToAuthPage(
                        _GuestAuthChoice.signup,
                      ),
                      child: const Text('إنشاء حساب'),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
        bottomNavigationBar: AppBottomNavigation(
          currentIndex: _isFavorites ? 2 : 3,
          isSignedIn: false,
          onTap: (index) {
            if (index == 1) {
              Navigator.pop(context);
            } else if (index == 2 && !_isFavorites) {
              Navigator.pushReplacement(
                context,
                MaterialPageRoute<void>(
                  builder: (_) => const GuestAccessPage(
                    feature: GuestFeature.favorites,
                  ),
                ),
              );
            } else if (index == 3 && _isFavorites) {
              Navigator.pushReplacement(
                context,
                MaterialPageRoute<void>(
                  builder: (_) => const GuestAccessPage(
                    feature: GuestFeature.profile,
                  ),
                ),
              );
            }
          },
        ),
      ),
    );
  }
}