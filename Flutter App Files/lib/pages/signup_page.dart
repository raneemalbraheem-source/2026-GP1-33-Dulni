import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'dart:async';

import '../services/speech_recognition_service.dart';
import '../services/voice_feedback_service.dart';
import '../services/auth_service.dart';
import 'login_page.dart';

enum _VoiceMode { commands, field }

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

  _VoiceMode _voiceMode = _VoiceMode.commands;
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

  String _lastSpokenValidationMessage = '';

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
        _nameFocusNode.requestFocus();
      } else if (!_emailIsValid) {
        _emailFocusNode.requestFocus();
      } else if (!_passwordIsValid) {
        _passwordFocusNode.requestFocus();
      } else {
        _confirmFocusNode.requestFocus();
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
      _showMessage(_authError(e.code));
    } catch (_) {
      _showMessage('تعذر إنشاء الحساب. تحقق من الاتصال وحاول مجددًا.');
    } finally {
      if (mounted) setState(() => _loading = false);
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
                      child: Text(
                        'رحلة أسهل مع دُلّني',
                        style: theme.textTheme.headlineMedium,
                        textAlign: TextAlign.center,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'يمكن إنشاء حساب لتخصيص تجربة الاستخدام.',
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
                      autofillHints: const [AutofillHints.email],
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
                      onFieldSubmitted: (_) => _confirmFocusNode.requestFocus(),
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
    try {
      await _voiceService.initialize();

      final ready = await _speechService.initialize(
        onStatus: _handleSpeechStatus,
        onError: (message) {
          debugPrint('Speech error: $message');
        },
      );

      if (!mounted || !ready) return;

      _voiceEnabled = true;

      await _voiceService.speak(
        'مرحبًا بك في صفحة إنشاء الحساب في تطبيق دُلّني. '
        'سنقوم بإدخال البيانات بالترتيب التالي: '
        'الاسم الكامل، ثم البريد الإلكتروني، '
        'ثم كلمة المرور، ثم تأكيد كلمة المرور. '
        'بعد الانتهاء من كل حقل، قل انتهى للعودة إلى قائمة الأوامر. '
        'لإدخال الاسم قل: إدخال الاسم. '
        'وللبريد الإلكتروني قل: إدخال البريد الإلكتروني. '
        'ولكلمة المرور قل: إدخال كلمة المرور. '
        'ولتأكيدها قل: إدخال تأكيد كلمة المرور. '
        'ولإنشاء الحساب قل: إنشاء الحساب.',
      );

      if (!mounted) return;

      await _listenForVoice();
    } catch (e) {
      debugPrint('Signup voice initialization error: $e');
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

    final started = await _speechService.startListening(
      onResult: (recognizedText) {
        debugPrint('SIGNUP RECOGNIZED: "$recognizedText"');
        _handleVoiceResult(recognizedText);
      },
      onStatus: _handleSpeechStatus,
      onError: (message) {
        debugPrint('SIGNUP SPEECH ERROR: $message');
      },
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
      if (_voiceMode == _VoiceMode.commands) {
        await _handleVoiceCommand(text);
      } else {
        await _handleFieldInput(text);
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

    // تأكيد كلمة المرور أولًا حتى لا تختلط بأمر كلمة المرور.
    if (command.contains('تاكيد كلمة المرور') ||
        command.contains('تاكيد كلمه المرور') ||
        command.contains('ادخال التاكيد') ||
        command.contains('ادخل التاكيد') ||
        command.contains('ادخال تاكيد') ||
        command.contains('ادخل تاكيد')) {
      await _startFieldCapture(_VoiceField.confirmPassword);
      return;
    }

    if (command.contains('ادخال الاسم') ||
        command.contains('ادخل الاسم') ||
        command.contains('ادخال اسم') ||
        command.contains('ادخل اسم')) {
      await _startFieldCapture(_VoiceField.name);
      return;
    }

    if (command.contains('ادخال البريد') ||
        command.contains('ادخل البريد') ||
        command.contains('ادخال الايميل') ||
        command.contains('ادخل الايميل')) {
      await _startFieldCapture(_VoiceField.email);
      return;
    }

    if (command.contains('ادخال كلمة المرور') ||
        command.contains('ادخل كلمة المرور') ||
        command.contains('ادخال كلمه المرور') ||
        command.contains('ادخل كلمه المرور')) {
      await _startFieldCapture(_VoiceField.password);
      return;
    }

    if (command.contains('انشاء الحساب') || command.contains('انشاء حساب')) {
      await _stopVoiceListening();

      if (mounted) {
        await _createAccount();
      }
      return;
    }

    debugPrint('SIGNUP: Command not recognized.');

    await _speakAndResume(
      'لم أتعرف على الأمر. يمكنك قول إدخال الاسم، '
      'أو إدخال البريد الإلكتروني، أو إدخال كلمة المرور، '
      'أو إدخال تأكيد كلمة المرور، أو إنشاء الحساب.',
    );
  }

  Future<void> _startFieldCapture(_VoiceField field) async {
    _activeVoiceField = field;
    _voiceMode = _VoiceMode.field;

    switch (field) {
      case _VoiceField.name:
        await _speakAndResume('أدخل الاسم الكامل الآن. بعد الانتهاء قل انتهى.');
        break;

      case _VoiceField.email:
        await _speakAndResume(
          'أدخل البريد الإلكتروني. '
          'يمكنك قول نقطة أو دوت لإدخال النقطة، '
          'وعند أو آت لإدخال علامة آت، '
          'وشرطة أو داش لإدخال الشرطة، '
          'وشرطة سفلية أو أندر سكور لإدخال الشرطة السفلية. '
          'بعد الانتهاء قل انتهى.',
        );
        break;

      case _VoiceField.password:
        await _speakAndResume(
          'أدخل كلمة المرور باستخدام الأحرف الإنجليزية والأرقام والرموز. '
          'لن أكرر كلمة المرور بصوت مرتفع. '
          'بعد الانتهاء قل انتهى.',
        );
        break;

      case _VoiceField.confirmPassword:
        await _speakAndResume(
          'أدخل كلمة المرور مرة أخرى للتأكيد. '
          'لن أكررها بصوت مرتفع. بعد الانتهاء قل انتهى.',
        );
        break;
    }
  }

  Future<void> _handleFieldInput(String text) async {
    debugPrint(
      'SIGNUP FIELD INPUT: "$text" | '
      'Mode: $_voiceMode | Field: $_activeVoiceField',
    );
    final normalized = _normalizeArabic(text);

    if (normalized == 'انتهى' || normalized == 'انته') {
      await _finishFieldCapture();
      return;
    }

    final endIndex = normalized.lastIndexOf('انتهى');

    if (endIndex != -1) {
      final remainingText = text.substring(0, endIndex).trim();

      if (remainingText.isNotEmpty) {
        _appendVoiceInput(remainingText);
      }

      await _finishFieldCapture();
      return;
    }

    _appendVoiceInput(text);

    await _announceCurrentFieldValidation();
  }

  void _appendVoiceInput(String recognizedText) {
    debugPrint(
      'SIGNUP APPEND INPUT: "$recognizedText" | Field: $_activeVoiceField',
    );
    if (!mounted || _activeVoiceField == null) return;

    String value = recognizedText.trim();

    switch (_activeVoiceField!) {
      case _VoiceField.name:
        _nameController.text = _joinVoiceText(_nameController.text, value);

        setState(() {
          _nameTouched = true;
        });
        break;

      case _VoiceField.email:
        value = _normalizeEmailVoiceInput(value);

        _emailController.text = _joinVoiceText(_emailController.text, value);
        debugPrint(
          'SIGNUP FIELD VALUE: '
          '${_activeVoiceField == _VoiceField.name ? _nameController.text : ''}',
        );

        setState(() {
          _emailTouched = true;
        });
        break;

      case _VoiceField.password:
        _passwordController.text += _normalizePasswordVoiceInput(value);

        setState(() {
          _passwordTouched = true;
        });
        break;

      case _VoiceField.confirmPassword:
        _confirmController.text += _normalizePasswordVoiceInput(value);

        setState(() {
          _confirmTouched = true;
        });
        break;
    }
  }

  String _joinVoiceText(String oldValue, String newValue) {
    if (oldValue.trim().isEmpty) return newValue;

    return '${oldValue.trim()} $newValue';
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

  Future<void> _finishFieldCapture() async {
    await _speechService.stopListening();

    _activeVoiceField = null;
    _voiceMode = _VoiceMode.commands;
    _lastSpokenValidationMessage = '';

    await _speakAndResume(
      'تم إنهاء إدخال الحقل. '
      'يمكنك الآن إعطاء الأمر التالي.',
    );
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

  Future<void> _announceCurrentFieldValidation() async {
    final error = _currentFieldError();

    if (error == null || error == _lastSpokenValidationMessage) {
      return;
    }

    _lastSpokenValidationMessage = error;

    await _speakAndResume(error);
  }

  Future<void> _speakAndResume(String message) async {
    if (!mounted) return;

    _voiceBusy = true;

    try {
      await _speechService.stopListening();
      await _voiceService.speak(message);
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
