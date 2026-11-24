import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter/semantics.dart';

import 'dart:async';

import '../services/speech_recognition_service.dart';
import '../services/voice_feedback_service.dart';
import '../services/permission_service.dart';
import '../services/auth_service.dart';
import '../services/voice_navigation_service.dart';
import 'guest_access_page.dart';
import 'login_page.dart';

enum _VoiceMode { manual, commands, field, review }

enum _VoiceField { name, email }

class SignupPage extends StatefulWidget {
  const SignupPage({super.key});

  @override
  State<SignupPage> createState() => _SignupPageState();
}

class _SignupPageState extends State<SignupPage> {
  static final RegExp _emailPattern = RegExp(
    r"^[A-Za-z0-9!#$%&'*+/=?^_`{|}~-]+(?:\.[A-Za-z0-9!#$%&'*+/=?^_`{|}~-]+)*@[A-Za-z0-9](?:[A-Za-z0-9-]{0,61}[A-Za-z0-9])?(?:\.[A-Za-z0-9](?:[A-Za-z0-9-]{0,61}[A-Za-z0-9])?)+$",
  );
  static final RegExp _englishPrintableCharacters = RegExp(r'[\x21-\x7E]');
  static final RegExp _namePattern = RegExp(
    r"^[A-Za-z\u0621-\u064A\u066E-\u06D3\u06FA-\u06FC\u064B-\u065F\u0670\u06D6-\u06ED ]+$",
  );
  static final RegExp _allowedNameCharacters = RegExp(
    r"[A-Za-z\u0621-\u064A\u066E-\u06D3\u06FA-\u06FC\u064B-\u065F\u0670\u06D6-\u06ED ]",
  );

  final _formKey = GlobalKey<FormState>();
  final _nameFocusNode = FocusNode();
  final _emailFocusNode = FocusNode();
  final _nameController = TextEditingController();
  final _emailController = TextEditingController();
  final _authService = AuthService();
  final _speechService = SpeechRecognitionService.instance;
  final _voiceService = VoiceFeedbackService.instance;

  _VoiceMode _voiceMode = _VoiceMode.manual;
  _VoiceField? _activeVoiceField;

  bool _loading = false;
  bool _nameTouched = false;
  bool _emailTouched = false;
  bool _voiceEnabled = false;
  bool _voiceBusy = false;
  bool _voiceProcessing = false;
  bool _voiceRestartPending = false;
  bool _awaitingVoiceChoice = false;
  bool _screenReaderActive = false;
  bool _isLeavingPage = false;

  bool get _nameIsValid {
    final name = _nameController.text.trim();
    return name.length >= 2 && name.length <= 20 && _namePattern.hasMatch(name);
  }

  bool get _emailIsValid {
    final email = _emailController.text.trim();
    return email.isNotEmpty && _emailPattern.hasMatch(email);
  }

  Timer? _silenceTimer;

static const Duration _silenceTimeout = Duration(seconds: 8);

void _cancelSilenceTimer() {
  _silenceTimer?.cancel();
  _silenceTimer = null;
}


void _startSilenceTimer() {
  _cancelSilenceTimer();

  if (!mounted ||
      !_voiceEnabled ||
      _voiceBusy ||
      _voiceProcessing ||
      _loading ||
      _voiceMode == _VoiceMode.manual) {
    return;
  }

  _silenceTimer = Timer(_silenceTimeout, () {
    if (!mounted ||
        !_voiceEnabled ||
        _voiceBusy ||
        _voiceProcessing ||
        _loading ||
        _voiceMode == _VoiceMode.manual) {
      return;
    }

    String reminder;

    if (_awaitingVoiceChoice) {
      reminder =
          'هل تريد إدخال بياناتك صوتيًا؟ '
          'قل نعم لاستخدام الإدخال الصوتي، أو لا للإدخال اليدوي.';
    } else if (_voiceMode == _VoiceMode.field &&
        _activeVoiceField != null) {
      final fieldName =
          _activeVoiceField == _VoiceField.name
              ? 'حقل الاسم الكامل'
              : 'حقل البريد الإلكتروني';

      reminder =
          '$fieldName. '
          '${_fieldRequirements(_activeVoiceField!)} '
          'لم يصلني إدخال. يمكنك التحدث الآن.';
    } else if (_voiceMode == _VoiceMode.review) {
      reminder =
          'لم يصلني ردك. قولي تأكيد للمتابعة، '
          'أو إعادة المحاولة لإدخال المعلومة مرة أخرى، '
          'أو الانتقال إلى الإدخال اليدوي.';
    } else if (_voiceMode == _VoiceMode.commands &&
        _activeVoiceField == null &&
        _nameIsValid &&
        _emailIsValid) {
      reminder =
          'تم تأكيد الاسم والبريد الإلكتروني. '
          'قل إنشاء الحساب للمتابعة.';
    } else {
      reminder =
          'لم يصلني ردك. عندما تكون مستعدًا، '
          'قل بدء إدخال المعلومات.';
    }

    _speakAndResume(reminder);
  });
}


