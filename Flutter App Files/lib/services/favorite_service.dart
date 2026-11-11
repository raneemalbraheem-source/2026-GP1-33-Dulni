import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

class FavoriteService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  String? get _uid => FirebaseAuth.instance.currentUser?.uid;

  CollectionReference<Map<String, dynamic>> get _favoritesCollection {
    return _firestore
        .collection('User')
        .doc(_uid)
        .collection('favoriteLocations');
  }

  Future<void> addFavorite({
    required String name,
    required double latitude,
    required double longitude,
  }) async {
    await _favoritesCollection.add({
      'name': name,
      'latitude': latitude,
      'longitude': longitude,
      'createdAt': FieldValue.serverTimestamp(),
    });
  }

  Stream<QuerySnapshot<Map<String, dynamic>>> getFavorites() {
    return _favoritesCollection
        .orderBy('createdAt', descending: true)
        .snapshots();
  }

  Future<void> deleteFavorite(String favoriteId) async {
    await _favoritesCollection.doc(favoriteId).delete();
  }
}