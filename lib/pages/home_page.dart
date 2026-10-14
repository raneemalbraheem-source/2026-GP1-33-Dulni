import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

import 'profile_page.dart';

class HomePage extends StatelessWidget {
  const HomePage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('دلني'),
        actions: [
          IconButton(
            tooltip: 'الملف الشخصي',
            icon: const Icon(Icons.person_outline),
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => const ProfilePage(),
              ),
            ),
          ),
        ],
      ),
      body: const SafeArea(
        child: GoogleMap(
          initialCameraPosition: CameraPosition(
            target: LatLng(24.7136, 46.6753),
            zoom: 14,
          ),
        ),
      ),
    );
  }
}