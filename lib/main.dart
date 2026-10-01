import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const DulniApp());
}

class DulniApp extends StatelessWidget {
  const DulniApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'دُلّني',
      theme: ThemeData(
        useMaterial3: true,
        fontFamily: 'Arial',

        // Simple, high-contrast color system.
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF155EEF),
          brightness: Brightness.light,
        ),

        scaffoldBackgroundColor: Colors.white,

        appBarTheme: const AppBarTheme(
          backgroundColor: Colors.white,
          foregroundColor: Colors.black,
          elevation: 0,
        ),

        textTheme: const TextTheme(
          headlineLarge: TextStyle(
            fontSize: 32,
            fontWeight: FontWeight.bold,
            color: Colors.black,
          ),
          headlineMedium: TextStyle(
            fontSize: 28,
            fontWeight: FontWeight.bold,
            color: Colors.black,
          ),
          bodyLarge: TextStyle(
            fontSize: 18,
            color: Colors.black,
            height: 1.5,
          ),
          bodyMedium: TextStyle(
            fontSize: 16,
            color: Colors.black,
            height: 1.5,
          ),
        ),

        elevatedButtonTheme: ElevatedButtonThemeData(
          style: ElevatedButton.styleFrom(
            minimumSize: const Size(double.infinity, 64),
            padding: const EdgeInsets.symmetric(
              horizontal: 24,
              vertical: 16,
            ),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
            textStyle: const TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
      ),

      // Arabic / RTL
      locale: const Locale('ar'),

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
  bool _isRequestingPermission = false;

  @override
  void initState() {
    super.initState();

    // Request microphone permission when the application starts.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _requestMicrophonePermission();
    });
  }

  Future<void> _requestMicrophonePermission() async {
    if (_isRequestingPermission) return;

    setState(() {
      _isRequestingPermission = true;
    });

    final status = await Permission.microphone.request();

    if (!mounted) return;

    setState(() {
      _isRequestingPermission = false;
    });

    if (status.isDenied) {
      _showPermissionMessage(
        'للاستفادة من الميزات الصوتية، يحتاج دُلّني إلى الوصول إلى الميكروفون.',
      );
    } else if (status.isPermanentlyDenied) {
      _showPermissionMessage(
        'تم رفض صلاحية الميكروفون. يمكنك تفعيلها من إعدادات الجهاز.',
        showSettingsButton: true,
      );
    }
  }

  void _showPermissionMessage(
    String message, {
    bool showSettingsButton = false,
  }) {
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text(
            'صلاحية الميكروفون',
            textAlign: TextAlign.right,
          ),
          content: Text(
            message,
            textAlign: TextAlign.right,
            style: const TextStyle(
              fontSize: 18,
              height: 1.5,
            ),
          ),
          actions: [
            if (showSettingsButton)
              TextButton(
                onPressed: () {
                  Navigator.pop(context);
                  openAppSettings();
                },
                child: const Text(
                  'فتح الإعدادات',
                  style: TextStyle(fontSize: 17),
                ),
              ),
            TextButton(
              onPressed: () {
                Navigator.pop(context);
              },
              child: const Text(
                'حسنًا',
                style: TextStyle(fontSize: 17),
              ),
            ),
          ],
        );
      },
    );
  }

  void _goToRegister() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => const PlaceholderPage(
          title: 'إنشاء حساب',
        ),
      ),
    );
  }

  void _goToLogin() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => const PlaceholderPage(
          title: 'تسجيل الدخول',
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        body: SafeArea(
          child: LayoutBuilder(
            builder: (context, constraints) {
              return SingleChildScrollView(
                padding: const EdgeInsets.symmetric(
                  horizontal: 24,
                  vertical: 32,
                ),
                child: ConstrainedBox(
                  constraints: BoxConstraints(
                    minHeight: constraints.maxHeight - 64,
                  ),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Semantics(
                        label: 'شعار تطبيق دُلّني',
                        image: true,
                        child: Container(
                          width: 150,
                          height: 150,
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(30),
                            color: const Color(0xFFF2F5F9),
                          ),
                          child: const Center(
                            child: Icon(
                              Icons.navigation_rounded,
                              size: 80,
                              color: Color(0xFF155EEF),
                            ),
                          ),
                        ),
                      ),

                      const SizedBox(height: 28),

                      Semantics(
                        header: true,
                        child: Text(
                          'دُلّني',
                          style: Theme.of(context)
                              .textTheme
                              .headlineLarge
                              ?.copyWith(
                                fontSize: 38,
                              ),
                          textAlign: TextAlign.center,
                        ),
                      ),

                      const SizedBox(height: 12),

                      const Text(
                        'تنقّل أسهل، بصوت أوضح',
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.w600,
                          color: Color(0xFF333333),
                          height: 1.5,
                        ),
                        textAlign: TextAlign.center,
                      ),

                      const SizedBox(height: 16),

                      const Text(
                        'تطبيق دُلّني يساعدك على التنقل بأمان من خلال تجربة صوتية مخصصة.',
                        style: TextStyle(
                          fontSize: 18,
                          color: Color(0xFF444444),
                          height: 1.6,
                        ),
                        textAlign: TextAlign.center,
                      ),

                      const SizedBox(height: 48),

                      Semantics(
                        button: true,
                        label: 'إنشاء حساب',
                        hint: 'اضغط مرتين لإنشاء حساب جديد',
                        child: SizedBox(
                          width: double.infinity,
                          child: ElevatedButton(
                            onPressed: _goToRegister,
                            child: const Text('إنشاء حساب'),
                          ),
                        ),
                      ),

                      const SizedBox(height: 16),

                      Semantics(
                        button: true,
                        label: 'تسجيل الدخول',
                        hint: 'اضغط مرتين لتسجيل الدخول إلى حسابك',
                        child: SizedBox(
                          width: double.infinity,
                          child: OutlinedButton(
                            onPressed: _goToLogin,
                            style: OutlinedButton.styleFrom(
                              minimumSize: const Size(
                                double.infinity,
                                64,
                              ),
                              side: const BorderSide(
                                width: 2,
                                color: Color(0xFF155EEF),
                              ),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(16),
                              ),
                              textStyle: const TextStyle(
                                fontSize: 20,
                                fontWeight: FontWeight.bold,
                              ),
                              foregroundColor:
                                  const Color(0xFF155EEF),
                            ),
                            child: const Text('تسجيل الدخول'),
                          ),
                        ),
                      ),

                      const SizedBox(height: 28),

                      Semantics(
                        button: true,
                        label: 'إعادة طلب صلاحية الميكروفون',
                        hint: 'اضغط لطلب الوصول إلى الميكروفون مرة أخرى',
                        child: TextButton.icon(
                          onPressed: _requestMicrophonePermission,
                          icon: const Icon(
                            Icons.mic_none_rounded,
                            size: 24,
                          ),
                          label: const Text(
                            'السماح بالوصول إلى الميكروفون',
                            style: TextStyle(
                              fontSize: 17,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}

class PlaceholderPage extends StatelessWidget {
  final String title;

  const PlaceholderPage({
    super.key,
    required this.title,
  });

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        appBar: AppBar(
          title: Text(title),
        ),
        body: Center(
          child: Text(
            title,
            style: const TextStyle(
              fontSize: 28,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
      ),
    );
  }
}
