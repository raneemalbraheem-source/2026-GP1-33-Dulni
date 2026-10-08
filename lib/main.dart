import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:firebase_core/firebase_core.dart';
import 'firebase_options.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );
  runApp(const DulniApp());
}

/// Shared colors for the welcome screen and future application screens.
abstract final class DulniColors {
  static const navy = Color(0xFF011B36);
  static const green = Color(0xFF53B129);
  static const darkGreen = Color(0xFF1F6B2E);
  static const secondaryText = Color(0xFF475569);
  static const fieldBorder = Color(0xFF64748B);
  static const softBackground = Color(0xFFF8FAFC);
  static const error = Color(0xFFB42318);
  static const darkSurface = Color(0xFF102D47);
}

ThemeData buildDulniTheme(Brightness brightness) {
  final isDark = brightness == Brightness.dark;
  final surface = isDark ? DulniColors.navy : Colors.white;
  final foreground = isDark ? Colors.white : DulniColors.navy;
  final secondaryText =
      isDark ? const Color(0xFFCBD5E1) : DulniColors.secondaryText;
  final actionBackground =
      isDark ? DulniColors.green : DulniColors.navy;
  final actionForeground = isDark ? DulniColors.navy : Colors.white;
  final outline =
      isDark ? const Color(0xFF94A3B8) : DulniColors.fieldBorder;

  final scheme = ColorScheme.fromSeed(
    seedColor: DulniColors.navy,
    brightness: brightness,
  ).copyWith(
    primary: actionBackground,
    onPrimary: actionForeground,
    secondary: isDark ? DulniColors.green : DulniColors.darkGreen,
    onSecondary: isDark ? DulniColors.navy : Colors.white,
    surface: surface,
    onSurface: foreground,
    onSurfaceVariant: secondaryText,
    surfaceContainerHighest:
        isDark ? DulniColors.darkSurface : DulniColors.softBackground,
    outline: outline,
    outlineVariant:
        isDark ? const Color(0xFF475569) : const Color(0xFFE2E8F0),
    error: isDark ? const Color(0xFFFFB4AB) : DulniColors.error,
    onError: isDark ? const Color(0xFF690005) : Colors.white,
    errorContainer:
        isDark ? const Color(0xFF4B1512) : const Color(0xFFFEECE9),
    onErrorContainer:
        isDark ? const Color(0xFFFFDAD6) : DulniColors.error,
  );

  TextStyle text(double size, FontWeight weight, {Color? color}) => TextStyle(
        fontFamily: 'NotoSansArabic',
        fontFamilyFallback: const ['NotoSans'],
        fontSize: size,
        fontWeight: weight,
        height: 1.5,
        color: color ?? foreground,
      );

  final buttonShape = RoundedRectangleBorder(
    borderRadius: BorderRadius.circular(12),
  );
  final inputBorder = OutlineInputBorder(
    borderRadius: BorderRadius.circular(12),
    borderSide: BorderSide(color: outline, width: 1.5),
  );

  return ThemeData(
    useMaterial3: true,
    brightness: brightness,
    colorScheme: scheme,
    scaffoldBackgroundColor: surface,
    fontFamily: 'NotoSansArabic',
    fontFamilyFallback: const ['NotoSans'],
    visualDensity: VisualDensity.standard,
    materialTapTargetSize: MaterialTapTargetSize.padded,
    textTheme: TextTheme(
      displayLarge: text(38, FontWeight.w700),
      displayMedium: text(34, FontWeight.w700),
      displaySmall: text(32, FontWeight.w700),
      headlineLarge: text(32, FontWeight.w700),
      headlineMedium: text(28, FontWeight.w700),
      headlineSmall: text(24, FontWeight.w600),
      titleLarge: text(22, FontWeight.w600),
      titleMedium: text(20, FontWeight.w600),
      titleSmall: text(18, FontWeight.w500),
      bodyLarge: text(20, FontWeight.w400),
      bodyMedium: text(18, FontWeight.w400),
      bodySmall: text(18, FontWeight.w400, color: secondaryText),
      labelLarge: text(20, FontWeight.w600),
      labelMedium: text(18, FontWeight.w500),
      labelSmall: text(18, FontWeight.w500),
    ),
    appBarTheme: AppBarTheme(
      backgroundColor: surface,
      foregroundColor: foreground,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      centerTitle: false,
      titleTextStyle: text(24, FontWeight.w600),
      systemOverlayStyle:
          isDark ? SystemUiOverlayStyle.light : SystemUiOverlayStyle.dark,
    ),
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        backgroundColor: actionBackground,
        foregroundColor: actionForeground,
        minimumSize: const Size(48, 60),
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
        elevation: 0,
        shape: buttonShape,
        textStyle: text(20, FontWeight.w600),
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: actionBackground,
        foregroundColor: actionForeground,
        minimumSize: const Size(48, 60),
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
        shape: buttonShape,
        textStyle: text(20, FontWeight.w600),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: foreground,
        minimumSize: const Size(48, 60),
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
        side: BorderSide(color: foreground, width: 2),
        shape: buttonShape,
        textStyle: text(20, FontWeight.w600),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: foreground,
        minimumSize: const Size(48, 48),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        textStyle: text(18, FontWeight.w600),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: scheme.surfaceContainerHighest,
      labelStyle: text(18, FontWeight.w500),
      hintStyle: text(18, FontWeight.w400, color: secondaryText),
      errorStyle: text(18, FontWeight.w500, color: scheme.error),
      errorMaxLines: 4,
      contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
      border: inputBorder,
      enabledBorder: inputBorder,
      focusedBorder: inputBorder.copyWith(
        borderSide: BorderSide(color: scheme.primary, width: 2.5),
      ),
      errorBorder: inputBorder.copyWith(
        borderSide: BorderSide(color: scheme.error, width: 2),
      ),
      focusedErrorBorder: inputBorder.copyWith(
        borderSide: BorderSide(color: scheme.error, width: 2.5),
      ),
    ),
    dividerTheme: DividerThemeData(color: scheme.outlineVariant),
    iconTheme: IconThemeData(color: foreground, size: 28),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: surface,
      indicatorColor:
          isDark ? const Color(0xFF23452D) : const Color(0xFFEAF5EC),
      labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
      labelTextStyle: WidgetStatePropertyAll(text(18, FontWeight.w500)),
      iconTheme: WidgetStatePropertyAll(
        IconThemeData(color: foreground, size: 28),
      ),
    ),
  );
}

