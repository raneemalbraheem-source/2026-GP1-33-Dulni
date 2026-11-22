
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../services/auth_service.dart';
import 'signup_page.dart';

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

  bool _loading = false;
  bool _emailTouched = false;

  bool get _emailIsValid {
    final value = _emailController.text.trim();
    return value.isNotEmpty && _emailPattern.hasMatch(value);
  }

  Color get _successColor {
    return Theme.of(context).brightness == Brightness.dark
        ? Colors.green.shade300
        : Colors.green.shade800;
  }

  @override
  void dispose() {
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
    final normalBorder = colors.outline;

    final currentBorder = !touched
        ? normalBorder
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
  border: outline(normalBorder),
  enabledBorder: outline(currentBorder),
  focusedBorder: outline(
    currentBorder,
    width: 1.8,
  ),
  errorBorder: outline(colors.error),
  focusedErrorBorder: outline(
    colors.error,
    width: 1.8,
  ),
  errorMaxLines: 2,
);
  }

  Future<void> _login() async {
    if (_loading) return;

    if (!_formKey.currentState!.validate()) {
      _emailFocusNode.requestFocus();
      return;
    }

    setState(() => _loading = true);

    try {
      final email = _emailController.text.trim().toLowerCase();

      final canSendLink =
          await _authService.canSendSignInLink(email);

      if (canSendLink) {
        await _authService.sendSignInLink(
          email: email,
        );
      }

      if (!mounted) return;

      _showMessage(
        'إذا كان لديك حساب مسجل في دُلّني، '
        'فسيتم إرسال رابط تسجيل الدخول إلى بريدك الإلكتروني. '
        'يرجى التحقق من صندوق الوارد أو البريد المزعج.',
      );
    } on FirebaseAuthException catch (e) {
      if (!mounted) return;

      if (e.code == 'too-many-requests') {
        _showMessage('محاولات كثيرة. يرجى المحاولة لاحقًا.');
      } else if (e.code == 'network-request-failed') {
        _showMessage(
          'تعذر الاتصال بالإنترنت. تحقق من الاتصال وحاول مجددًا.',
        );
      } else {
        _showMessage(
          'تعذر معالجة طلبك. تحقق من الاتصال وحاول مجددًا.',
        );
      }
    } catch (_) {
      if (!mounted) return;

      _showMessage(
        'تعذر معالجة طلبك. تحقق من الاتصال وحاول مجددًا.',
      );
    } finally {
      if (mounted) {
        setState(() => _loading = false);
      }
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
              constraints: const BoxConstraints(
                maxWidth: 520,
              ),
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
                      autofillHints: const [
                        AutofillHints.email,
                      ],
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
