import 'package:flutter/material.dart';

import '../services/auth_service.dart';
import '../pages/login_page.dart';

Future<void> showLogoutDialog(BuildContext context) async {
  final shouldSignOut = await showDialog<bool>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: const Text('تسجيل الخروج؟'),
      content: const Text('هل تريد تسجيل الخروج من حسابك؟'),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(dialogContext, false),
          child: const Text('إلغاء'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(dialogContext, true),
          child: const Text('تسجيل الخروج'),
        ),
      ],
    ),
  );

  if (shouldSignOut != true) return;

  await AuthService().signOut();

  if (!context.mounted) return;

  Navigator.of(context).pushAndRemoveUntil(
    MaterialPageRoute(
      builder: (_) => const LoginPage(),
    ),
    (_) => false,
  );
}