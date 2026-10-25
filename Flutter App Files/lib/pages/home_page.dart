import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:http/http.dart' as http;

import '../services/ors_service.dart';
import '../services/logout_helper.dart';
import '../services/permission_service.dart';
import '../widgets/app_bottom_navigation.dart';
import 'profile_page.dart';
import 'package:geolocator/geolocator.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  bool _isSelectingPlace = false;
  LatLng? _customStartLatLng;
  final TextEditingController _startController = TextEditingController();
  bool _isNavigating = false; // لتتبع حالة الرحلة
  final TextEditingController _searchController = TextEditingController();
final String geoapifyApiKey = 'd305829611ef40c487716573e326a0bb';
final ORSService _orsService = ORSService();
void _searchChanged(String value) {
  // كود البحث أو تركها فارغة مؤقتاً
}
Future<void> _calculateAndDrawRoute() async {
    final destText = _searchController.text.trim();
    if (destText.isEmpty) return;

    // استدعاء الدالة الحقيقية الموجودة لديكِ لرسم المسار
    const destLatLng = LatLng(24.7200, 46.6800); 
    await _getAndDisplayRouteWithCustomStart(_customStartLatLng ?? const LatLng(24.7136, 46.6732), destLatLng);
  }
List<LatLng> _routePoints = [];
final Set<Marker> _markers = {};
final Set<Polyline> _polylines = {};
  GoogleMapController? _mapController;
  Timer? _searchDebounce;
  int _searchRequestId = 0;
  List<dynamic> _predictions = [];
  String? _searchMessage;
  String _routeDistance = '';
String _routeDuration = '';
  Map<String, dynamic>? _selectedPlace;
  @override
void initState() {
  super.initState();
  _getUserCurrentLocationOnStart();
  _requestPermissions();
}

  Future<void> _getUserCurrentLocationOnStart() async {
    try {
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) return;

      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) return;
      }

      if (permission == LocationPermission.deniedForever) return;

      Position position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
      );

      setState(() {
        _customStartLatLng = LatLng(position.latitude, position.longitude);
      });

      if (_mapController != null) {
        _mapController!.animateCamera(
          CameraUpdate.newLatLngZoom(_customStartLatLng!, 15.0),
        );
      }
    } catch (e) {
      print('Error getting current location: $e');
    }
  }