class DulniApp extends StatelessWidget {
  const DulniApp({super.key});

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
      themeMode: ThemeMode.system,
      // Arabic localization supplies RTL throughout routes and dialogs.
      // System text scaling remains enabled; do not override TextScaler.
      home: const WelcomePage(),
    );
  }
}

class WelcomePage extends StatefulWidget {
  const WelcomePage({super.key});

  @override
  State<WelcomePage> createState() => _WelcomePageState();
}

class _WelcomePageState extends State<WelcomePage> {
  @override
  void initState() {
    super.initState();
    // Show Android's permission prompt after the first screen is ready.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _requestMicrophonePermission();
    });
  }

  Future<void> _requestMicrophonePermission() async {
    try {
      final status = await Permission.microphone.status;
      if (!mounted) return;

      // Permission is already available. This does not start recording.
      if (status.isGranted) return;

      // Android will not show another prompt in these cases.
      // The user can change permission later in Android app settings.
      if (status.isPermanentlyDenied || status.isRestricted) return;

      // Denial leaves the non-voice welcome actions available.
      // Connect speech recognition later, and start it only after checking
      // that microphone permission is granted.
      await Permission.microphone.request();
    } on PlatformException {
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('تعذر طلب الإذن'),
          content: const Text(
            'تعذر طلب إذن الميكروفون. يمكنك المتابعة، '
            'ومراجعة الإذن لاحقًا من إعدادات الجهاز.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('متابعة'),
            ),
          ],
        ),
      );
    }
  }

  void _goToPage(String title) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => PlaceholderPage(title: title),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;

    return Scaffold(
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            final availableHeight = constraints.maxHeight - 48;
            return SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
              child: Center(
                child: ConstrainedBox(
                  constraints: BoxConstraints(
                    maxWidth: 520,
                    minHeight: availableHeight > 0 ? availableHeight : 0,
                  ),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Center(
                        child: Semantics(
                          image: true,
                          label: 'شعار تطبيق دلني',
                          excludeSemantics: true,
                          child: Container(
                            width: 180,
                            padding: const EdgeInsets.all(16),
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(16),
                              border: Border.all(color: colors.outlineVariant),
                            ),
                            child: Image.asset(
                              'assets/images/dulni_logo.jpeg',
                              fit: BoxFit.contain,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 24),
                      Semantics(
                        header: true,
                        headingLevel: 1,
                        child: Text(
                          'دلني',
                          style: theme.textTheme.displayLarge,
                          textAlign: TextAlign.center,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'ندلّك ونمشي معك خطوة بخطوة ...',
                        style: theme.textTheme.titleLarge,
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 16),
                      Text(
                        'ندلّك لوجهتك بالعربي، بدون تيرن رايت وتيرن ليفت! '
                        'وننبهك للعوائق اللي في طريقك ونتأكد إنك توصل بأمان.',
                        style: theme.textTheme.bodyLarge?.copyWith(
                          color: colors.onSurfaceVariant,
                        ),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 32),
                      // Standard buttons provide their own TalkBack labels.
                      ElevatedButton(
                        onPressed: () => _goToPage('إنشاء حساب'),
                        child: const Text('إنشاء حساب', textAlign: TextAlign.center),
                      ),
                      const SizedBox(height: 16),
                      OutlinedButton(
                        onPressed: () => _goToPage('تسجيل الدخول'),
                        child: const Text('تسجيل الدخول', textAlign: TextAlign.center),
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

/// Replace these destinations with real authentication screens later.
/// These pages do not register or authenticate users.
class PlaceholderPage extends StatelessWidget {
  final String title;
  const PlaceholderPage({super.key, required this.title});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: Text(title),
        leading: BackButton(
          onPressed: () => Navigator.of(context).pop(),
        ),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Semantics(
                header: true,
                headingLevel: 1,
                child: Text(title, style: theme.textTheme.headlineMedium),
              ),
              const SizedBox(height: 16),
              Text(
                'هذه صفحة مؤقتة. سيُضاف نموذج $title هنا لاحقًا.',
                style: theme.textTheme.bodyLarge,
              ),
              const SizedBox(height: 24),
              OutlinedButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('العودة إلى صفحة الترحيب'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
