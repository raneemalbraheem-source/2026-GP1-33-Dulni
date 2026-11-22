import 'dart:async';

import 'package:app_links/app_links.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:firebase_app_check/firebase_app_check.dart';

import 'app_theme.dart';
import 'firebase_options.dart';
import 'pages/home_page.dart';
import 'pages/login_page.dart';
import 'services/auth_service.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );

await FirebaseAppCheck.instance.activate(
  providerAndroid: const AndroidDebugProvider(),
);

  runApp(const DulniApp());
}

class DulniApp extends StatefulWidget {
  const DulniApp({super.key});

  @override
  State<DulniApp> createState() => _DulniAppState();
}

class _DulniAppState extends State<DulniApp> {
  static const String _emailLinkHost = 'dulni-d2dd1.firebaseapp.com';
  static const String _emailLinkPath = '/__/auth/links';

  final AppLinks _appLinks = AppLinks();
  final AuthService _authService = AuthService();
  final FirebaseAuth _firebaseAuth = FirebaseAuth.instance;

  final GlobalKey<NavigatorState> _navigatorKey = GlobalKey<NavigatorState>();
  final GlobalKey<ScaffoldMessengerState> _scaffoldMessengerKey =
      GlobalKey<ScaffoldMessengerState>();

  StreamSubscription<Uri>? _linkSubscription;
  final Set<String> _linksBeingHandled = <String>{};