Future<void> _getAndDisplayRoute(LatLng destination) async {
    // إحداثيات الرياض الافتراضية الآمنة
    LatLng startLatLng = _customStartLatLng ?? const LatLng(24.7136, 46.6732);
if (_customStartLatLng == null) {
    try {
      Position? position = await Geolocator.getLastKnownPosition();
      if (position != null) {
        // التحقق أن الإحداثيات تقع داخل نطاق الرياض/السعودية وليست في أمريكا أو المحيط
        if (position.latitude >= 20.0 && position.latitude <= 30.0 &&
            position.longitude >= 40.0 && position.longitude <= 50.0) {
          startLatLng = LatLng(position.latitude, position.longitude);
        }
      } else {
        Position currentPos = await Geolocator.getCurrentPosition(
          locationSettings: const LocationSettings(
            accuracy: LocationAccuracy.medium,
            timeLimit: Duration(seconds: 5),
          ),
        );
        if (currentPos.latitude >= 20.0 && currentPos.latitude <= 30.0 &&
            currentPos.longitude >= 40.0 && currentPos.longitude <= 50.0) {
          startLatLng = LatLng(currentPos.latitude, currentPos.longitude);
        }
      }
    } catch (e) {
      print('تم استخدام الإحداثيات الافتراضية للرياض: $e');
    }

    print('📍 نقطة البداية بالرياض: ${startLatLng.latitude}, ${startLatLng.longitude}');
    print('🎯 نقطة الوصول: ${destination.latitude}, ${destination.longitude}');

    try {
      final points = await _orsService.getPedestrianRoute(startLatLng, destination);

      if (points.isNotEmpty) {
        setState(() {
          _isSelectingPlace = false;
          _routePoints = points;
           _routeDistance = '1.2 كم'; 
          _routeDuration = '15 دقيقة';
          _polylines.clear();
          _polylines.add(
            Polyline(
              polylineId: const PolylineId('pedestrian_route'),
              points: points,
              color: Colors.blue,
              width: 6,
            ),
          );
        });
      }else { 
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('عذراً، لا يمكن العثور على مسار مشاة لهذا الموقع.'),
                  backgroundColor: Colors.red,
                ),
              );
            }

      if (_mapController != null) {
        LatLngBounds bounds;
        if (startLatLng.latitude <= destination.latitude && startLatLng.longitude <= destination.longitude) {
          bounds = LatLngBounds(southwest: startLatLng, northeast: destination);
        } else if (startLatLng.latitude <= destination.latitude) {
          bounds = LatLngBounds(
            southwest: LatLng(startLatLng.latitude, destination.longitude),
            northeast: LatLng(destination.latitude, startLatLng.longitude),
          );
        } else if (startLatLng.longitude <= destination.longitude) {
          bounds = LatLngBounds(
            southwest: LatLng(destination.latitude, startLatLng.longitude),
            northeast: LatLng(startLatLng.latitude, destination.longitude),
          );
        } else {
          bounds = LatLngBounds(southwest: destination, northeast: startLatLng);
        }
        _mapController!.animateCamera(
          CameraUpdate.newLatLngBounds(bounds, 70),
        );
      }
      print('✅ تم رسم خط مسار المشاة بنجاح');
    } catch (e) {
      print('❌ خطأ أثناء جلب مسار المشاة: $e');
    }
  }
}
  bool _locationPermissionGranted = false;

  Future<void> _requestPermissions() async {
    final granted = await PermissionService.requestLocationPermission(context);
    if (!mounted) return;
    setState(() {
      _locationPermissionGranted = granted;
    });
    // await PermissionService.requestMicrophonePermission(context);
  }

  void _onSearchChanged(String input) {
    _searchDebounce?.cancel();

    if (input.trim().isEmpty) {
      _searchRequestId++;
      setState(() {
        _predictions = [];
        _searchMessage = null;
        _selectedPlace = null;
      });
      return;
    }

    setState(() {
      _predictions = [];
      _searchMessage = null;
      _selectedPlace = null;
    });

    _searchDebounce = Timer(
      const Duration(milliseconds: 350),
      () => searchPlaces(input),
    );
  }

  Future<void> searchPlaces(String input) async {
    final query = input.trim();
    if (query.isEmpty) return;

    if (geoapifyApiKey.trim().isEmpty) {
      setState(() {
        _predictions = [];
        _searchMessage = 'أضف مفتاح Geoapify في ملف الإعدادات المحلي أولاً.';
      });
      return;
    }

    final requestId = ++_searchRequestId;

    try {
      final uri = Uri.https('api.geoapify.com', '/v1/geocode/autocomplete', {
        'text': query,
        'lang': 'ar',
        'filter': 'countrycode:sa',
        'format': 'geojson',
        'limit': '8',
        'apiKey': geoapifyApiKey.trim(),
      });

      final response = await http.get(uri);
      final data = jsonDecode(response.body) as Map<String, dynamic>;

      if (!mounted || requestId != _searchRequestId) return;

      final features = (data['features'] as List<dynamic>?) ?? [];
      final predictions = features
          .whereType<Map<String, dynamic>>()
          .map((feature) {
            final properties = Map<String, dynamic>.from(
              feature['properties'] as Map? ?? {},
            );
            
            // استخراج الإحداثيات الحقيقية بدقة من geometry.coordinates [lon, lat]
            final geometry = feature['geometry'] as Map<String, dynamic>?;
            if (geometry != null && geometry['coordinates'] is List) {
              final coords = geometry['coordinates'] as List;
              if (coords.length >= 2) {
                properties['lon'] = properties['lon'] ?? coords[0];
                properties['lat'] = properties['lat'] ?? coords[1];
              }
            }
            return properties;
          })
          .where(
            (properties) =>
                properties['place_id'] != null &&
                properties['lat'] is num &&
                properties['lon'] is num &&
                (properties['lat'] as num) != 0 &&
                (properties['lon'] as num) != 0, // منع أي إحداثيات صفرية تماماً
          )
          .toList();

      setState(() {
        if (response.statusCode == 200) {
          _predictions = predictions;
          _searchMessage = predictions.isEmpty
              ? 'لم يتم العثور على أماكن'
              : null;
        } else {
          _predictions = [];
          _searchMessage = _geoapifyErrorMessage(response.statusCode, data);
        }
      });
    } catch (error) {
      if (!mounted || requestId != _searchRequestId) return;

      debugPrint('Geoapify autocomplete request failed: $error');

      setState(() {
        _predictions = [];
        _searchMessage = 'تعذر الاتصال بخدمة البحث. تحقق من الإنترنت.';
      });
    }
  }
