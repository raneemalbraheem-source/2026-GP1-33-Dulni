import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../services/favorite_service.dart';
import '../widgets/app_bottom_navigation.dart';
import 'profile_page.dart';
import '../services/logout_helper.dart';

class FavoritePage extends StatelessWidget {
  const FavoritePage({super.key});

  @override
  Widget build(BuildContext context) {
    final favoriteService = FavoriteService();

    return Scaffold(
      appBar: AppBar(
        automaticallyImplyLeading: false,
        title: const Text('المواقع المفضلة'),
      ),
      

      body: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: favoriteService.getFavorites(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(
              child: CircularProgressIndicator(),
            );
          }

         if (snapshot.hasError) {
           return Center(
           child: Text(
             snapshot.error.toString(),
              ),
             );
             }

          final favorites = snapshot.data?.docs ?? [];

          if (favorites.isEmpty) {
            return const Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.favorite_border,
                    size: 80,
                    color: Colors.grey,
                  ),
                  SizedBox(height: 16),
                  Text(
                    'لا توجد مواقع مفضلة حالياً',
                    style: TextStyle(fontSize: 18),
                  ),
                ],
              ),
            );
          }

          return ListView.builder(
            padding: const EdgeInsets.all(12),
            itemCount: favorites.length,
            itemBuilder: (context, index) {
              final favorite = favorites[index];
              final data = favorite.data();

              final name = data['name'] ?? 'موقع غير معروف';
              final latitude = data['latitude'];
              final longitude = data['longitude'];

              return Card(
                margin: const EdgeInsets.only(bottom: 10),
                child: ListTile(
                  leading: const CircleAvatar(
                    child: Icon(
                      Icons.favorite,
                      color: Colors.red,
                    ),
                  ),

                  title: Text(
                    name,
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                    ),
                  ),

                  subtitle: Text(
                    'Lat: $latitude\nLng: $longitude',
                  ),

                  onTap: () {
                    Navigator.pop(
                      context,
                      {
                        'name': name,
                        'latitude': latitude,
                        'longitude': longitude,
                      },
                    );
                  },

                  trailing: IconButton(
                    icon: const Icon(
                      Icons.delete,
                      color: Colors.red,
                    ),
                    onPressed: () async {
                      final confirm = await showDialog<bool>(
                        context: context,
                        builder: (_) => AlertDialog(
                          title: const Text('حذف الموقع'),
                          content: const Text(
                            'هل أنت متأكد من حذف هذا الموقع من المفضلة؟',
                          ),
                          actions: [
                            TextButton(
                              onPressed: () =>
                                  Navigator.pop(context, false),
                              child: const Text('إلغاء'),
                            ),
                            ElevatedButton(
                              onPressed: () =>
                                  Navigator.pop(context, true),
                              child: const Text('حذف'),
                            ),
                          ],
                        ),
                      );

                      if (confirm == true) {
                        await favoriteService.deleteFavorite(
                          favorite.id,
                        );

                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text(
                                'تم حذف الموقع من المفضلة',
                              ),
                            ),
                          );
                        }
                      }
                    },
                  ),
                ),
              );
            },
          );
        },
      ),
      bottomNavigationBar: AppBottomNavigation(
  currentIndex: 2,
  isSignedIn: FirebaseAuth.instance.currentUser != null,
  onTap: (index) async {

  if (index == 0) {
    showLogoutDialog(context);
  }

  else if (index == 1) {
    Navigator.pop(context);
  }

  else if (index == 2) {
    return;
  }

  else if (index == 3) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => const ProfilePage(),
      ),
    );
  }
}
),
    );
  }
}