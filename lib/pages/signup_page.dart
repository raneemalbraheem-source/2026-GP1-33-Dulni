import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../services/auth_service.dart';
import 'home_page.dart';
import 'login_page.dart';

class SignupPage extends StatefulWidget {
  const SignupPage({super.key});

  @override
  State<SignupPage> createState() => _SignupPageState();
}

class _SignupPageState extends State<SignupPage> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmController = TextEditingController();
  final _authService = AuthService();
  bool _hidePassword = true;
  bool _hideConfirm = true;
  bool _loading = false;

  @override
  void dispose() {
    _nameController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    _confirmController.dispose();
    super.dispose();
  }

  Future<void> _createAccount() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _loading = true);
    try {
      await _authService.createAccount(
        fullName: _nameController.text,
        email: _emailController.text,
        password: _passwordController.text,
      );
      if (!mounted) return;
      Navigator.pushAndRemoveUntil(
        context,
        MaterialPageRoute(builder: (_) => const HomePage()),
        (_) => false,
      );
    } on FirebaseAuthException catch (e) {
      String message;
      switch (e.code) {
        case 'email-already-in-use':
          message = 'هذا البريد الإلكتروني مسجّل مسبقًا.';
          break;
        case 'invalid-email':
          message = 'صيغة البريد الإلكتروني غير صحيحة.';
          break;
        case 'weak-password':
          message = 'كلمة المرور لا تستوفي متطلبات الأمان. يرجى اختيار كلمة مرور أقوى.';
          break;
        case 'network-request-failed':
          message = 'تعذر الاتصال بالإنترنت. يرجى المحاولة مجددًا.';
          break;
        default:
          message = 'تعذر إنشاء الحساب. يرجى المحاولة مجددًا.';
      }
      _showMessage(message);
    } catch (_) {
      _showMessage('تعذر حفظ بيانات الحساب. يرجى التحقق من الاتصال وإعدادات الخدمة ثم المحاولة مجددًا.');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
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
                    const Icon(Icons.person_add_alt_1_outlined, size: 72),
                    const SizedBox(height: 16),
                    Text('رحلة أسهل مع دلني',
                        style: theme.textTheme.headlineMedium,
                        textAlign: TextAlign.center),
                    const SizedBox(height: 8),
                    Text('أنشئ حسابًا لتخصيص تجربة الاستخدام.',
                        style: theme.textTheme.bodyLarge,
                        textAlign: TextAlign.center),
                    const SizedBox(height: 28),
                    TextFormField(
                      controller: _nameController,
                      textCapitalization: TextCapitalization.words,
                      decoration: const InputDecoration(
                        labelText: 'الاسم الكامل',
                        prefixIcon: Icon(Icons.person_outline),
                      ),
                      validator: (v) => (v == null || v.trim().isEmpty)
                          ? 'يرجى إدخال الاسم الكامل.'
                          : v!.trim().length < 2 || v.trim().length > 20
                              ? 'يجب أن يتراوح الاسم بين حرفين و20 حرفًا.'
                              : null,
                    ),
                    const SizedBox(height: 16),
                    TextFormField(
                      controller: _emailController,
                      keyboardType: TextInputType.emailAddress,
                      textDirection: TextDirection.ltr,
                      decoration: const InputDecoration(
                        labelText: 'البريد الإلكتروني',
                        prefixIcon: Icon(Icons.email_outlined),
                      ),
                      validator: (v) {
                        final value = v?.trim() ?? '';
                        if (value.isEmpty) return 'يرجى إدخال البريد الإلكتروني.';
                        if (!RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(value)) {
                          return 'صيغة البريد الإلكتروني غير صحيحة. يرجى إدخال بريد صالح.';
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: 16),
                    TextFormField(
                      controller: _passwordController,
                      obscureText: _hidePassword,
                      decoration: InputDecoration(
                        labelText: 'كلمة المرور',
                        helperText: '8 أحرف على الأقل، مع حرف كبير وصغير ورقم ورمز خاص.',
                        prefixIcon: const Icon(Icons.lock_outline),
                        suffixIcon: IconButton(
                          tooltip: _hidePassword ? 'إظهار كلمة المرور' : 'إخفاء كلمة المرور',
                          onPressed: () => setState(() => _hidePassword = !_hidePassword),
                          icon: Icon(_hidePassword ? Icons.visibility_outlined : Icons.visibility_off_outlined),
                        ),
                      ),
                      validator: (v) {
                        if (v == null || v.isEmpty) return 'يرجى إدخال كلمة المرور.';
                        if (v.length < 8) return 'يجب ألا تقل كلمة المرور عن 8 أحرف.';
                        if (!RegExp(r'[A-Z]').hasMatch(v)) return 'يلزم وجود حرف إنجليزي كبير واحد على الأقل.';
                        if (!RegExp(r'[a-z]').hasMatch(v)) return 'يلزم وجود حرف إنجليزي صغير واحد على الأقل.';
                        if (!RegExp(r'\d').hasMatch(v)) return 'يلزم وجود رقم واحد على الأقل.';
                        if (!RegExp(r'[^A-Za-z0-9]').hasMatch(v)) return 'يلزم وجود رمز خاص واحد على الأقل.';
                        return null;
                      },
                    ),
                    const SizedBox(height: 16),
                    TextFormField(
                      controller: _confirmController,
                      obscureText: _hideConfirm,
                      decoration: InputDecoration(
                        labelText: 'تأكيد كلمة المرور',
                        prefixIcon: const Icon(Icons.lock_reset_outlined),
                        suffixIcon: IconButton(
                          tooltip: _hideConfirm ? 'إظهار كلمة المرور' : 'إخفاء كلمة المرور',
                          onPressed: () => setState(() => _hideConfirm = !_hideConfirm),
                          icon: Icon(_hideConfirm ? Icons.visibility_outlined : Icons.visibility_off_outlined),
                        ),
                      ),
                      validator: (v) {
                        if (v == null || v.isEmpty) return 'يرجى تأكيد كلمة المرور.';
                        if (v != _passwordController.text) return 'كلمتا المرور غير متطابقتين.';
                        return null;
                      },
                    ),
                    const SizedBox(height: 24),
                    ElevatedButton(
                      onPressed: _loading ? null : _createAccount,
                      child: _loading
                          ? const SizedBox(height: 24, width: 24,
                              child: CircularProgressIndicator(strokeWidth: 2))
                          : const Text('إنشاء الحساب'),
                    ),
                    const SizedBox(height: 16),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Flexible(child: Text('يوجد حساب بالفعل؟')),
                        TextButton(
                          onPressed: () => Navigator.pushReplacement(
                            context,
                            MaterialPageRoute(builder: (_) => const LoginPage()),
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