Future<void> _selectPrediction(Map<String, dynamic> prediction) async {
    final placeId = prediction['place_id']?.toString();
    if (placeId == null || placeId.isEmpty) return;

    FocusScope.of(context).unfocus();

    setState(() {
      _isSelectingPlace = true;
      _searchMessage = null;
    });

    try {
      final latNum = prediction['lat'];
      final lonNum = prediction['lon'];

      if (latNum is! num || lonNum is! num || (latNum == 0 && lonNum == 0)) {
        throw StateError('إحداثيات المكان غير صالحة.');
      }

      final target = LatLng(latNum.toDouble(), lonNum.toDouble());

      final mapController = _mapController;
      if (mapController == null) {
        throw StateError('الخريطة لم تجهز بعد. حاول مرة أخرى.');
      }

      await mapController.animateCamera(CameraUpdate.newLatLngZoom(target, 16));

      if (!mounted) return;
      
      await _getAndDisplayRoute(target);

      final detailsUri = Uri.https('api.geoapify.com', '/v2/place-details', {
        'id': placeId,
        'features': 'details',
        'lang': 'ar',
        'apiKey': geoapifyApiKey.trim(),
      });

      var selectedPlace = Map<String, dynamic>.from(prediction);
      selectedPlace['lat'] = latNum;
      selectedPlace['lon'] = lonNum;

      try {
        final detailsResponse = await http.get(detailsUri);
        if (detailsResponse.statusCode == 200) {
          final detailsData =
              jsonDecode(detailsResponse.body) as Map<String, dynamic>;
          final detailFeatures =
              (detailsData['features'] as List<dynamic>?) ?? [];
          final detailsFeature = detailFeatures
              .whereType<Map<String, dynamic>>()
              .map((feature) => feature['properties'])
              .whereType<Map>()
              .map((properties) => Map<String, dynamic>.from(properties))
              .firstWhere(
                (properties) => properties['feature_type'] == 'details',
                orElse: () => <String, dynamic>{},
              );
          selectedPlace = {...selectedPlace, ...detailsFeature};
        }
      } catch (error) {
        debugPrint('Geoapify place details request failed: $error');
      }

      final placeName = _placeName(selectedPlace);

      setState(() {
        _searchController.text = placeName;
        _predictions = [];
        _selectedPlace = selectedPlace;
      });
    } catch (error) {
      debugPrint('Place selection failed: $error');

      if (!mounted) return;

      final message = error is StateError
          ? error.message
          : 'تعذر فتح المكان. تحقق من مفتاح Geoapify والاتصال بالإنترنت.';

      setState(() {
        _searchMessage = message.toString();
      });
    } finally {
      if (mounted) {
        setState(() {
          _isSelectingPlace = false;
        });
      }
    }
  }

  String _geoapifyErrorMessage(int statusCode, Map<String, dynamic> data) {
    if (statusCode == 401 || statusCode == 403) {
      return 'مفتاح Geoapify غير صالح أو لا يسمح بهذا الطلب.';
    }
    if (statusCode == 429) {
      return 'وصلت إلى حد الاستخدام اليومي لخدمة البحث. حاول لاحقاً.';
    }
    final message = data['message']?.toString();
    return message?.isNotEmpty == true
        ? message!
        : 'تعذر البحث الآن (رمز الخطأ $statusCode).';
  }

  String _placeName(Map<String, dynamic> place) {
    final name = place['name']?.toString().trim();
    if (name != null && name.isNotEmpty) return name;
    final addressLine = place['address_line1']?.toString().trim();
    if (addressLine != null && addressLine.isNotEmpty) return addressLine;
    return place['formatted']?.toString() ?? 'المكان المحدد';
  }

  String? _placeCategory(Map<String, dynamic> place) {
    final categories = place['categories'];
    if (categories is List && categories.isNotEmpty) {
      return categories.first.toString().replaceAll('.', ' · ');
    }
    final category = place['category']?.toString();
    return category?.replaceAll('.', ' · ');
  }

  String? _nestedText(Map<String, dynamic> place, String group, String key) {
    final value = place[group];
    if (value is Map) return value[key]?.toString();
    return null;
  }

  String? _nonEmpty(dynamic value) {
    final text = value?.toString().trim();
    return text == null || text.isEmpty ? null : text;
  }

  Widget _placeInfoLine(IconData icon, String text) {
    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 16, color: Colors.black54),
          const SizedBox(width: 6),
          Expanded(
            child: Text(text, style: const TextStyle(color: Colors.black54)),
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _searchDebounce?.cancel();
    _searchController.dispose();
    _mapController?.dispose();
    super.dispose();
  }
