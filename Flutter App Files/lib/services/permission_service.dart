import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';

class PermissionService {
  static Future<bool> requestLocationPermission(
      BuildContext context) async {
    final status = await Permission.location.request();

    if (status.isGranted) {
      return true;
    }

    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'تم رفض صلاحية الموقع. قد لا تعمل الملاحة بشكل صحيح.',
          ),
        ),
      );
    }

    return false;
  }

  static Future<bool> requestMicrophonePermission(
      BuildContext context) async {
    final status = await Permission.microphone.request();

    if (status.isGranted) {
      return true;
    }

    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'تم رفض صلاحية الميكروفون. قد لا تعمل الأوامر الصوتية بشكل صحيح.',
          ),
        ),
      );
    }

    return false;
  }
}