
import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import 'voice_feedback_service.dart';

class PermissionService {
  static Future<bool> requestLocationPermission(
    BuildContext context) async {
  final currentStatus = await Permission.location.status;

  if (currentStatus.isGranted) {
    return true;
  }

  await VoiceFeedbackService.instance.speak(
    'يجب منح دُلّني إذن استخدام الموقع لتحديد موقعك الحالي وبدء الملاحة.',
  );

  if (!context.mounted) return false;

  return _requestPermission(
    context: context,
    permission: Permission.location,
    title: 'صلاحية الموقع',
    explanation:
        'يحتاج دُلّني إلى صلاحية الموقع لتحديد موقعك الحالي '
        'ومساعدتك في بدء الملاحة.',
    deniedMessage:
        'تم رفض إذن الموقع. لن يتمكن دُلّني من تحديد موقعك الحالي، '
        'ويمكنك تحديد نقطة البدء يدوياً لكن خدمات الملاحة قد لا تعمل بشكل صحيح.',
  );
}

  static Future<bool> requestMicrophonePermission(
    BuildContext context) async {
  final currentStatus = await Permission.microphone.status;

  if (currentStatus.isGranted) {
    return true;
  }

  await VoiceFeedbackService.instance.speak(
    'يجب منح دُلّني إذن استخدام الميكروفون قبل استخدام التجربة الصوتية.',
  );

  if (!context.mounted) return false;

  return _requestPermission(
    context: context,
    permission: Permission.microphone,
    title: 'صلاحية الميكروفون',
    explanation:
        'يحتاج دُلّني إلى صلاحية الميكروفون حتى تتمكن من '
        'استخدام الأوامر الصوتية للتحكم في التطبيق.',
    deniedMessage:
        'تم رفض إذن الميكروفون، ولن تعمل الأوامر الصوتية بشكل صحيح. '
        'يمكنك المتابعة باستخدام الإدخال اليدوي.',
  );
}

  static Future<bool> _requestPermission({
    required BuildContext context,
    required Permission permission,
    required String title,
    required String explanation,
    required String deniedMessage,
  }) async {
    final status = await permission.request();

    if (status.isGranted) {
      return true;
    }

    if (!context.mounted) return false;

    final openSettings = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(title),
        content: Text(explanation),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('إلغاء'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('فتح الإعدادات'),
          ),
        ],
      ),
    );

    if (!context.mounted) return false;

    if (openSettings == true) {
      await openAppSettings();
      return false;
    }

    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(deniedMessage),
        ),
      );

    return false;
  }
}
