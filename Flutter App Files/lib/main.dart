import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'pages/home_page.dart';
import 'app_theme.dart';
import 'firebase_options.dart';
import 'pages/welcome_page.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );

  final preferences = await SharedPreferences.getInstance();
  final rememberMe = preferences.getBool('rememberMe') ?? false;

  if (!rememberMe) {
    await FirebaseAuth.instance.signOut();
  }

  final currentUser =
      await FirebaseAuth.instance.authStateChanges().first;

  final Widget initialPage = currentUser == null
      ? const WelcomePage()
      : const HomePage();

  runApp(DulniApp(initialPage: initialPage));
}

class DulniApp extends StatelessWidget {
  final Widget initialPage;

  const DulniApp({
    super.key,
    required this.initialPage,
  });

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
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
      // يتبع مظهر التطبيق إعدادات الجهاز: فاتح أو داكن.
      themeMode: ThemeMode.system,
      home: initialPage,
    );
  }
}
