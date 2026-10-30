import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../services/auth_service.dart';
import 'home_page.dart';
import 'signup_page.dart';
import 'password_reset_page.dart';

class LoginPage extends StatefulWidget {
  const LoginPage({super.key});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  static final RegExp _emailPattern =
      RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$');

  final _formKey = GlobalKey<FormState>();
  final _emailFocusNode = FocusNode();
  final _passwordFocusNode = FocusNode();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _authService = AuthService();

  bool _rememberMe = false;
  bool _hidePassword = true;
  bool _loading = false;
  bool _emailTouched = false;
  bool _passwordTouched = false;

  bool get _emailIsValid {
    final value = _emailController.text.trim();
    return value.isNotEmpty && _emailPattern.hasMatch(value);
  }

  bool get _passwordIsValid {
    final password = _passwordController.text;
    return password.length >= 8 &&
        RegExp(r'[A-Z]').hasMatch(password) &&
        RegExp(r'[a-z]').hasMatch(password) &&
        RegExp(r'\d').hasMatch(password) &&
        RegExp(r'[^A-Za-z0-9\s]').hasMatch(password);
  }

  Color get _successColor {
    return Theme.of(context).brightness == Brightness.dark
        ? Colors.green.shade300
        : Colors.green.shade800;
  }

  @override
  void dispose() {
    _emailFocusNode.dispose();
    _passwordFocusNode.dispose();
    _emailController.dispose();
    _passwordController.dispose();
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
    final Color normalBorder = colors.outline;
    final Color currentBorder = !touched
        ? normalBorder
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
      border: outline(normalBorder),
      enabledBorder: outline(currentBorder),
      focusedBorder: outline(currentBorder, width: 1.8),
      errorBorder: outline(colors.error),
      focusedErrorBorder: outline(colors.error, width: 1.8),
      errorMaxLines: 2,
    );
  }

  Future<void> _login() async {
    if (!_formKey.currentState!.validate()) {
      if (!_emailIsValid) {
        _emailFocusNode.requestFocus();
      } else {
        _passwordFocusNode.requestFocus();
      }
      return;
    }

    setState(() => _loading = true);

    try {
      await _authService.signIn(
        email: _emailController.text,
        password: _passwordController.text,
      );

      final preferences = await SharedPreferences.getInstance();
      await preferences.setBool('rememberMe', _rememberMe);

      if (!mounted) return;

      Navigator.pushAndRemoveUntil(
        context,
        MaterialPageRoute<void>(
          builder: (_) => const HomePage(),
        ),
        (_) => false,
      );
    } on FirebaseAuthException catch (e) {
      _showMessage(_authError(e.code));
    } catch (_) {
      _showMessage(
        'تعذر تسجيل الدخول. تحقق من الاتصال وحاول مجددًا.',
      );
    } finally {
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

  String _authError(String code) {
    switch (code) {
      case 'invalid-email':
        return 'البريد الإلكتروني غير صحيح.';
      case 'user-not-found':
      case 'invalid-credential':
      case 'wrong-password':
        return 'بيانات الدخول غير صحيحة.';
      case 'user-disabled':
        return 'الحساب غير مفعّل. تواصل مع الدعم.';
      case 'too-many-requests':
        return 'محاولات كثيرة. حاول لاحقًا.';
      case 'network-request-failed':
        return 'تعذر الاتصال بالإنترنت. تحقق من الاتصال وحاول مجددًا.';
      default:
        return 'تعذر تسجيل الدخول. حاول مجددًا.';
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

  void _resetPassword() {
    final email = _emailController.text.trim();
    Navigator.push(
      context,
      MaterialPageRoute<void>(
        builder: (_) => PasswordResetPage(initialEmail: email),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(title: const Text('تسجيل الدخول')),
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
                      child: Icon(Icons.explore_outlined, size: 76),
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
                      'يمكن تسجيل الدخول للمتابعة مع دُلّني.',
                      style: theme.textTheme.bodyLarge,
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 28),
                    TextFormField(
                      focusNode: _emailFocusNode,
                      controller: _emailController,
                      autofillHints: const [AutofillHints.email],
                      textInputAction: TextInputAction.next,
                      onFieldSubmitted: (_) => _passwordFocusNode.requestFocus(),
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
                      autofillHints: const [AutofillHints.password],
                      textInputAction: TextInputAction.done,
                      onFieldSubmitted: (_) => _loading ? null : _login(),
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
                        if (!_passwordIsValid) {
                          return 'أدخل كلمة مرور صالحة.';
                        }
                        return null;
                      },
                    ),
                    CheckboxListTile(
                      value: _rememberMe,
                      onChanged: _loading
                          ? null
                          : (value) {
                              setState(() => _rememberMe = value ?? false);
                            },
                      title: const Text('تذكّرني'),
                      controlAffinity: ListTileControlAffinity.leading,
                      contentPadding: EdgeInsets.zero,
                    ),
                    Align(
                      alignment: AlignmentDirectional.centerEnd,
                      child: TextButton(
                        onPressed: _loading ? null : _resetPassword,
                        child: const Text('نسيت كلمة المرور؟'),
                      ),
                    ),
                    const SizedBox(height: 12),
                    ElevatedButton(
                      onPressed: _loading ? null : _login,
                      child: _loading
                          ? Semantics(
                              excludeSemantics: true,
                              liveRegion: true,
                              label: 'جارٍ تسجيل الدخول',
                              child: SizedBox(
                                height: 24,
                                width: 24,
                                child: CircularProgressIndicator(strokeWidth: 2),
                              ),
                            )
                          : const Text('تسجيل الدخول'),
                    ),
                    const SizedBox(height: 16),
                    Wrap(
                      alignment: WrapAlignment.center,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        const Text('لا يوجد حساب؟'),
                        TextButton(
                          onPressed: () => Navigator.pushReplacement(
                            context,
                            MaterialPageRoute<void>(
                              builder: (_) => const SignupPage(),
                            ),
                          ),
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