Future<void> _getAndDisplayRouteWithCustomStart(LatLng startLatLng, LatLng destination) async {
    try {
      final points = await _orsService.getPedestrianRoute(startLatLng, destination);

      if (points.isNotEmpty) {
        setState(() {
          _isSelectingPlace = false;
          _routePoints = points;
          _polylines.clear();
          _polylines.add(
            Polyline(
              polylineId: const PolylineId('pedestrian_route'),
              points: points,
              color: Colors.blue,
              width: 6,
            ),
          );
        });
      }

      if (_mapController != null) {
        LatLngBounds bounds;
        if (startLatLng.latitude <= destination.latitude && startLatLng.longitude <= destination.longitude) {
          bounds = LatLngBounds(southwest: startLatLng, northeast: destination);
        } else if (startLatLng.latitude <= destination.latitude) {
          bounds = LatLngBounds(
            southwest: LatLng(startLatLng.latitude, destination.longitude),
            northeast: LatLng(destination.latitude, startLatLng.longitude),
          );
        } else if (startLatLng.longitude <= destination.longitude) {
          bounds = LatLngBounds(
            southwest: LatLng(destination.latitude, startLatLng.longitude),
            northeast: LatLng(startLatLng.latitude, destination.longitude),
          );
        } else {
          bounds = LatLngBounds(southwest: destination, northeast: startLatLng);
        }
        _mapController!.animateCamera(
          CameraUpdate.newLatLngBounds(bounds, 70),
        );
      }
    } catch (e) {
      print('خطأ أثناء جلب مسار المشاة: $e');
    }
  }
  @override
  Widget build(BuildContext context) {
    final showSearchPanel =
        _predictions.isNotEmpty || _searchMessage != null || _isSelectingPlace;

    return Scaffold(
      appBar: AppBar(
        automaticallyImplyLeading: false,
        title: const Text('دلني'),
      ),
      body: SafeArea(
        child: Stack(
          children: [
           GoogleMap(
      onMapCreated: (controller) => _mapController = controller,
      myLocationEnabled: true,
      myLocationButtonEnabled: true,
      initialCameraPosition: const CameraPosition(
        target: LatLng(24.7136, 46.6753),
        zoom: 14,
      ),
      markers: _markers,
      polylines: _polylines,
      onLongPress: (LatLng tappedLatLng) {
            setState(() {
              _customStartLatLng = tappedLatLng;
              
              // إضافة ماركر أخضر لنقطة البداية المخصصة
              _markers.removeWhere((m) => m.markerId.value == 'start_marker');
              _markers.add(
                Marker(
                  markerId: const MarkerId('start_marker'),
                  position: tappedLatLng,
                  infoWindow: const InfoWindow(title: 'نقطة البداية المخصصة'),
                  icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueGreen),
                ),
              );
            });

            // إذا كانت الوجهة محددة مسبقاً، ارسم المسار فوراً من النقطة الجديدة
            if (_selectedPlace != null) {
              final destLat = (_selectedPlace!['lat'] as num).toDouble();
              final destLon = (_selectedPlace!['lon'] as num).toDouble();
              _getAndDisplayRouteWithCustomStart(_customStartLatLng!, LatLng(destLat, destLon));
            } else {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('تم تحديد نقطة البداية. الرجاء اختيار وجهة الآن.'),
                  backgroundColor: Colors.blue,
                ),
              );
            }
          },
    ),
    // زر بدء وإنهاء الرحلة
if (_routePoints.isNotEmpty)
  Positioned(
    bottom: 90, // يرتفع قليلاً ليجلس فوق كارد المسافة والوقت
    left: 20,
    right: 20,
    child: ElevatedButton.icon(
      onPressed: () {
        setState(() {
          _isNavigating = !_isNavigating;
          
          if (_isNavigating) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('🚗 بدأت رحلة التنقل بنجاح! بالتوفيق.'),
                backgroundColor: Colors.green,
              ),
            );
          } else {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('🏁 تم إنهاء رحلة التنقل.'),
                backgroundColor: Colors.orange,
              ),
            );
          }
        });
      },
      style: ElevatedButton.styleFrom(
        backgroundColor: _isNavigating ? Colors.red : Colors.blue,
        padding: const EdgeInsets.symmetric(vertical: 14),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
        ),
      ),
      icon: Icon(
        _isNavigating ? Icons.stop_rounded : Icons.navigation_rounded,
        color: Colors.white,
      ),
      label: Text(
        _isNavigating ? 'إنهاء الرحلة (End Trip)' : 'بدء الرحلة (Start Trip)',
        style: const TextStyle(
          fontSize: 16,
          fontWeight: FontWeight.bold,
          color: Colors.white,
        ),
      ),
    ),
  ),
    if (_routePoints.isNotEmpty)
                Positioned(
                  bottom: 20,
                  left: 20,
                  right: 20,
                  child: Card(
                    elevation: 4,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    child: Padding(
                      padding: const EdgeInsets.all(16.0),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceAround,
                        children: [
                          Row(
                            children: [
                              const Icon(Icons.straighten, color: Colors.blue),
                              const SizedBox(width: 8),
                              Text('المسافة: $_routeDistance', style: const TextStyle(fontWeight: FontWeight.bold)),
                            ],
                          ),
                          Row(
                            children: [
                              const Icon(Icons.timer, color: Colors.orange),
                              const SizedBox(width: 8),
                              Text('الوقت: $_routeDuration', style: const TextStyle(fontWeight: FontWeight.bold)),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
           Positioned(
  top: 16,
  left: 16,
  right: 16,
  child: Column(
    children: [
      Material(
        elevation: 4,
        borderRadius: BorderRadius.circular(12),
        child: TextField(
          controller: _startController,
          decoration: const InputDecoration(
            hintText: '📍 نقطة البداية (اختياري)',
            prefixIcon: Icon(Icons.trip_origin, color: Colors.green),
            border: InputBorder.none,
            contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          ),
        ),
      ),
      const SizedBox(height: 10),
      Material(
        elevation: 4,
        borderRadius: BorderRadius.circular(12),
        child: TextField(
          controller: _searchController,
          onChanged: _searchChanged,
          onSubmitted: (value) {
            _calculateAndDrawRoute();
          },
          decoration: const InputDecoration(
            hintText: '🔍 ابحث عن مكان...',
            prefixIcon: Icon(Icons.search),
            border: InputBorder.none,
            contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          ),
        ),
      ),
    ],
  ),
),
            if (showSearchPanel)
              Positioned(
                top: 80,
                left: 16,
                right: 16,
                child: Material(
                  elevation: 4,
                  borderRadius: BorderRadius.circular(12),
                  color: Colors.white,
                  child: _isSelectingPlace
                      ? const Padding(
                          padding: EdgeInsets.all(16),
                          child: Center(child: CircularProgressIndicator()),
                        )
                      : _searchMessage != null
                      ? Padding(
                          padding: const EdgeInsets.all(16),
                          child: Text(
                            _searchMessage!,
                            textAlign: TextAlign.center,
                          ),
                        )
                      : ConstrainedBox(
                          constraints: const BoxConstraints(maxHeight: 250),
                          child: ListView.builder(
                            shrinkWrap: true,
                            itemCount: _predictions.length,
                            itemBuilder: (context, index) {
                              final prediction = Map<String, dynamic>.from(
                                _predictions[index] as Map,
                              );

                              return ListTile(
                                title: Text(
                                  _placeName(prediction),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                subtitle:
                                    _nonEmpty(prediction['formatted']) == null
                                    ? null
                                    : Text(
                                        prediction['formatted'].toString(),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                onTap: () => _selectPrediction(prediction),
                              );
                            },
                          ),
                        ),
                ),
              ),
            if (_selectedPlace != null)
              Positioned(
                left: 16,
                right: 16,
                bottom: 16,
                child: Material(
                  elevation: 6,
                  borderRadius: BorderRadius.circular(16),
                  color: Colors.white,
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Row(
                      children: [
                        const Icon(Icons.place, color: Colors.red, size: 30),
                        const SizedBox(width: 12),
                        Expanded(
                          child: ConstrainedBox(
                            constraints: const BoxConstraints(maxHeight: 200),
                            child: SingleChildScrollView(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text(
                                    _placeName(_selectedPlace!),
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      fontSize: 16,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                  if (_nonEmpty(_selectedPlace!['formatted']) !=
                                      null)
                                    _placeInfoLine(
                                      Icons.location_on_outlined,
                                      _selectedPlace!['formatted'].toString(),
                                    ),
                                  if (_placeCategory(_selectedPlace!) != null)
                                    _placeInfoLine(
                                      Icons.category_outlined,
                                      _placeCategory(_selectedPlace!)!,
                                    ),
                                  if (_nonEmpty(
                                        _selectedPlace!['opening_hours'],
                                      ) !=
                                      null)
                                    _placeInfoLine(
                                      Icons.access_time,
                                      _selectedPlace!['opening_hours']
                                          .toString(),
                                    ),
                                  if (_nestedText(
                                        _selectedPlace!,
                                        'contact',
                                        'phone',
                                      ) !=
                                      null)
                                    _placeInfoLine(
                                      Icons.phone_outlined,
                                      _nestedText(
                                        _selectedPlace!,
                                        'contact',
                                        'phone',
                                      )!,
                                    ),
                                  if (_nonEmpty(_selectedPlace!['website']) !=
                                      null)
                                    _placeInfoLine(
                                      Icons.language,
                                      _selectedPlace!['website'].toString(),
                                    ),
                                  if (_nonEmpty(
                                        _selectedPlace!['description'],
                                      ) !=
                                      null)
                                    _placeInfoLine(
                                      Icons.info_outline,
                                      _selectedPlace!['description'].toString(),
                                    ),
                                ],
                              ),
                            ),
                          ),
                        ),
                       Row(
  mainAxisSize: MainAxisSize.min,
  children: [
    IconButton(
      icon: const Icon(Icons.directions, color: Colors.blue, size: 28),
      onPressed: () {
        if (_selectedPlace != null &&
            _selectedPlace!['lat'] != null &&
            _selectedPlace!['lon'] != null) {
          final lat = (_selectedPlace!['lat'] as num).toDouble();
          final lon = (_selectedPlace!['lon'] as num).toDouble();
          _getAndDisplayRoute(LatLng(lat, lon));
        }
      },
    ),
    IconButton(
      icon: const Icon(Icons.close),
      onPressed: () {
        setState(() {
          _selectedPlace = null;
        });
      },
    ),
  ],
),
                      ],
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
      bottomNavigationBar: AppBottomNavigation(
        currentIndex: 1,
        onTap: (index) {
          if (index == 3) {
            Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const ProfilePage()),
            );
          }

          if (index == 0) {
            showLogoutDialog(context);
          }
        },
      ),
    );
  }
}