  Color get _successColor {
    return Theme.of(context).brightness == Brightness.dark
        ? Colors.green.shade300
        : Colors.green.shade800;
  }

  @override
  void dispose() {
    _voiceEnabled = false;
    _cancelSilenceTimer();

    _nameFocusNode.dispose();
    _emailFocusNode.dispose();

    _nameController.dispose();
    _emailController.dispose();

    super.dispose();
  }

  InputDecoration _fieldDecoration({
    required String labelText,
    required IconData prefixIcon,
    required bool touched,
    required bool isValid,
    Widget? suffixIcon,
  }) {
    final colors = Theme.of(context).colorScheme;
    final Color currentBorder = !touched
        ? colors.outline
        : isValid
        ? _successColor
        : colors.error;

    OutlineInputBorder outline(Color color, {double width = 1.2}) {
      return OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: color, width: width),
      );
    }

    return InputDecoration(
      labelText: labelText,
      prefixIcon: ExcludeSemantics(child: Icon(prefixIcon)),
      suffixIcon: suffixIcon,
      border: outline(colors.outline),
      enabledBorder: outline(currentBorder),
      focusedBorder: outline(currentBorder, width: 1.8),
      errorBorder: outline(colors.error),
      focusedErrorBorder: outline(colors.error, width: 1.8),
      errorMaxLines: 2,
    );
  }

  Future<void> _createAccount() async {
    if (!_formKey.currentState!.validate()) {
      _activeVoiceField = !_nameIsValid ? _VoiceField.name : _VoiceField.email;

      final error = _currentFieldError();
      if (error != null) {
        await _retryAfterValidationError(error);
      }
      return;
    }

    _cancelSilenceTimer();

    setState(() => _loading = true);

    try {
      final email = _emailController.text.trim().toLowerCase();

      // Check whether this address is already registered before sending
      // a sign-up link. Existing addresses must use the sign-in flow.
      final alreadyRegistered = await _authService.canSendSignInLink(email);
      if (alreadyRegistered) {
        const message = 'هذا البريد مستخدم بالفعل.';
        _showMessage(message);
        if (_voiceEnabled) {
          _activeVoiceField = _VoiceField.email;
          _voiceMode = _VoiceMode.field;
          _emailController.clear();
          setState(() => _emailTouched = false);
          await _speakAndResume(
            '$message يرجى إدخال بريد إلكتروني آخر غير مسجل.',
          );
        }
        return;
      }

      await _authService.sendSignUpLink(
        fullName: _nameController.text.trim(),
        email: email,
      );

      if (!mounted) return;

      final shouldSpeak = _voiceEnabled;
      await _stopVoiceListening();
      if (!mounted) return;

      if (!mounted) return;

      const message =
          'تم إرسال رابط إنشاء الحساب إلى بريدك الإلكتروني. '
          'يرجى التحقق من صندوق الوارد أو البريد المزعج '
          'وفتح الرابط لإكمال التسجيل والدخول إلى دُلّني.';

      _showMessage(message);

      if (shouldSpeak) {
        await _voiceService.speak(message);
      }
    } on FirebaseAuthException catch (e) {
      final message = _authError(e.code);
      _showMessage(message);
      await _speakAndResume(message);
    } catch (_) {
      const message = 'تعذر إنشاء الحساب. تحقق من الاتصال وحاول مجددًا.';
      _showMessage(message);
      await _speakAndResume(message);
    } finally {
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

  String _authError(String code) {
    switch (code) {
      case 'email-already-in-use':
        return 'هذا البريد مستخدم بالفعل.';
      case 'invalid-email':
        return 'البريد الإلكتروني غير صحيح.';
      case 'network-request-failed':
        return 'تعذر الاتصال بالإنترنت. تحقق من الاتصال وحاول مجددًا.';
      default:
        return 'تعذر إنشاء الحساب. حاول مجددًا.';
    }
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Semantics(
          excludeSemantics: true,
          liveRegion: true,
          label: message,
          child: Text(message),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;
        _handleBackNavigation();
      },
      child: Scaffold(
        appBar: AppBar(title: const Text('إنشاء حساب')),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 520),
              child: AutofillGroup(
                child: Form(
                  key: _formKey,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const ExcludeSemantics(
                        child: Icon(Icons.person_add_alt_1_outlined, size: 72),
                      ),
                      const SizedBox(height: 16),
                      Semantics(
                        header: true,
                        excludeSemantics: true,
                        label: _voiceEnabled
                            ? 'رحلة أسهل مع دلّني. صفحة إنشاء الحساب. '
                                  'يمكنك قول الانتقال إلى الإدخال اليدوي في أي وقت.'
                            : 'رحلة أسهل مع دُلّني. صفحة إنشاء الحساب. '
                                  'يمكنك إدخال بياناتك يدويًا باستخدام لوحة المفاتيح '
                                  'أو قارئ الشاشة. هل ترغب في استخدام الإدخال الصوتي؟ '
                                  'لتفعيله، استخدم الإجراء المخصص تفعيل الإدخال الصوتي.',
                        customSemanticsActions: _voiceEnabled
                            ? <CustomSemanticsAction, VoidCallback>{
                                CustomSemanticsAction(
                                  label: 'الانتقال إلى الإدخال اليدوي',
                                ): () =>
                                    unawaited(_switchToManual()),
                              }
                            : <CustomSemanticsAction, VoidCallback>{
                                CustomSemanticsAction(
                                  label: 'تفعيل الإدخال الصوتي',
                                ): () =>
                                    unawaited(_enableVoiceMode()),
                              },
                        child: Text(
                          'رحلة أسهل مع دُلّني',
                          style: theme.textTheme.headlineMedium,
                          textAlign: TextAlign.center,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'يمكنك إنشاء حساب لتخصيص تجربة الاستخدام.',
                        style: theme.textTheme.bodyLarge,
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 28),
                      TextFormField(
                        focusNode: _nameFocusNode,
                        controller: _nameController,
                        autofillHints: const [AutofillHints.name],
                        inputFormatters: [
                          FilteringTextInputFormatter.allow(
                            _allowedNameCharacters,
                          ),
                        ],
                        textInputAction: TextInputAction.next,
                        onFieldSubmitted: (_) => _emailFocusNode.requestFocus(),
                        textCapitalization: TextCapitalization.words,
                        autovalidateMode: AutovalidateMode.onUserInteraction,
                        decoration: _fieldDecoration(
                          labelText: 'الاسم الكامل',
                          prefixIcon: Icons.person_outline,
                          touched: _nameTouched,
                          isValid: _nameIsValid,
                        ),
                        onChanged: (_) {
                          setState(() => _nameTouched = true);
                        },
                        validator: (value) {
                          final name = value?.trim() ?? '';
                          if (name.isEmpty) {
                            return 'أدخل الاسم الكامل.';
                          }
                          if (!_namePattern.hasMatch(name)) {
                            return 'الاسم يقبل الحروف والمسافات فقط.';
                          }
                          if (name.length < 2 || name.length > 20) {
                            return 'الاسم يجب أن يكون بين حرفين و20 حرفًا.';
                          }
                          return null;
                        },
                      ),
                      const SizedBox(height: 16),
                      TextFormField(
                        focusNode: _emailFocusNode,
                        controller: _emailController,
                        inputFormatters: [
                          FilteringTextInputFormatter.allow(
                            _englishPrintableCharacters,
                          ),
                        ],
                        autofillHints: const [AutofillHints.newUsername],
                        autocorrect: false,
                        enableSuggestions: false,
                        textInputAction: TextInputAction.done,
                        onFieldSubmitted: (_) =>
                            _loading ? null : _createAccount(),
                        keyboardType: TextInputType.emailAddress,
                        textDirection: TextDirection.ltr,
                        autovalidateMode: AutovalidateMode.onUserInteraction,
                        decoration: _fieldDecoration(
                          labelText: 'البريد الإلكتروني',
                          prefixIcon: Icons.email_outlined,
                          touched: _emailTouched,
                          isValid: _emailIsValid,
                        ),
                        onChanged: (_) {
                          setState(() => _emailTouched = true);
                        },
                        validator: (value) {
                          final email = value?.trim() ?? '';
                          if (email.isEmpty) {
                            return 'أدخل البريد الإلكتروني.';
                          }
                          if (!_emailPattern.hasMatch(email)) {
                            return 'أدخل بريدًا إلكترونيًا صحيحًا.';
                          }
                          return null;
                        },
                      ),
                      const SizedBox(height: 24),
                      ElevatedButton(
                        onPressed: _loading ? null : _createAccount,
                        child: _loading
                            ? Semantics(
                                excludeSemantics: true,
                                liveRegion: true,
                                label: 'جارٍ إرسال رابط إنشاء الحساب',
                                child: SizedBox(
                                  height: 24,
                                  width: 24,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                ),
                              )
                            : const Text('إنشاء الحساب'),
                      ),
                      const SizedBox(height: 16),
                      Wrap(
                        alignment: WrapAlignment.center,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          const Text('هل لديك حساب بالفعل؟'),
                          TextButton(
                            onPressed: _loading
                          ? null
                          : () async {
                              _voiceEnabled = false;
                              _silenceTimer?.cancel();
                              _voiceRestartPending = false;

                              await _speechService.cancelListening();
                              await _voiceService.stop();

                              if (!mounted) return;

                              Navigator.pushReplacement(
                                context,
                                MaterialPageRoute<void>(
                                  builder: (_) => const LoginPage(),
                                ),
                              );
                            },
                            child: const Text('تسجيل الدخول'),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  @override
  void initState() {
    super.initState();

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _startSignupVoiceGuide();
    });
  }

  Future<void> _startSignupVoiceGuide() async {
    if (!mounted) return;

    // When accessibility navigation is active, leave the page in manual
    // mode so the app's TTS does not compete with TalkBack or another reader.
    _screenReaderActive =
        MediaQuery.maybeOf(context)?.accessibleNavigation ?? false;

    if (_screenReaderActive) {
      if (mounted) {
        setState(() {
          _voiceEnabled = false;
          _voiceMode = _VoiceMode.manual;
        });
      }
      return;
    }

    try {
      await _voiceService.initialize();
      if (!mounted || _isLeavingPage) return;

      final ready = await _speechService.initialize(
        onStatus: _handleSpeechStatus,
        onError: (message) {
          debugPrint('Speech error: $message');
        },
      );

      if (!mounted || _isLeavingPage || !ready) return;

      setState(() {
        _voiceEnabled = true;
        _voiceMode = _VoiceMode.commands;
        _awaitingVoiceChoice = true;
      });

      await _speakAndResume(
        'مرحبًا بك في صفحة إنشاء الحساب في تطبيق دُلّني. '
        'يمكنك إدخال بياناتك صوتيًا أو يدويًا باستخدام لوحة المفاتيح '
        'أو قارئ الشاشة. هل ترغب في استخدام الإدخال الصوتي؟ '
        'قل نعم لاستخدامه، أو لا للانتقال إلى الإدخال اليدوي.',
      );
    } catch (e) {
      debugPrint('Signup voice initialization error: $e');
      if (mounted && !_isLeavingPage) {
        setState(() {
          _voiceEnabled = false;
          _voiceMode = _VoiceMode.manual;
        });
      }
    }
  }

  Future<void> _handleVoiceNavigation(
  VoiceNavigationAction action,
) async {
  switch (action) {
    case VoiceNavigationAction.home:
      Navigator.popUntil(context, (route) => route.isFirst);
      break;

    case VoiceNavigationAction.favorites:
      Navigator.popUntil(context, (route) => route.isFirst);
      Navigator.push(
        context,
        MaterialPageRoute<void>(
          builder: (_) => const GuestAccessPage(
            feature: GuestFeature.favorites,
          ),
        ),
      );
      break;

    case VoiceNavigationAction.profile:
      Navigator.popUntil(context, (route) => route.isFirst);
      Navigator.push(
        context,
        MaterialPageRoute<void>(
          builder: (_) => const GuestAccessPage(
            feature: GuestFeature.profile,
          ),
        ),
      );
      break;

    case VoiceNavigationAction.login:
      Navigator.pushReplacement(
        context,
        MaterialPageRoute<void>(
          builder: (_) => const LoginPage(),
        ),
      );
      break;

    case VoiceNavigationAction.signup:
    case VoiceNavigationAction.logout:
      break;
  }
}

Future<void> _startGeneralVoiceNavigation() async {
  _voiceEnabled = false;
  await _stopVoiceListening();

  if (!mounted) return;

  final started = await VoiceNavigationService.instance.start(
    context: context,
    currentPage: VoiceNavigationPage.signup,
    isSignedIn: false,
    onNavigate: _handleVoiceNavigation,
    onComplete: () async {
      if (!mounted) return;

      _voiceEnabled = true;
      _voiceMode = _VoiceMode.commands;
      _awaitingVoiceChoice = false;

      await _speakAndResume(
        'سنُدخل البيانات بالترتيب التالي: الاسم الكامل، '
        'ثم البريد الإلكتروني فقط. '
        'عندما تكون مستعدًا، قل: بدء إدخال المعلومات.',
      );
    },
  );

  if (!started && mounted) {
    _voiceEnabled = true;
    _voiceMode = _VoiceMode.commands;
    _awaitingVoiceChoice = false;

    await _speakAndResume(
      'سنُدخل البيانات بالترتيب التالي: الاسم الكامل، '
      'ثم البريد الإلكتروني فقط. '
      'عندما تكون مستعدًا، قل: بدء إدخال المعلومات.',
    );
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

    debugPrint('SIGNUP: Starting voice listening...');

    final isEmailField =
        _voiceMode == _VoiceMode.field &&
        _activeVoiceField == _VoiceField.email;

    final selectedLocale = isEmailField
        ? _speechService.englishLocaleId
        : _speechService.arabicLocaleId;

    if (isEmailField && selectedLocale == null) {
      const message =
          'لغة التعرف على الكلام الإنجليزية غير متاحة في الجهاز. '
          'يرجى تفعيل خدمة التعرف على الكلام باللغة الإنجليزية، '
          'أو الانتقال إلى الإدخال اليدوي لإدخال البريد الإلكتروني.';

      _showMessage(message);

      final screenReaderActive =
          MediaQuery.maybeOf(context)?.accessibleNavigation ??
          _screenReaderActive;
      if (screenReaderActive) {
        SemanticsService.sendAnnouncement(
          View.of(context),
          message,
          Directionality.of(context),
        );
      } else {
        await _voiceService.speak(message);
      }
      await _switchToManual();
      return;
    }

        final hasMicrophonePermission =
        await PermissionService.requestMicrophonePermission(context);

    if (!mounted) return;

    if (!hasMicrophonePermission) {
      await _switchToManual();
      return;
    }

    final started = await _speechService.startListening(
      onResult: (recognizedText) {
        debugPrint('SIGNUP RECOGNIZED: "$recognizedText"');
        _handleVoiceResult(recognizedText);
      },
      onStatus: _handleSpeechStatus,
      onError: (message) {
        debugPrint('SIGNUP SPEECH ERROR: $message');
      },
      localeId: selectedLocale,
      useLastPartialOnStop: true,
    );
    debugPrint('SIGNUP: Listening started = $started');
    if (started) {
  _startSilenceTimer();
}

    if (!started && mounted && _voiceEnabled) {
      debugPrint('SIGNUP: Could not start listening.');
    }
  }

  void _handleSpeechStatus(String status) {
    debugPrint('SIGNUP SPEECH STATUS: $status');

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

    _cancelSilenceTimer();

    debugPrint('SIGNUP: Processing voice result: $text');

    _voiceProcessing = true;
    _voiceRestartPending = false;

    try {
      switch (_voiceMode) {
        case _VoiceMode.manual:
          return;

        case _VoiceMode.commands:
          await _handleVoiceCommand(text);
          break;

        case _VoiceMode.field:
          await _handleFieldInput(text);
          break;

        case _VoiceMode.review:
          await _handleReviewCommand(text);
          break;
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

  Future<void> _handleVoiceCommand(String text) async {
    final command = _normalizeArabic(text);

    debugPrint('SIGNUP COMMAND: "$command"');

    if (_isSwitchToManualCommand(command)) {
      await _switchToManual();
      return;
    }

    // Initial choice: the user can choose voice or manual entry.
    if (_awaitingVoiceChoice) {
      if (command == 'نعم' ||
          command == 'اي' ||
          command == 'ايوه' ||
          command == 'ابغى' ||
          command == 'ارغب') {
        _awaitingVoiceChoice = false;
        await _startGeneralVoiceNavigation();
        return;
      }

      if (command == 'لا' ||
      command.contains('ادخال يدوي') ||
      command.contains('استخدام لوحة المفاتيح')) {
    _awaitingVoiceChoice = false;

    await _speakAndResume(
      'حسنًا، سيتم الانتقال إلى الإدخال اليدوي. '
    );

    await _switchToManual();
    return;
  }

      await _speakAndResume(
        'لم أفهم اختيارك. قل نعم لاستخدام الإدخال الصوتي، '
        'أو لا لاستخدام الإدخال اليدوي.',
      );
      return;
    }

    if (command.contains('بدء ادخال المعلومات') ||
        command.contains('ابدا ادخال المعلومات') ||
        command.contains('ابدأ إدخال المعلومات' ) ||
      command.contains('ابدء ادخال المعلومات')) {
      final nextField = _firstIncompleteVoiceField();
      if (nextField != null) {
        await _startFieldCapture(nextField);
      } else {
        _activeVoiceField = null;
        await _speakAndResume(
          'الاسم والبريد الإلكتروني صحيحان. '
          'قل إنشاء الحساب للمتابعة.',
        );
      }
      return;
    }

    if (command.contains('انشاء الحساب') || command.contains('انشاء حساب')) {
      if (_activeVoiceField != null) {
        await _speakAndResume(
          'لم تنتهِ من إدخال جميع البيانات بعد. '
          'يرجى إكمال الحقول أولًا.',
        );
        return;
      }

      await _speechService.stopListening();

      if (mounted) {
        await _createAccount();
      }
      return;
    }

    final reminder = _nameIsValid &&
        _emailIsValid &&
        _activeVoiceField == null
    ? 'لم أتعرف على الأمر. قل إنشاء الحساب للمتابعة.'
    : 'لم أتعرف على الأمر. عندما تكون مستعدًا، '
        'قل بدء إدخال المعلومات.';

await _speakAndResume(reminder);
  }

  bool _isSwitchToManualCommand(String normalizedCommand) {
    return normalizedCommand.contains('الانتقال الى الادخال اليدوي') ||
        normalizedCommand.contains('انتقال الى الادخال اليدوي') ||
        normalizedCommand.contains('switch to manual input');
  }

  Future<void> _switchToManual() async {
    if (!mounted) return;

    _cancelSilenceTimer();

    final fieldToFocus = _activeVoiceField;
    _voiceRestartPending = false;
    _awaitingVoiceChoice = false;
    _voiceEnabled = false;
    _voiceBusy = true;

    await _speechService.cancelListening();
    await _voiceService.stop();

    if (!mounted) return;

    setState(() {
      _voiceMode = _VoiceMode.manual;
      _voiceEnabled = false;
      _voiceBusy = false;
    });

    // Keep all controllers and their values intact.
    final focusNode = _focusNodeForField(
      fieldToFocus ?? _firstIncompleteVoiceField(),
    );
    if (focusNode != null) {
      focusNode.requestFocus();
    }

    final screenReaderActive =
        MediaQuery.maybeOf(context)?.accessibleNavigation ??
        _screenReaderActive;
    if (screenReaderActive) {
      SemanticsService.sendAnnouncement(
        View.of(context),
        'تم الانتقال إلى الإدخال اليدوي. جميع البيانات المدخلة محفوظة.',
        Directionality.of(context),
      );
    }
  }

  FocusNode? _focusNodeForField(_VoiceField? field) {
    switch (field) {
      case _VoiceField.name:
        return _nameFocusNode;
      case _VoiceField.email:
        return _emailFocusNode;
      case null:
        return null;
    }
  }

  _VoiceField? _firstIncompleteVoiceField() {
    final previousField = _activeVoiceField;
    for (final field in _VoiceField.values) {
      _activeVoiceField = field;
      if (_currentFieldError() != null) {
        _activeVoiceField = previousField;
        return field;
      }
    }
    _activeVoiceField = previousField;
    return null;
  }

  Future<void> _enableVoiceMode() async {
    if (!mounted || _voiceEnabled || _loading) return;

    try {
      await _voiceService.initialize();
      final ready = await _speechService.initialize(
        onStatus: _handleSpeechStatus,
        onError: (message) => debugPrint('Speech error: $message'),
      );

      if (!mounted || !ready) return;

      setState(() {
        _voiceEnabled = true;
        _voiceMode = _VoiceMode.commands;
        _awaitingVoiceChoice = false;
      });

      final nextField = _firstIncompleteVoiceField();
      if (nextField != null) {
        await _startFieldCapture(nextField);
      } else {
        _activeVoiceField = null;
        await _speakAndResume(
          'الاسم والبريد الإلكتروني صحيحان. '
          'قل إنشاء الحساب لمتابعة إنشاء الحساب.',
        );
      }
    } catch (e) {
      debugPrint('Could not enable signup voice mode: $e');
    }
  }

  Future<void> _handleReviewCommand(String text) async {
    final command = _normalizeArabic(text);

    debugPrint('SIGNUP REVIEW COMMAND: "$command"');

    if (_isSwitchToManualCommand(command)) {
      await _switchToManual();
      return;
    }

    if (command.contains('اعادة المحاولة') ||
        command.contains('اعاده المحاوله') ||
        command == 'اعادة' ||
        command == 'اعد') {
      final field = _activeVoiceField;
      if (field != null) {
        await _startFieldCapture(field);
      }
      return;
    }

    if (command == 'تاكيد' ||
        command == 'اكد' ||
        command.contains('تاكيد الادخال') ||
        command.contains('نعم تاكيد')) {
      await _advanceAfterConfirmation();
      return;
    }

    const options =
        'قل تأكيد لاعتماد الإدخال، '
        'أو إعادة المحاولة لإدخاله من جديد، '
        'أو الانتقال إلى الإدخال اليدوي.';

    await _speakAndResume('لم أتعرف على اختيارك. $options');
  }

  Future<void> _advanceAfterConfirmation() async {
    switch (_activeVoiceField) {
      case _VoiceField.name:
        await _startFieldCapture(_VoiceField.email);
        break;

      case _VoiceField.email:
        _activeVoiceField = null;
        _voiceMode = _VoiceMode.commands;
        await _speakAndResume(
          'تم تأكيد الاسم والبريد الإلكتروني بنجاح. '
          'لإنشاء حسابك، قل: إنشاء الحساب.',
        );
        break;

      case null:
        await _speakAndResume('لا يوجد حقل ينتظر التأكيد حاليًا.');
        break;
    }
  }

  String _fieldRequirements(_VoiceField field) {
    switch (field) {
      case _VoiceField.name:
        return 'يجب أن يكون الاسم مكونًا من حرفين على الأقل '
            'و20 حرفًا كحد أقصى، '
            'ويسمح باستخدام الحروف العربية أو الإنجليزية والمسافات فقط.';

      case _VoiceField.email:
        return 'يجب إدخال بريد إلكتروني صحيح باللغة الإنجليزية، '
            'مثل example@gmail.com، '
            'ولا يُسمح بإدخال مسافات.';
    }
  }

  Future<void> _startFieldCapture(
    _VoiceField field, {
    bool clearExisting = true,
  }) async {
    if (!mounted) return;

    _activeVoiceField = field;
    _voiceMode = _VoiceMode.field;

    final requirements = _fieldRequirements(field);

    switch (field) {
      case _VoiceField.name:
        if (clearExisting) {
          _nameController.clear();
          setState(() => _nameTouched = false);
        }

        await _speakAndResume(
          'أنت الآن في حقل الاسم الكامل. '
          '$requirements '
          'ابدأ بإدخال اسمك. ',
        );
        break;

      case _VoiceField.email:
        if (clearExisting) {
          _emailController.clear();
          setState(() => _emailTouched = false);
        }

        await _speakAndResume(
          'أنت الآن في حقل البريد الإلكتروني. '
          '$requirements '
          'يمكنك قول نقطة أو دوت لإدخال النقطة، '
          'وعند أو آت لإدخال علامة آت، '
          'وشرطة أو داش لإدخال الشرطة، '
          'وشرطة سفلية أو أندر سكور لإدخال الشرطة السفلية. '
          'ابدأ بإدخال بريدك الإلكتروني. ',
        );
        break;
    }
  }

  Future<void> _handleFieldInput(String text) async {
    if (_activeVoiceField == null) return;

    final normalizedCommand = _normalizeArabic(text);
    if (_isSwitchToManualCommand(normalizedCommand)) {
      await _switchToManual();
      return;
    }

    debugPrint(
      'SIGNUP FIELD INPUT: "$text" | '
      'Field: $_activeVoiceField',
    );

    // استبدال محتوى الحقل بالنص الذي تم التعرف عليه.
    _appendVoiceInput(text);

    // التحقق من صحة الإدخال.
    final error = _currentFieldError();

    if (error != null) {
      await _retryAfterValidationError(error);
      return;
    }

    // الإدخال صحيح، انتقل إلى وضع التأكيد.
    _voiceMode = _VoiceMode.review;

    switch (_activeVoiceField!) {
      case _VoiceField.name:
        await _speakAndResume(
          'تم التقاط الاسم التالي: '
          '${_nameController.text}. '
          'قل تأكيد لاعتماد الاسم، '
          'أو إعادة المحاولة لإدخاله من جديد، '
          'أو الانتقال إلى الإدخال اليدوي.',
        );
        break;

      case _VoiceField.email:
        await _speakAndResume(
          'تم التقاط البريد الإلكتروني التالي: '
          '${_emailController.text}. '
          'قل تأكيد لاعتماد البريد، '
          'أو إعادة المحاولة لإدخاله من جديد، '
          'أو الانتقال إلى الإدخال اليدوي.',
        );
        break;
    }
  }

  void _appendVoiceInput(String recognizedText) {
    if (!mounted || _activeVoiceField == null) return;

    String value = recognizedText.trim();

    switch (_activeVoiceField!) {
      case _VoiceField.name:
        value = value
            .replaceAll(RegExp(r'^[.,،؛:!?؟]+|[.,،؛:!?؟]+$'), '')
            .trim();

        _nameController.text = value;

        setState(() {
          _nameTouched = true;
        });
        break;

      case _VoiceField.email:
        value = _normalizeEmailVoiceInput(value);

        _emailController.text = value;

        setState(() {
          _emailTouched = true;
        });
        break;
    }

    debugPrint('SIGNUP: Input assigned to $_activeVoiceField');
  }

  void _clearActiveVoiceField() {
    if (!mounted || _activeVoiceField == null) return;

    switch (_activeVoiceField!) {
      case _VoiceField.name:
        _nameController.clear();
        setState(() => _nameTouched = false);
        break;

      case _VoiceField.email:
        _emailController.clear();
        setState(() => _emailTouched = false);
        break;
    }
  }

  Future<void> _retryAfterValidationError(String error) async {
    final field = _activeVoiceField;

    if (field == null) return;

    debugPrint('SIGNUP VALIDATION ERROR: $error | Field: $field');

    // عرض الخطأ للمستخدم دون عرض محتوى الحقل.
    _showMessage(error);

    // حذف الإدخال غير الصحيح.
    _clearActiveVoiceField();

    // العودة إلى وضع إدخال البيانات.
    _voiceMode = _VoiceMode.field;

    await _speakAndResume(
      '$error '
      'تم حذف الإدخال السابق. '
      'يرجى إعادة إدخال ${_fieldName(field)} من جديد.',
    );
  }

  String _fieldName(_VoiceField field) {
    switch (field) {
      case _VoiceField.name:
        return 'الاسم الكامل';

      case _VoiceField.email:
        return 'البريد الإلكتروني';
    }
  }

  String _normalizeEmailVoiceInput(String text) {
  String result = text.toLowerCase().trim();

  final replacements = <String, String>{
    'شرطة سفلية': '_',
    'اندر سكور': '_',
    'underscore': '_',
    'نقطة': '.',
    'دوت': '.',
    'dot': '.',
    'عند': '@',
    'آت': '@',
    'ات': '@',
    'شرطة': '-',
    'داش': '-',
    'dash': '-',
  };

  replacements.forEach((word, symbol) {
    result = result.replaceAll(word, symbol);
  });

  // Replace English "at" only when spoken as a separate word.
  result = result.replaceAll(
    RegExp(r'(?<![a-z0-9])at(?![a-z0-9])'),
    '@',
  );

result = result.replaceAll(RegExp(r'\s+'), '');
result = result.replaceFirst(RegExp(r'[.,،؛:!?؟]+$'), '');

return result;
}

  String? _currentFieldError() {
    switch (_activeVoiceField) {
      case _VoiceField.name:
        final name = _nameController.text.trim();

        if (name.isEmpty) {
          return 'لم يتم إدخال الاسم بعد.';
        }
        if (name.length < 2) {
          return 'الاسم أقل من حرفين. يرجى إدخال حرفين على الأقل.';
        }
        if (name.length > 20) {
          return 'الاسم تجاوز 20 حرفًا. يرجى اختصار الاسم.';
        }
        if (!_namePattern.hasMatch(name)) {
          return 'الاسم يقبل الحروف والمسافات فقط.';
        }
        return null;

      case _VoiceField.email:
        final email = _emailController.text.trim();

        if (email.isEmpty) {
          return 'لم يتم إدخال البريد الإلكتروني بعد.';
        }
        if (!_emailPattern.hasMatch(email)) {
          return 'صيغة البريد الإلكتروني غير صحيحة. تحقق من كتابة البريد.';
        }
        return null;

      case null:
        return null;
    }
  }

  Future<void> _speakAndResume(String message) async {
    if (!mounted || !_voiceEnabled) return;

    _cancelSilenceTimer();

    _voiceBusy = true;

    try {
      await _speechService.stopListening();

      if (!mounted) return;

      final screenReaderActive =
          MediaQuery.maybeOf(context)?.accessibleNavigation ??
          _screenReaderActive;
      if (screenReaderActive) {
        // Route announcements through the active screen reader instead of
        // starting a second TTS engine over TalkBack.
        SemanticsService.sendAnnouncement(
          View.of(context),
          message,
          Directionality.of(context),
        );
        final estimatedSpeechTime = Duration(
          milliseconds: (message.length * 75).clamp(1200, 9000).toInt(),
        );
        await Future<void>.delayed(estimatedSpeechTime);
      } else {
        await _voiceService.speak(message);
      }
    } catch (e) {
      debugPrint('Voice feedback error: $e');
    } finally {
      _voiceBusy = false;
    }

    if (mounted && _voiceEnabled && !_voiceProcessing) {
      await _listenForVoice();
    }
  }

  Future<void> _stopVoiceListening() async {
    _cancelSilenceTimer();
    _voiceEnabled = false;
    await _speechService.cancelListening();
    await _voiceService.stop();
  }

  Future<void> _handleBackNavigation() async {
  if (_isLeavingPage) return;

  _isLeavingPage = true;
  _voiceEnabled = false;
  _voiceRestartPending = false;
  _cancelSilenceTimer();

  await _speechService.cancelListening();
  await _voiceService.stop();

  if (!mounted) return;

  Navigator.of(context).pop();
}

  
}
