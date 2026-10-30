import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../services/auth_service.dart';
import 'login_page.dart';

class SignupPage extends StatefulWidget {
  const SignupPage({super.key});

  @override
  State<SignupPage> createState() => _SignupPageState();
}

class _SignupPageState extends State<SignupPage> {
  static final RegExp _emailPattern =
      RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$');
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

  bool _hidePassword = true;
  bool _hideConfirm = true;
  bool _loading = false;
  bool _nameTouched = false;
  bool _emailTouched = false;
  bool _passwordTouched = false;
  bool _confirmTouched = false;

  bool get _nameIsValid {
    final name = _nameController.text.trim();
    return name.length >= 2 &&
        name.length <= 20 &&
        _namePattern.hasMatch(name);
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
      _PasswordRule('رقم واحد على الأقل (0–9)', RegExp(r'\d').hasMatch(password)),
      _PasswordRule(
        'رمز خاص واحد على الأقل (مثل ! أو @ أو #)',
        RegExp(r'[^A-Za-z0-9\s]').hasMatch(password),
      ),
    ];
  }

  bool get _passwordIsValid => _passwordRules.every((rule) => rule.isMet);

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
                    ExcludeSemantics(
                      child: Icon(
                        icon,
                        color: color,
                        size: 17,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        rule.label,
                        style: theme.textTheme.bodyMedium?.copyWith(color: color),
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
        MaterialPageRoute<void>(
          builder: (_) => const LoginPage(),
        ),
        (_) => false,
      );
    } on FirebaseAuthException catch (e) {
      _showMessage(_authError(e.code));
    } catch (_) {
      _showMessage(
        'تعذر إنشاء الحساب. تحقق من الاتصال وحاول مجددًا.',
      );
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
                      onFieldSubmitted: (_) => _loading ? null : _createAccount(),
                      controller: _confirmController,
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
                                child: CircularProgressIndicator(strokeWidth: 2),
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
}

class _PasswordRule {
  const _PasswordRule(this.label, this.isMet);

  final String label;
  final bool isMet;
}
