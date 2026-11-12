import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter/semantics.dart';

import 'dart:async';

import '../services/speech_recognition_service.dart';
import '../services/voice_feedback_service.dart';
import '../services/auth_service.dart';
import 'login_page.dart';

enum _VoiceMode { manual, commands, field, review }

enum _VoiceField { name, email, password, confirmPassword }

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
  final _passwordFocusNode = FocusNode();
  final _confirmFocusNode = FocusNode();
  final _nameController = TextEditingController();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmController = TextEditingController();
  final _authService = AuthService();
  final _speechService = SpeechRecognitionService.instance;
  final _voiceService = VoiceFeedbackService.instance;

  _VoiceMode _voiceMode = _VoiceMode.manual;
  _VoiceField? _activeVoiceField;

  bool _hidePassword = true;
  bool _hideConfirm = true;
  bool _loading = false;
  bool _nameTouched = false;
  bool _emailTouched = false;
  bool _passwordTouched = false;
  bool _confirmTouched = false;
  bool _voiceEnabled = false;
  bool _voiceBusy = false;
  bool _voiceProcessing = false;
  bool _voiceRestartPending = false;
  bool _awaitingVoiceChoice = false;
  bool _screenReaderActive = false;

  bool get _nameIsValid {
    final name = _nameController.text.trim();
    return name.length >= 2 && name.length <= 20 && _namePattern.hasMatch(name);
  }

  bool get _emailIsValid {
    final email = _emailController.text.trim();
    return email.isNotEmpty && _emailPattern.hasMatch(email);
  }

  List<_PasswordRule> get _passwordRules {
    final password = _passwordController.text;
    return [
      _PasswordRule('8 أحرف على الأقل', password.length >= 8),
      _PasswordRule(
        'حرف إنجليزي كبير واحد على الأقل (A–Z)',
        RegExp(r'[A-Z]').hasMatch(password),
      ),
      _PasswordRule(
        'حرف إنجليزي صغير واحد على الأقل (a–z)',
        RegExp(r'[a-z]').hasMatch(password),
      ),
      _PasswordRule(
        'رقم واحد على الأقل (0–9)',
        RegExp(r'\d').hasMatch(password),
      ),
      _PasswordRule(
        'رمز خاص واحد على الأقل (مثل ! أو @ أو #)',
        RegExp(r'[^A-Za-z0-9\s]').hasMatch(password),
      ),
    ];
  }

  bool _isAsciiPassword(String value) =>
      value.codeUnits.every((unit) => unit >= 0x21 && unit <= 0x7E);

  bool get _passwordIsValid =>
      _isAsciiPassword(_passwordController.text) &&
      _passwordRules.every((rule) => rule.isMet);

  Color get _successColor {
    return Theme.of(context).brightness == Brightness.dark
        ? Colors.green.shade300
        : Colors.green.shade800;
  }

  bool get _confirmIsValid {
    return _confirmController.text.isNotEmpty &&
        _confirmController.text == _passwordController.text;
  }

  String? get _confirmErrorText {
    if (!_confirmTouched) return null;
    if (_confirmController.text.isEmpty) {
      return 'أكد كلمة المرور.';
    }
    if (_confirmController.text != _passwordController.text) {
      return 'كلمتا المرور غير متطابقتين.';
    }
    return null;
  }

  @override
  void dispose() {
    _voiceEnabled = false;

    unawaited(_speechService.cancelListening());
    unawaited(_voiceService.stop());

    _nameFocusNode.dispose();
    _emailFocusNode.dispose();
    _passwordFocusNode.dispose();
    _confirmFocusNode.dispose();

    _nameController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    _confirmController.dispose();

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

  Widget _buildPasswordRules() {
    final theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsetsDirectional.only(start: 8, top: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Semantics(
            header: true,
            child: Text(
              'متطلبات كلمة المرور:',
              style: theme.textTheme.bodyMedium?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          const SizedBox(height: 6),
          ..._passwordRules.map((rule) {
            final color = !_passwordTouched
                ? theme.colorScheme.onSurfaceVariant
                : rule.isMet
                ? _successColor
                : theme.colorScheme.error;
            final icon = !_passwordTouched
                ? Icons.radio_button_unchecked
                : rule.isMet
                ? Icons.check_circle
                : Icons.cancel_outlined;
            final spokenStatus = !_passwordTouched
                ? 'لم يبدأ التحقق بعد'
                : rule.isMet
                ? 'مستوفى'
                : 'غير مستوفى';
            return Padding(
              padding: const EdgeInsets.symmetric(vertical: 2),
              child: Semantics(
                container: true,
                excludeSemantics: true,
                label: '$spokenStatus: ${rule.label}',
                child: Row(
                  children: [
                    ExcludeSemantics(child: Icon(icon, color: color, size: 17)),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        rule.label,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: color,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            );
          }),
        ],
      ),
    );
  }

  Future<void> _createAccount() async {
    if (!_formKey.currentState!.validate()) {
      if (!_nameIsValid) {
        _activeVoiceField = _VoiceField.name;
      } else if (!_emailIsValid) {
        _activeVoiceField = _VoiceField.email;
      } else if (!_passwordIsValid) {
        _activeVoiceField = _VoiceField.password;
      } else {
        _activeVoiceField = _VoiceField.confirmPassword;
      }

      final error = _currentFieldError();

      if (error != null) {
        await _retryAfterValidationError(error);
      }

      return;
    }

    setState(() => _loading = true);

    try {
      await _authService.createAccount(
        fullName: _nameController.text.trim(),
        email: _emailController.text.trim(),
        password: _passwordController.text,
      );

      // Ask Android Autofill / the active password manager to save the
      // newly created credential after Firebase confirms account creation.
      TextInput.finishAutofillContext(shouldSave: true);

      if (!mounted) return;

      // Firebase signs in the newly created user automatically.
      // Sign out so the user can sign in from the Login page.
      await FirebaseAuth.instance.signOut();

      if (!mounted) return;

      Navigator.pushAndRemoveUntil(
        context,
        MaterialPageRoute<void>(builder: (_) => const LoginPage()),
        (_) => false,
      );
    } on FirebaseAuthException catch (e) {
      final message = _authError(e.code);

      _showMessage(message);

      if (e.code == 'email-already-in-use' && _voiceEnabled) {
        _activeVoiceField = _VoiceField.email;
        await _startFieldCapture(_VoiceField.email);
      } else {
        await _speakAndResume(message);
      }
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
      case 'weak-password':
        return 'كلمة المرور لا تحقق شروط الأمان.';
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

    return Scaffold(
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
                        textInputAction: TextInputAction.next,
                        onFieldSubmitted: (_) =>
                            _passwordFocusNode.requestFocus(),
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
                      const SizedBox(height: 16),
                      TextFormField(
                        focusNode: _passwordFocusNode,
                        controller: _passwordController,
                        textDirection: TextDirection.ltr,
                        inputFormatters: [
                          FilteringTextInputFormatter.allow(
                            _englishPrintableCharacters,
                          ),
                        ],
                        autofillHints: const [AutofillHints.newPassword],
                        textInputAction: TextInputAction.next,
                        onFieldSubmitted: (_) =>
                            _confirmFocusNode.requestFocus(),
                        obscureText: _hidePassword,
                        enableSuggestions: false,
                        autocorrect: false,
                        autovalidateMode: AutovalidateMode.onUserInteraction,
                        decoration: _fieldDecoration(
                          labelText: 'كلمة المرور',
                          prefixIcon: Icons.lock_outline,
                          touched: _passwordTouched,
                          isValid: _passwordIsValid,
                          suffixIcon: IconButton(
                            tooltip: _hidePassword
                                ? 'إظهار كلمة المرور'
                                : 'إخفاء كلمة المرور',
                            onPressed: () {
                              setState(() => _hidePassword = !_hidePassword);
                            },
                            icon: Icon(
                              _hidePassword
                                  ? Icons.visibility_outlined
                                  : Icons.visibility_off_outlined,
                            ),
                          ),
                        ),
                        onChanged: (_) {
                          setState(() => _passwordTouched = true);
                        },
                        validator: (value) {
                          if (value == null || value.isEmpty) {
                            return 'أدخل كلمة المرور.';
                          }
                          if (!_isAsciiPassword(value)) {
                            return 'استخدم أحرفًا إنجليزية ورموزًا فقط.';
                          }
                          if (!_passwordIsValid) {
                            return 'كلمة المرور لا تحقق جميع الشروط.';
                          }
                          return null;
                        },
                      ),
                      _buildPasswordRules(),
                      const SizedBox(height: 16),
                      TextFormField(
                        focusNode: _confirmFocusNode,
                        autofillHints: const [AutofillHints.newPassword],
                        textInputAction: TextInputAction.done,
                        onFieldSubmitted: (_) =>
                            _loading ? null : _createAccount(),
                        controller: _confirmController,
                        textDirection: TextDirection.ltr,
                        inputFormatters: [
                          FilteringTextInputFormatter.allow(
                            _englishPrintableCharacters,
                          ),
                        ],
                        obscureText: _hideConfirm,
                        enableSuggestions: false,
                        autocorrect: false,
                        autovalidateMode: AutovalidateMode.disabled,
                        forceErrorText: _confirmErrorText,
                        decoration: _fieldDecoration(
                          labelText: 'تأكيد كلمة المرور',
                          prefixIcon: Icons.lock_reset_outlined,
                          touched: _confirmTouched,
                          isValid: _confirmIsValid,
                          suffixIcon: IconButton(
                            tooltip: _hideConfirm
                                ? 'إظهار كلمة المرور'
                                : 'إخفاء كلمة المرور',
                            onPressed: () {
                              setState(() => _hideConfirm = !_hideConfirm);
                            },
                            icon: Icon(
                              _hideConfirm
                                  ? Icons.visibility_outlined
                                  : Icons.visibility_off_outlined,
                            ),
                          ),
                        ),
                        onChanged: (_) {
                          setState(() => _confirmTouched = true);
                        },
                        validator: (value) {
                          if (value == null || value.isEmpty) {
                            return 'أكد كلمة المرور.';
                          }
                          if (value != _passwordController.text) {
                            return 'كلمتا المرور غير متطابقتين.';
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
                                label: 'جارٍ إنشاء الحساب',
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
                                : () => Navigator.pushReplacement(
                                    context,
                                    MaterialPageRoute<void>(
                                      builder: (_) => const LoginPage(),
                                    ),
                                  ),
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

      final ready = await _speechService.initialize(
        onStatus: _handleSpeechStatus,
        onError: (message) {
          debugPrint('Speech error: $message');
        },
      );

      if (!mounted || !ready) return;

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
      if (mounted) {
        setState(() {
          _voiceEnabled = false;
          _voiceMode = _VoiceMode.manual;
        });
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
        await _speakAndResume(
          'سنُدخل البيانات بالترتيب التالي: الاسم الكامل، '
          'ثم البريد الإلكتروني، ثم كلمة المرور، ثم تأكيد كلمة المرور. '
          'عندما تكون مستعدًا، قل: ابدأ إنشاء الحساب.',
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

    if (command.contains('ابدا انشاء الحساب')) {
      final nextField = _firstIncompleteVoiceField();
      if (nextField != null) {
        await _startFieldCapture(nextField);
      } else {
        _activeVoiceField = null;
        await _speakAndResume(
          'جميع الحقول تحتوي على بيانات صحيحة. '
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

    await _speakAndResume(
      'لم أتعرف على الأمر. '
      'عندما تكون مستعدًا، قل: ابدأ إنشاء الحساب.',
    );
  }

  bool _isSwitchToManualCommand(String normalizedCommand) {
    return normalizedCommand.contains('الانتقال الى الادخال اليدوي') ||
        normalizedCommand.contains('انتقال الى الادخال اليدوي') ||
        normalizedCommand.contains('switch to manual input');
  }

  Future<void> _switchToManual() async {
    if (!mounted) return;

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
      case _VoiceField.password:
        return _passwordFocusNode;
      case _VoiceField.confirmPassword:
        return _confirmFocusNode;
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
          'جميع الحقول تحتوي على بيانات صحيحة. '
          'قل إنشاء الحساب للمتابعة.',
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

    // Read sensitive fields only after the user explicitly requests it.
    if ((_activeVoiceField == _VoiceField.password ||
            _activeVoiceField == _VoiceField.confirmPassword) &&
        (command.contains('قراءة الحقل') ||
            command.contains('قراءه الحقل') ||
            command.contains('اقرا الحقل') ||
            command.contains('قراءة كلمة المرور') ||
            command.contains('قراءه كلمة المرور') ||
            command.contains('قراءه كلمه المرور') ||
            command.contains('اقرا كلمة المرور') ||
            command.contains('اقرا كلمه المرور') ||
            command.contains('قراءة تأكيد كلمة المرور') ||
            command.contains('قراءه تاكيد كلمة المرور') ||
            command.contains('اقرا تاكيد كلمة المرور'))) {
      final isConfirmation = _activeVoiceField == _VoiceField.confirmPassword;
      final value = isConfirmation
          ? _confirmController.text
          : _passwordController.text;
      final fieldLabel = isConfirmation ? 'تأكيد كلمة المرور' : 'كلمة المرور';

      await _speakAndResume(
        '$fieldLabel هي: $value. '
        'قل تأكيد لاعتماد الإدخال، '
        'أو إعادة المحاولة لإدخاله من جديد، '
        'أو قراءة الحقل لسماعه مرة أخرى، '
        'أو الانتقال إلى الإدخال اليدوي.',
      );
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

    String options;
    if (_activeVoiceField == _VoiceField.password ||
        _activeVoiceField == _VoiceField.confirmPassword) {
      options =
          'قل تأكيد لاعتماد الإدخال، '
          'أو إعادة المحاولة لإدخاله من جديد، '
          'أو قراءة الحقل لسماعه، '
          'أو الانتقال إلى الإدخال اليدوي.';
    } else {
      options =
          'قل تأكيد لاعتماد الإدخال، '
          'أو إعادة المحاولة لإدخاله من جديد، '
          'أو الانتقال إلى الإدخال اليدوي.';
    }

    await _speakAndResume('لم أتعرف على اختيارك. $options');
  }

  Future<void> _advanceAfterConfirmation() async {
    switch (_activeVoiceField) {
      case _VoiceField.name:
        await _startFieldCapture(_VoiceField.email);
        break;

      case _VoiceField.email:
        await _startFieldCapture(_VoiceField.password);
        break;

      case _VoiceField.password:
        await _startFieldCapture(_VoiceField.confirmPassword);
        break;

      case _VoiceField.confirmPassword:
        _activeVoiceField = null;
        _voiceMode = _VoiceMode.commands;

        await _speakAndResume(
          'تم تأكيد جميع البيانات بنجاح. '
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
            'ويحتوي على اسم المستخدم، ثم علامة آت، '
            'ثم اسم النطاق ونقطة وامتداد البريد، '
            'مثل example@gmail.com، '
            'ولا يُسمح بإدخال مسافات.';

      case _VoiceField.password:
        return 'يجب أن تتكون كلمة المرور من 8 أحرف على الأقل， '
            'وأن تحتوي على حرف إنجليزي كبير وحرف صغير ورقم ورمز خاص واحد على الأقل， '
            'الرمز الخاص مثل علامة التعجب أو علامة الآت. '
            'يُسمح بالأحرف الإنجليزية والأرقام والرموز فقط.';

      case _VoiceField.confirmPassword:
        return 'يجب إعادة إدخال كلمة المرور نفسها تمامًا، '
            'بما في ذلك الأحرف الكبيرة والصغيرة والأرقام والرموز， '
            'حتى تتطابق مع كلمة المرور السابقة.';
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
          'ابدأ بإدخال بريدك الإلكتروني. ',);
        break;

      case _VoiceField.password:
        if (clearExisting) {
          _passwordController.clear();
          setState(() => _passwordTouched = false);
        }

        await _speakAndResume(
          'أنت الآن في حقل كلمة المرور. '
          '$requirements '
          'لن أقرأ كلمة المرور تلقائيًا حفاظًا على الخصوصية. ',
        );
        break;

      case _VoiceField.confirmPassword:
        if (clearExisting) {
          _confirmController.clear();
          setState(() => _confirmTouched = false);
        }

        await _speakAndResume(
          'أنت الآن في حقل تأكيد كلمة المرور. '
          '$requirements '
          'لن أقرأ كلمة المرور تلقائيًا حفاظًا على الخصوصية. ',
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

      case _VoiceField.password:
        await _speakAndResume(
          'تم التقاط كلمة المرور. '
          'لن أقرأ محتواها تلقائيًا حفاظًا على الخصوصية. '
          'قل تأكيد لاعتمادها، '
          'أو إعادة المحاولة لإدخالها من جديد، '
          'أو قراءة الحقل بصوت مرتفع لسماعه، '
          'أو الانتقال إلى الإدخال اليدوي.',
        );
        break;

      case _VoiceField.confirmPassword:
        await _speakAndResume(
          'تم التقاط تأكيد كلمة المرور. '
          'لن أقرأ محتواها تلقائيًا حفاظًا على الخصوصية. '
          'قل تأكيد لاعتماد الإدخال، '
          'أو إعادة المحاولة لإدخاله من جديد، '
          'أو قراءة الحقل بصوت مرتفع لسماعه '
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

      case _VoiceField.password:
        value = _normalizePasswordVoiceInput(value);

        _passwordController.text = value;

        setState(() {
          _passwordTouched = true;
        });
        break;

      case _VoiceField.confirmPassword:
        value = _normalizePasswordVoiceInput(value);

        _confirmController.text = value;

        setState(() {
          _confirmTouched = true;
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

      case _VoiceField.password:
        _passwordController.clear();
        setState(() => _passwordTouched = false);
        break;

      case _VoiceField.confirmPassword:
        _confirmController.clear();
        setState(() => _confirmTouched = false);
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

      case _VoiceField.password:
        return 'كلمة المرور';

      case _VoiceField.confirmPassword:
        return 'تأكيد كلمة المرور';
    }
  }

  String _normalizeEmailVoiceInput(String text) {
    String result = text.toLowerCase();

    final replacements = <String, String>{
      'نقطة': '.',
      'دوت': '.',
      'dot': '.',
      'عند': '@',
      'ات': '@',
      'آت': '@',
      'at': '@',
      'شرطة سفلية': '_',
      'اندر سكور': '_',
      'underscore': '_',
      'شرطة': '-',
      'داش': '-',
      'dash': '-',
    };

    replacements.forEach((word, symbol) {
      result = result.replaceAll(word, symbol);
    });

    return result.replaceAll(RegExp(r'\s+'), '');
  }

  String _normalizePasswordVoiceInput(String text) {
    // Remove spaces between dictated password segments.
    // The password itself is never spoken back.
    return text.replaceAll(RegExp(r'\s+'), '');
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

      case _VoiceField.password:
        final password = _passwordController.text;

        if (password.isEmpty) {
          return 'لم يتم إدخال كلمة المرور بعد.';
        }

        if (!_isAsciiPassword(password)) {
          return 'استخدم الأحرف الإنجليزية والأرقام والرموز فقط.';
        }

        final unmetRules = _passwordRules
            .where((rule) => !rule.isMet)
            .map((rule) => rule.label)
            .toList();

        if (unmetRules.isNotEmpty) {
          return 'كلمة المرور لا تحقق جميع الشروط. '
              'الشروط المتبقية: ${unmetRules.join('، ')}.';
        }

        return null;

      case _VoiceField.confirmPassword:
        final confirmation = _confirmController.text;

        if (confirmation.isEmpty) {
          return 'لم يتم إدخال تأكيد كلمة المرور بعد.';
        }

        if (confirmation != _passwordController.text) {
          return 'كلمتا المرور غير متطابقتين. يرجى إعادة إدخال التأكيد.';
        }

        return null;

      case null:
        return null;
    }
  }

  Future<void> _speakAndResume(String message) async {
    if (!mounted || !_voiceEnabled) return;

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
    _voiceEnabled = false;
    await _speechService.cancelListening();
    await _voiceService.stop();
  }
}

class _PasswordRule {
  const _PasswordRule(this.label, this.isMet);

  final String label;
  final bool isMet;
}
