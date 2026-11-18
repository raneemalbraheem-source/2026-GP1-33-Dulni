import 'package:flutter/material.dart';

import '../widgets/app_bottom_navigation.dart';
import 'login_page.dart';
import 'signup_page.dart';

enum GuestFeature { favorites, profile }

class GuestAccessPage extends StatelessWidget {
  const GuestAccessPage({super.key, required this.feature});

  final GuestFeature feature;

  bool get _isFavorites => feature == GuestFeature.favorites;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final title = _isFavorites ? 'الأماكن المفضلة' : 'الملف الشخصي';
    final message = _isFavorites
        ? 'يرجى تسجيل الدخول لحفظ الأماكن المفضلة والاطّلاع عليها.'
        : 'يرجى تسجيل الدخول للوصول إلى ملفك الشخصي وإدارة إعداداتك.';

    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        appBar: AppBar(title: Text(title)),
        body: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 420),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Icon(
                      _isFavorites
                          ? Icons.favorite_border
                          : Icons.account_circle_outlined,
                      size: 72,
                      color: theme.colorScheme.primary,
                    ),
                    const SizedBox(height: 20),
                    Text(
                      title,
                      textAlign: TextAlign.center,
                      style: theme.textTheme.headlineSmall,
                    ),
                    const SizedBox(height: 12),
                    Text(
                      message,
                      textAlign: TextAlign.center,
                      style: theme.textTheme.bodyLarge,
                    ),
                    const SizedBox(height: 28),
                    FilledButton(
                      onPressed: () => Navigator.push(
                        context,
                        MaterialPageRoute<void>(
                          builder: (_) => const LoginPage(),
                        ),
                      ),
                      child: const Text('تسجيل الدخول'),
                    ),
                    const SizedBox(height: 12),
                    OutlinedButton(
                      onPressed: () => Navigator.push(
                        context,
                        MaterialPageRoute<void>(
                          builder: (_) => const SignupPage(),
                        ),
                      ),
                      child: const Text('إنشاء حساب'),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
        bottomNavigationBar: AppBottomNavigation(
          currentIndex: _isFavorites ? 2 : 3,
          isSignedIn: false,
          onTap: (index) {
            if (index == 1) {
              Navigator.pop(context);
            } else if (index == 2 && !_isFavorites) {
              Navigator.pushReplacement(
                context,
                MaterialPageRoute<void>(
                  builder: (_) => const GuestAccessPage(
                    feature: GuestFeature.favorites,
                  ),
                ),
              );
            } else if (index == 3 && _isFavorites) {
              Navigator.pushReplacement(
                context,
                MaterialPageRoute<void>(
                  builder: (_) => const GuestAccessPage(
                    feature: GuestFeature.profile,
                  ),
                ),
              );
            }
          },
        ),
      ),
    );
  }
}