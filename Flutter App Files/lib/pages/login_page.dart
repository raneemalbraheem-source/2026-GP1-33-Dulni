
import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter/semantics.dart';

import '../services/auth_service.dart';
import '../services/speech_recognition_service.dart';
import '../services/voice_feedback_service.dart';
import 'signup_page.dart';

enum _LoginVoiceMode { manual, commands, field, review }

class LoginPage extends StatefulWidget {
  const LoginPage({super.key});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  static final RegExp _emailPattern = RegExp(
    r"^[A-Za-z0-9!#$%&'*+/=?^_`{|}~-]+(?:\.[A-Za-z0-9!#$%&'*+/=?^_`{|}~-]+)*@[A-Za-z0-9](?:[A-Za-z0-9-]{0,61}[A-Za-z0-9])?(?:\.[A-Za-z0-9](?:[A-Za-z0-9-]{0,61}[A-Za-z0-9])?)+$",
  );

  static final RegExp _englishPrintableCharacters =
      RegExp(r'[\x21-\x7E]');

  final _formKey = GlobalKey<FormState>();
  final _emailFocusNode = FocusNode();
  final _emailController = TextEditingController();

  final _authService = AuthService();
  final _speechService = SpeechRecognitionService.instance;
  final _voiceService = VoiceFeedbackService.instance;

  _LoginVoiceMode _voiceMode = _LoginVoiceMode.manual;

  bool _loading = false;
  bool _emailTouched = false;
  bool _voiceEnabled = false;
  bool _voiceBusy = false;
  bool _voiceProcessing = false;
  bool _voiceRestartPending = false;
  bool _awaitingVoiceChoice = false;
  bool _emailConfirmed = false;
  bool _screenReaderActive = false;

  Timer? _silenceTimer;

  bool get _emailIsValid {
    final email = _emailController.text.trim();
    return email.isNotEmpty && _emailPattern.hasMatch(email);
  }

  Color get _successColor {
    return Theme.of(context).brightness == Brightness.dark
        ? Colors.green.shade300
        : Colors.green.shade800;
  }