  @override
  void initState() {
    super.initState();

    _linkSubscription = _appLinks.uriLinkStream.listen(
      (uri) {
        unawaited(_handleIncomingLink(uri));
      },
      onError: (Object error) {
        debugPrint('App link reception failed.');
      },
    );

    // Handles the case where the app was completely closed before
    // the user opened the email authentication link.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      unawaited(_handleInitialLink());
    });
  }

  Future<void> _handleInitialLink() async {
    try {
      final initialUri = await _appLinks.getInitialLink();
      if (initialUri != null) {
        await _handleIncomingLink(initialUri);
      }
    } catch (error) {
      debugPrint('Initial app link could not be read.');
    }
  }

  bool _isDulniEmailLink(Uri uri) {
    return uri.scheme == 'https' &&
        uri.host == _emailLinkHost &&
        uri.path.startsWith(_emailLinkPath);
  }

  Future<void> _handleIncomingLink(Uri uri) async {
    if (!_isDulniEmailLink(uri)) return;

    final emailLink = uri.toString();

    // Prevent the same link from being processed twice when both the
    // initial-link and stream callbacks deliver it.
    if (!_linksBeingHandled.add(emailLink)) return;

    try {
      if (!await _authService.isEmailSignInLink(emailLink)) {
        _showMessage(
          'رابط تسجيل الدخول غير صالح أو انتهت صلاحيته. '
          'يرجى طلب رابط جديد.',
        );
        return;
      }

      var email = await _authService.getPendingEmail();

      // Firebase requires the email address again if the link is opened
      // on a device that does not have the original pending email saved.
      if (email == null || email.trim().isEmpty) {
        email = await _askForRequiredText(
          title: 'تأكيد البريد الإلكتروني',
          message: 'أدخل البريد الإلكتروني الذي استلم رابط دُلّني.',
          label: 'البريد الإلكتروني',
          keyboardType: TextInputType.emailAddress,
        );
      }

      if (email.trim().isEmpty) return;

      final pendingAction = await _authService.getPendingEmailLinkAction();
      if (pendingAction == 'deleteAccount') {
        await _authService.completeAccountDeletionWithEmailLink(
          email: email,
          emailLink: emailLink,
        );
        await _authService.clearPendingEmailLinkData();
        _showMessage('تم حذف الحساب بنجاح.');
        return;
      }

      await _authService.completeEmailLinkSignIn(
        email: email,
        emailLink: emailLink,
      );

      // Use the pending sign-up name when available. For an existing account,
      // read the saved profile name instead of asking again.
      var fullName = await _authService.getPendingName();
      if (fullName == null || fullName.trim().isEmpty) {
        fullName = await _authService.getFullName();
      }

      // A sign-up link opened on another device has no locally saved name.
      // Ask for it only when the account does not already have a profile.
      if (fullName == null || fullName.trim().isEmpty) {
        fullName = await _askForRequiredText(
          title: 'إكمال إنشاء الحساب',
          message: 'أدخل اسمك لإكمال ملفك الشخصي في دُلّني.',
          label: 'الاسم الكامل',
          keyboardType: TextInputType.name,
        );
      }

      if (fullName.trim().isEmpty) {
        _showMessage(
          'تم تسجيل الدخول، لكن يلزم إدخال الاسم لإكمال ملفك الشخصي.',
        );
        return;
      }

      await _authService.createUserProfileIfMissing(fullName: fullName);
      await _authService.clearPendingEmailLinkData();

      _showMessage('تم تسجيل الدخول بنجاح. أهلًا بك في دُلّني.');
      // authStateChanges() below switches the app to HomePage automatically.
    } on FirebaseAuthException catch (error) {
      debugPrint('Email link authentication failed: ${error.code}');

      if (error.code == 'expired-action-code' ||
          error.code == 'invalid-action-code' ||
          error.code == 'invalid-email-link') {
        _showMessage(
          'رابط تسجيل الدخول غير صالح أو انتهت صلاحيته. '
          'يرجى طلب رابط جديد.',
        );
      } else if (error.code == 'network-request-failed') {
        _showMessage('تعذر الاتصال بالإنترنت. تحقق من الاتصال وحاول مجددًا.');
      } else {
        _showMessage('تعذر إكمال تسجيل الدخول. يرجى المحاولة مجددًا.');
      }
    } catch (error) {
      debugPrint('Email link processing failed.');
      _showMessage('تعذر إكمال تسجيل الدخول. تحقق من الاتصال وحاول مجددًا.');
    }
  }

  Future<String> _askForRequiredText({
    required String title,
    required String message,
    required String label,
    required TextInputType keyboardType,
  }) async {
    final context = _navigatorKey.currentContext;
    if (context == null) return '';

    final controller = TextEditingController();

    final result = await showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) {
        return PopScope(
          canPop: false,
          child: AlertDialog(
            title: Text(title),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(message),
                const SizedBox(height: 16),
                TextField(
                  controller: controller,
                  autofocus: true,
                  keyboardType: keyboardType,
                  textDirection: keyboardType == TextInputType.emailAddress
                      ? TextDirection.ltr
                      : TextDirection.rtl,
                  decoration: InputDecoration(
                    labelText: label,
                    border: const OutlineInputBorder(),
                  ),
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () {
                  final value = controller.text.trim();
                  if (value.isNotEmpty) {
                    Navigator.of(dialogContext).pop(value);
                  }
                },
                child: const Text('متابعة'),
              ),
            ],
          ),
        );
      },
    );

    controller.dispose();
    return result?.trim() ?? '';
  }

  void _showMessage(String message) {
    _scaffoldMessengerKey.currentState
      ?..hideCurrentSnackBar()
      ..showSnackBar(
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
  void dispose() {
    _linkSubscription?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      navigatorKey: _navigatorKey,
      scaffoldMessengerKey: _scaffoldMessengerKey,
      debugShowCheckedModeBanner: false,
      title: 'دلني',
      locale: const Locale('ar', 'SA'),
      supportedLocales: const [Locale('ar', 'SA')],
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      theme: buildDulniTheme(Brightness.light),
      darkTheme: buildDulniTheme(Brightness.dark),
      themeMode: ThemeMode.system,
      home: StreamBuilder<User?>(
        stream: _firebaseAuth.authStateChanges(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Scaffold(
              body: Center(child: CircularProgressIndicator()),
            );
          }

          if (snapshot.hasData) {
            return const HomePage();
          }

          return const LoginPage();
        },
      ),
    );
  }
}
