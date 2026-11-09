import 'package:flutter/material.dart';

class AppBottomNavigation extends StatelessWidget {
  final int currentIndex;
  final Function(int) onTap;
  final bool isSignedIn;

  const AppBottomNavigation({
    super.key,
    required this.currentIndex,
    required this.onTap,
    this.isSignedIn = true,
  });

  @override
  Widget build(BuildContext context) {
    final items = <(int, BottomNavigationBarItem)>[
      if (isSignedIn)
        (0, const BottomNavigationBarItem(icon: Icon(Icons.logout), label: 'خروج')),
      (1, const BottomNavigationBarItem(icon: Icon(Icons.map), label: 'الخريطة')),
      (2, const BottomNavigationBarItem(icon: Icon(Icons.favorite), label: 'المفضلة')),
      (3, const BottomNavigationBarItem(icon: Icon(Icons.person), label: 'الحساب')),
    ];
    final visibleIndex = items.indexWhere((item) => item.$1 == currentIndex);
    return BottomNavigationBar(
      currentIndex: visibleIndex < 0 ? 0 : visibleIndex,
      type: BottomNavigationBarType.fixed,
      onTap: (index) => onTap(items[index].$1),
      items: items.map((item) => item.$2).toList(),
    );
  }
}