  @override
  void initState() {
    super.initState();

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _startLoginVoiceGuide();
    });
  }

  @override
  void dispose() {
    _voiceEnabled = false;
    _silenceTimer?.cancel();

    unawaited(_speechService.cancelListening());
    unawaited(_voiceService.stop());

    _emailFocusNode.dispose();
    _emailController.dispose();

    super.dispose();
  }

  InputDecoration _fieldDecoration({
    required String labelText,
    required IconData prefixIcon,
    required bool touched,
    required bool isValid,
  }) {
    final colors = Theme.of(context).colorScheme;

    final currentBorder = !touched
        ? colors.outline
        : isValid
            ? _successColor
            : colors.error;

    OutlineInputBorder outline(
      Color color, {
      double width = 1.2,
    }) {
      return OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(
          color: color,
          width: width,
        ),
      );
    }

    return InputDecoration(
      labelText: labelText,
      helperText: 'أدخل البريد الإلكتروني المرتبط بحسابك في دُلّني.',
      prefixIcon: ExcludeSemantics(
        child: Icon(prefixIcon),
      ),
      border: outline(colors.outline),
      enabledBorder: outline(currentBorder),
      focusedBorder: outline(currentBorder, width: 1.8),
      errorBorder: outline(colors.error),
      focusedErrorBorder: outline(colors.error, width: 1.8),
      errorMaxLines: 2,
    );
  }

  Future<void> _startLoginVoiceGuide() async {
    if (!mounted) return;

    _screenReaderActive =
        MediaQuery.maybeOf(context)?.accessibleNavigation ?? false;

    // لا نشغل صوت التطبيق تلقائيًا أثناء استخدام قارئ الشاشة.
    if (_screenReaderActive) {
      return;
    }

    try {
      await _voiceService.initialize();

      final ready = await _speechService.initialize(
        onStatus: _handleSpeechStatus,
        onError: (message) {
          debugPrint('Login speech error: $message');
        },
      );

      if (!mounted || !ready) return;

      setState(() {
        _voiceEnabled = true;
        _voiceMode = _LoginVoiceMode.commands;
        _awaitingVoiceChoice = true;
      });

      await _speakAndResume(
        'مرحبًا بك في صفحة تسجيل الدخول في تطبيق دُلّني. '
        'يمكنك تسجيل الدخول باستخدام الإدخال الصوتي أو اليدوي. '
        'هل ترغب في استخدام الإدخال الصوتي؟ '
        'قل نعم لاستخدامه، أو لا للانتقال إلى الإدخال اليدوي.',
      );
    } catch (e) {
      debugPrint('Login voice initialization error: $e');
      if (!mounted) return;

      setState(() {
        _voiceEnabled = false;
        _voiceMode = _LoginVoiceMode.manual;
      });
    }
  }

  Future<void> _enableVoiceMode() async {
    if (!mounted || _voiceEnabled || _loading) return;

    try {
      await _voiceService.initialize();

      final ready = await _speechService.initialize(
        onStatus: _handleSpeechStatus,
        onError: (message) {
          debugPrint('Login speech error: $message');
        },
      );

      if (!mounted || !ready) return;

      setState(() {
        _voiceEnabled = true;
        _voiceMode = _LoginVoiceMode.commands;
        _awaitingVoiceChoice = false;
      });

      await _startEmailCapture();
    } catch (e) {
      debugPrint('Could not enable login voice mode: $e');

      if (mounted) {
        _showMessage('تعذر تفعيل الإدخال الصوتي. يمكنك استخدام الإدخال اليدوي.');
      }
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

    final localeId = _speechService.englishLocaleId;

    if (localeId == null) {
      await _reportMessage(
        'لغة التعرف على الكلام الإنجليزية غير متاحة. '
        'يرجى تفعيلها أو الانتقال إلى الإدخال اليدوي.',
      );
      await _switchToManual();
      return;
    }

    final started = await _speechService.startListening(
      onResult: (recognizedText) {
        debugPrint('LOGIN RECOGNIZED: "$recognizedText"');
        _silenceTimer?.cancel();
        _handleVoiceResult(recognizedText);
      },
      onStatus: _handleSpeechStatus,
      onError: (message) {
        debugPrint('LOGIN SPEECH ERROR: $message');
      },
      localeId: localeId,
      useLastPartialOnStop: true,
    );

    debugPrint('LOGIN: Listening started = $started');

    if (started && mounted && _voiceEnabled) {
      _startSilenceTimer();
    }
  }

  void _startSilenceTimer() {
    _silenceTimer?.cancel();

    if (_voiceMode != _LoginVoiceMode.field) return;

    _silenceTimer = Timer(const Duration(seconds: 8), () async {
      if (!mounted ||
          !_voiceEnabled ||
          _voiceMode != _LoginVoiceMode.field ||
          _voiceProcessing ||
          _voiceBusy) {
        return;
      }

      await _speakAndResume(
        'لم أسمع إدخالًا حتى الآن. '
        'يرجى قول بريدك الإلكتروني باللغة الإنجليزية. '
        'يمكنك قول نقطة أو دوت لإدخال النقطة، '
        'وعند أو آت لإدخال علامة آت.',
      );
    });
  }

  void _handleSpeechStatus(String status) {
    debugPrint('LOGIN SPEECH STATUS: $status');

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
      switch (_voiceMode) {
        case _LoginVoiceMode.manual:
          return;

        case _LoginVoiceMode.commands:
          await _handleVoiceCommand(text);
          break;

        case _LoginVoiceMode.field:
          await _handleEmailInput(text);
          break;

        case _LoginVoiceMode.review:
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
        .trim()
        .toLowerCase();
  }

  Future<void> _handleVoiceCommand(String text) async {
    final command = _normalizeArabic(text);

    if (_isSwitchToManualCommand(command)) {
      await _switchToManual();
      return;
    }

    if (_awaitingVoiceChoice) {
      if (command == 'نعم' ||
          command == 'اي' ||
          command == 'ايوه' ||
          command == 'ابغى' ||
          command == 'ارغب') {
        _awaitingVoiceChoice = false;

        await _speakAndResume(
          'سنستخدم الإدخال الصوتي لإدخال البريد الإلكتروني. '
          'يجب أن يكون البريد صحيحًا باللغة الإنجليزية، '
          'مثل example@gmail.com. '
          'عندما تكون مستعدًا، قل: بدء إدخال المعلومات.',
        );
        return;
      }

      if (command == 'لا' ||
          command.contains('ادخال يدوي') ||
          command.contains('استخدام لوحة المفاتيح')) {
        _awaitingVoiceChoice = false;
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
        command.contains('ابدأ إدخال المعلومات')) {
      await _startEmailCapture();
      return;
    }

    if (command.contains('تسجيل الدخول') ||
        command.contains('سجل الدخول')) {
      if (!_emailConfirmed) {
        await _speakAndResume(
          'يجب تأكيد البريد الإلكتروني أولًا. '
          'قل بدء إدخال المعلومات لإدخال البريد.',
        );
        return;
      }

      await _speechService.stopListening();

      if (mounted) {
        await _login();
      }
      return;
    }

    await _speakAndResume(
      'لم أتعرف على الأمر. '
      'عندما تكون مستعدًا، قل بدء إدخال المعلومات.',
    );
  }

  bool _isSwitchToManualCommand(String command) {
    return command.contains('الانتقال الى الادخال اليدوي') ||
        command.contains('انتقال الى الادخال اليدوي') ||
        command.contains('switch to manual input');
  }

  Future<void> _startEmailCapture({bool clearExisting = true}) async {
    if (!mounted) return;

    _voiceMode = _LoginVoiceMode.field;
    _emailConfirmed = false;

    if (clearExisting) {
      _emailController.clear();
      setState(() => _emailTouched = false);
    }

    await _speakAndResume(
      'أنت الآن في حقل البريد الإلكتروني. '
      'أدخل بريدك باللغة الإنجليزية دون مسافات. '
      'يمكنك قول نقطة أو دوت لإدخال النقطة، '
      'وعند أو آت لإدخال علامة آت، '
      'وشرطة أو داش لإدخال الشرطة، '
      'وشرطة سفلية أو أندر سكور لإدخال الشرطة السفلية. '
      'ابدأ بإدخال بريدك الإلكتروني.',
    );
  }

  Future<void> _handleEmailInput(String text) async {
    final command = _normalizeArabic(text);

    if (_isSwitchToManualCommand(command)) {
      await _switchToManual();
      return;
    }

    final email = _normalizeEmailVoiceInput(text);

    _emailController.text = email;
    setState(() => _emailTouched = true);

    if (!_emailIsValid) {
      _emailController.clear();
      setState(() => _emailTouched = false);

      await _reportMessage(
        'صيغة البريد الإلكتروني غير صحيحة. '
        'تم حذف الإدخال السابق. يرجى إدخال بريد صحيح باللغة الإنجليزية.',
      );

      _voiceMode = _LoginVoiceMode.field;
      return;
    }

    _voiceMode = _LoginVoiceMode.review;

    await _speakAndResume(
      'تم التقاط البريد الإلكتروني التالي: $email. '
      'قل تأكيد لاعتماد البريد، '
      'أو إعادة المحاولة لإدخاله من جديد، '
      'أو الانتقال إلى الإدخال اليدوي.',
    );
  }

  String _normalizeEmailVoiceInput(String text) {
    String result = text.toLowerCase().trim();

    const replacements = <String, String>{
      'شرطة سفلية': '_',
      'اندر سكور': '_',
      'underscore': '_',
      'نقطة': '.',
      'دوت': '.',
      'dot': '.',
      'عند': '@',
      'ات': '@',
      'آت': '@',
      'at': '@',
      'شرطة': '-',
      'داش': '-',
      'dash': '-',
    };

    replacements.forEach((word, symbol) {
      result = result.replaceAll(word, symbol);
    });

    return result.replaceAll(RegExp(r'\s+'), '');
  }

  Future<void> _handleReviewCommand(String text) async {
    final command = _normalizeArabic(text);

    if (_isSwitchToManualCommand(command)) {
      await _switchToManual();
      return;
    }

    if (command.contains('اعادة المحاولة') ||
        command.contains('اعاده المحاوله') ||
        command == 'اعادة' ||
        command == 'اعد') {
      await _startEmailCapture();
      return;
    }

    if (command == 'تاكيد' ||
        command == 'اكد' ||
        command.contains('تاكيد الادخال') ||
        command.contains('نعم تاكيد')) {
      _emailConfirmed = true;
      _voiceMode = _LoginVoiceMode.commands;

      await _speakAndResume(
        'تم تأكيد البريد الإلكتروني بنجاح. '
        'لإرسال رابط تسجيل الدخول، قل: تسجيل الدخول.',
      );
      return;
    }

    await _speakAndResume(
      'لم أفهم اختيارك. قل تأكيد لاعتماد البريد، '
      'أو إعادة المحاولة لإدخاله من جديد، '
      'أو الانتقال إلى الإدخال اليدوي.',
    );
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
      _voiceMode = _LoginVoiceMode.manual;
      _voiceEnabled = false;
      _voiceBusy = false;
    });

    _emailFocusNode.requestFocus();

    final screenReaderActive =
        MediaQuery.maybeOf(context)?.accessibleNavigation ??
            _screenReaderActive;

    if (screenReaderActive) {
      SemanticsService.sendAnnouncement(
        View.of(context),
        'تم الانتقال إلى الإدخال اليدوي. يمكنك إدخال بريدك الإلكتروني.',
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
          milliseconds: (message.length * 75).clamp(1200, 9000).toInt(),
        );

        await Future<void>.delayed(estimatedSpeechTime);
      } else {
        await _voiceService.speak(message);
      }
    } catch (e) {
      debugPrint('Login voice feedback error: $e');
    } finally {
      _voiceBusy = false;
    }

    if (mounted && _voiceEnabled && !_voiceProcessing) {
      await _listenForVoice();
    }
  }

  Future<void> _reportMessage(String message) async {
    _showMessage(message);

    if (_voiceEnabled) {
      await _speakAndResume(message);
      return;
    }

    final screenReaderActive =
        MediaQuery.maybeOf(context)?.accessibleNavigation ??
            _screenReaderActive;

    if (screenReaderActive && mounted) {
      SemanticsService.sendAnnouncement(
        View.of(context),
        message,
        Directionality.of(context),
      );
    }
  }

  Future<void> _login() async {
    if (_loading) return;

    if (!_formKey.currentState!.validate()) {
      _emailFocusNode.requestFocus();

      if (_voiceEnabled) {
        await _reportMessage('يرجى إدخال بريد إلكتروني صحيح.');
      }
      return;
    }

    _silenceTimer?.cancel();

    if (_voiceEnabled) {
      await _speechService.stopListening();
    }

    if (!mounted) return;

    setState(() => _loading = true);

    try {
      final email = _emailController.text.trim().toLowerCase();

      final canSendLink =
          await _authService.canSendSignInLink(email);

      if (canSendLink) {
        await _authService.sendSignInLink(email: email);
      }

      if (!mounted) return;

      await _stopVoiceListening();

      if (!mounted) return;

      const message =
          'إذا كان لديك حساب مسجل في دُلّني، '
          'فسيتم إرسال رابط تسجيل الدخول إلى بريدك الإلكتروني. '
          'يرجى التحقق من صندوق الوارد أو البريد المزعج.';

      _showMessage(message);
    } on FirebaseAuthException catch (e) {
      if (!mounted) return;

      if (e.code == 'too-many-requests') {
        await _reportMessage('محاولات كثيرة. يرجى المحاولة لاحقًا.');
      } else if (e.code == 'network-request-failed') {
        await _reportMessage(
          'تعذر الاتصال بالإنترنت. تحقق من الاتصال وحاول مجددًا.',
        );
      } else {
        await _reportMessage(
          'تعذر معالجة طلبك. تحقق من الاتصال وحاول مجددًا.',
        );
      }
    } catch (_) {
      if (!mounted) return;

      await _reportMessage(
        'تعذر معالجة طلبك. تحقق من الاتصال وحاول مجددًا.',
      );
    } finally {
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

  Future<void> _stopVoiceListening() async {
    _silenceTimer?.cancel();
    _voiceEnabled = false;

    await _speechService.cancelListening();
    await _voiceService.stop();
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

  void _goToSignUp() {
    Navigator.pushReplacement(
      context,
      MaterialPageRoute<void>(
        builder: (_) => const SignupPage(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('تسجيل الدخول'),
      ),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 520),
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const ExcludeSemantics(
                      child: Icon(
                        Icons.explore_outlined,
                        size: 76,
                      ),
                    ),
                    const SizedBox(height: 16),
                    Semantics(
                      header: true,
                      child: Text(
                        'أهلًا بعودتك',
                        style: theme.textTheme.headlineMedium,
                        textAlign: TextAlign.center,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'أدخل بريدك الإلكتروني وسنرسل إليك رابطًا '
                      'آمنًا لتسجيل الدخول دون الحاجة إلى كلمة مرور.',
                      style: theme.textTheme.bodyMedium,
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 28),
                    TextFormField(
                      focusNode: _emailFocusNode,
                      controller: _emailController,
                      inputFormatters: [
                        FilteringTextInputFormatter.allow(
                          _englishPrintableCharacters,
                        ),
                      ],
                      autofillHints: const [AutofillHints.email],
                      autocorrect: false,
                      enableSuggestions: false,
                      textInputAction: TextInputAction.done,
                      onFieldSubmitted: (_) =>
                          _loading ? null : _login(),
                      keyboardType: TextInputType.emailAddress,
                      textDirection: TextDirection.ltr,
                      autovalidateMode:
                          AutovalidateMode.onUserInteraction,
                      decoration: _fieldDecoration(
                        labelText: 'البريد الإلكتروني',
                        prefixIcon: Icons.email_outlined,
                        touched: _emailTouched,
                        isValid: _emailIsValid,
                      ),
                      onChanged: (_) {
                        setState(() {
                          _emailTouched = true;
                          _emailConfirmed = false;
                        });
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
                    const SizedBox(height: 16),
                    if (!_voiceEnabled)
                      OutlinedButton.icon(
                        onPressed: _loading ? null : _enableVoiceMode,
                        icon: const Icon(Icons.mic_none),
                        label: const Text('تفعيل الإدخال الصوتي'),
                      )
                    else
                      OutlinedButton.icon(
                        onPressed: _loading ? null : _switchToManual,
                        icon: const Icon(Icons.keyboard_alt_outlined),
                        label: const Text('الانتقال إلى الإدخال اليدوي'),
                      ),
                    const SizedBox(height: 16),
                    ElevatedButton(
                      onPressed: _loading ? null : _login,
                      child: _loading
                          ? const Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                SizedBox(
                                  height: 20,
                                  width: 20,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                ),
                                SizedBox(width: 12),
                                Text('جارٍ الإرسال...'),
                              ],
                            )
                          : const Text('إرسال رابط تسجيل الدخول'),
                    ),
                    Wrap(
                      alignment: WrapAlignment.center,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        const Text('لا يوجد حساب؟'),
                        TextButton(
                          onPressed: _loading ? null : _goToSignUp,
                          child: const Text('إنشاء حساب'),
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
    );
  }
}
