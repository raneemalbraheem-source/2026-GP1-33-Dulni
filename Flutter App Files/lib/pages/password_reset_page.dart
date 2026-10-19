import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../services/auth_service.dart';

class PasswordResetPage extends StatefulWidget {
  final String initialEmail;
  const PasswordResetPage({super.key, this.initialEmail = ''});

  @override
  State<PasswordResetPage> createState() => _PasswordResetPageState();
}

class _PasswordResetPageState extends State<PasswordResetPage> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _authService = AuthService();
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    _emailController.text = widget.initialEmail;
  }

  @override
  void dispose() {
    _emailController.dispose();
    super.dispose();
  }

  Future<void> _sendResetLink() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _loading = true);
    try {
      await _authService.sendPasswordReset(_emailController.text.trim());
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('تم إرسال الطلب'),
          content: const Text(
            'إذا كان البريد الإلكتروني مسجلًا، فسيصل رابط إعادة تعيين كلمة المرور إلى صندوق البريد. يرجى اتباع التعليمات الواردة في الرسالة.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('حسنًا'),
            ),
          ],
        ),
      );
      if (mounted) Navigator.pop(context);
    } on FirebaseAuthException catch (e) {
      final message = e.code == 'invalid-email'
          ? 'صيغة البريد الإلكتروني غير صحيحة.'
          : e.code == 'network-request-failed'
              ? 'تعذر الاتصال بالإنترنت. يرجى المحاولة مجددًا.'
              : 'تعذر إرسال رابط إعادة التعيين. يرجى المحاولة مجددًا.';
      _showMessage(message);
    } catch (_) {
      _showMessage('تعذر إرسال رابط إعادة التعيين. يرجى المحاولة مجددًا.');
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
      appBar: AppBar(title: const Text('إعادة تعيين كلمة المرور')),
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
                    const Icon(Icons.lock_reset_outlined, size: 72),
                    const SizedBox(height: 16),
                    Text('استعادة الوصول إلى الحساب',
                        style: theme.textTheme.headlineMedium,
                        textAlign: TextAlign.center),
                    const SizedBox(height: 8),
                    const Text(
                      'أدخل البريد الإلكتروني المرتبط بالحساب لإرسال رابط إعادة تعيين كلمة المرور.',
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 28),
                    TextFormField(
                      controller: _emailController,
                      keyboardType: TextInputType.emailAddress,
                      textDirection: TextDirection.ltr,
                      decoration: const InputDecoration(
                        labelText: 'البريد الإلكتروني',
                        prefixIcon: Icon(Icons.email_outlined),
                      ),
                      validator: (value) {
                        final email = value?.trim() ?? '';
                        if (email.isEmpty) return 'يرجى إدخال البريد الإلكتروني.';
                        if (!RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(email)) {
                          return 'صيغة البريد الإلكتروني غير صحيحة.';
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: 24),
                    ElevatedButton(
                      onPressed: _loading ? null : _sendResetLink,
                      child: _loading
                          ? const SizedBox(height: 24, width: 24,
                              child: CircularProgressIndicator(strokeWidth: 2))
                          : const Text('إرسال رابط إعادة التعيين'),
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
