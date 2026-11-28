import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

class FavoriteService {
  FavoriteService({FirebaseFirestore? firestore, FirebaseAuth? auth})
    : _firestore = firestore ?? FirebaseFirestore.instance,
      _auth = auth ?? FirebaseAuth.instance;

  final FirebaseFirestore _firestore;
  final FirebaseAuth _auth;
  static final Set<String> _migratedUsers = {};

  User _requireUser() {
    final user = _auth.currentUser;
    if (user == null) {
      throw StateError('A signed-in user is required to manage favorites.');
    }
    return user;
  }

  CollectionReference<Map<String, dynamic>> get _favoritesCollection =>
      _firestore.collection('favoriteLocations');

  DocumentReference<Map<String, dynamic>> _userReference(User user) =>
      _firestore.collection('User').doc(user.uid);

  Future<void> migrateLegacyData() async {
    final user = _requireUser();
    if (!_migratedUsers.add(user.uid)) return;

    try {
      await _migrateLegacyFavorites(user);
      await _migrateLegacySessions(user);
    } catch (_) {
      _migratedUsers.remove(user.uid);
      rethrow;
    }
  }

  Future<void> _migrateLegacyFavorites(User user) async {
    final userRef = _userReference(user);
    final current = await _favoritesCollection
        .where('userRef', isEqualTo: userRef)
        .get();
    final currentIds = current.docs.map((document) => document.id).toSet();
    final legacy = await userRef.collection('favoriteLocations').get();

    for (final document in legacy.docs) {
      final old = document.data();
      final placeName = old['placeName'] ?? old['name'];
      final address = old['address'] ?? placeName;
      final oldLocation = old['location'];
      GeoPoint? location;
      if (oldLocation is GeoPoint) {
        location = oldLocation;
      } else if (old['latitude'] is num && old['longitude'] is num) {
        location = GeoPoint(
          (old['latitude'] as num).toDouble(),
          (old['longitude'] as num).toDouble(),
        );
      }
      if (placeName is! String || address is! String || location == null) {
        continue;
      }

      final target = _favoritesCollection.doc('legacy_${user.uid}_${document.id}');
      if (currentIds.contains(target.id)) continue;
      await target.set({
        'userRef': userRef,
        'placeName': placeName,
        'address': address,
        'location': location,
        'createdAt': FieldValue.serverTimestamp(),
      });
    }
  }

  Future<void> _migrateLegacySessions(User user) async {
    final userRef = _userReference(user);
    final sessions = _firestore.collection('navigationSessions');
    final current = await sessions.where('userRef', isEqualTo: userRef).get();
    final currentIds = current.docs.map((document) => document.id).toSet();
    final legacy = await userRef.collection('navigationSessions').get();

    for (final document in legacy.docs) {
      final old = document.data();
      if (old['startLocation'] is! GeoPoint ||
          old['destination'] is! GeoPoint ||
          old['startedAt'] is! Timestamp ||
          old['status'] is! String ||
          old['distance'] is! num) {
        continue;
      }

      final target = sessions.doc('legacy_${user.uid}_${document.id}');
      if (currentIds.contains(target.id)) continue;
      final migrated = <String, dynamic>{
        'userRef': userRef,
        'startLocation': old['startLocation'],
        'destination': old['destination'],
        'startedAt': old['startedAt'],
        'status': old['status'],
        'distance': old['distance'],
      };
      if (old['endedAt'] == null || old['endedAt'] is Timestamp) {
        migrated['endedAt'] = old['endedAt'];
      }
      await target.set(migrated);
    }
  }

  Future<void> addFavorite({
  required String placeName,
  required String address,
  required double latitude,
  required double longitude,
}) async {
  final user = _requireUser();

  final existingFavorites = await _favoritesCollection
      .where('userRef', isEqualTo: _userReference(user))
      .get();

  for (final document in existingFavorites.docs) {
    final data = document.data();
    final location = data['location'];

    if (location is GeoPoint &&
        location.latitude == latitude &&
        location.longitude == longitude) {
      await document.reference.delete();
      break;
    }
  }

  await _favoritesCollection.add({
    'userRef': _userReference(user),
    'placeName': placeName,
    'address': address,
    'location': GeoPoint(latitude, longitude),
    'createdAt': FieldValue.serverTimestamp(),
  });
}

  Stream<QuerySnapshot<Map<String, dynamic>>> getFavorites() {
    final user = _requireUser();
    unawaited(migrateLegacyData().catchError((Object _) {}));
    return _favoritesCollection
        .where('userRef', isEqualTo: _userReference(user))
        .orderBy('createdAt', descending: true)
        .snapshots();
  }

  Future<void> deleteFavorite(String favoriteId) async {
    final user = _requireUser();
    final favorite = await _favoritesCollection.doc(favoriteId).get();
    if (favorite.data()?['userRef'] != _userReference(user)) {
      throw StateError('The favorite does not belong to the signed-in user.');
    }
    await favorite.reference.delete();
  }
}
