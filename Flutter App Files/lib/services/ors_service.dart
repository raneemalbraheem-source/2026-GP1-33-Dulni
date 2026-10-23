import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:google_maps_flutter/google_maps_flutter.dart';

class ORSService {
  final String _apiKey = 'eyJvcmciOiI1YjNjZTM1OTc4NTExMTAwMDFjZjYyNDgiLCJpZCI6IjQyMTdlNjIwZjc3YzRmN2U5ZTc5YjJlNWZjMGExNDA4IiwiaCI6Im11cm11cjY0In0=';

  /// جلب مسار المشاة بين نقطة بداية ونقطة وصول
  Future<List<LatLng>> getPedestrianRoute(LatLng start, LatLng destination) async {
    // إضافة /geojson في نهاية الرابط للحصول على استجابة بصيغة GeoJSON مباشرة
    final String url = 'https://api.openrouteservice.org/v2/directions/foot-walking/geojson';

    try {
      final response = await http.post(
        Uri.parse(url),
        headers: {
          'Authorization': _apiKey,
          'Content-Type': 'application/json',
          'Accept': 'application/json, application/geo+json',
        },
        body: json.encode({
          'coordinates': [
            [start.longitude, start.latitude],
            [destination.longitude, destination.latitude]
          ]
        }),
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);

        if (data != null && data['features'] != null && (data['features'] as List).isNotEmpty) {
          final feature = data['features'][0];
          if (feature != null && feature['geometry'] != null && feature['geometry']['coordinates'] != null) {
            final List<dynamic> coordinates = feature['geometry']['coordinates'];

            return coordinates
                .map((coord) => LatLng(coord[1].toDouble(), coord[0].toDouble()))
                .toList();
          }
        }
        
        print('تحذير: استجابة السيرفر لا تحتوي على إحداثيات مسار صحيحة: ${response.body}');
        return [];
      } else {
        print('ORS Error Code: ${response.statusCode}');
        print('Response body: ${response.body}');
        return [];
      }
    } catch (e) {
      print('Error fetching pedestrian route: $e');
      return [];
    }
  }
}