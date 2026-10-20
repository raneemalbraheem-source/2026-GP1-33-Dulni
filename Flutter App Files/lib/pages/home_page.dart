import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:http/http.dart' as http;

import '../services/geoapify_config.dart';
import '../services/logout_helper.dart';
import '../services/permission_service.dart';
import '../widgets/app_bottom_navigation.dart';
import 'profile_page.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  final TextEditingController _searchController = TextEditingController();

  GoogleMapController? _mapController;
  Timer? _searchDebounce;
  int _searchRequestId = 0;
  List<dynamic> _predictions = [];
  String? _searchMessage;
  Map<String, dynamic>? _selectedPlace;
  bool _isSelectingPlace = false;
  bool _locationPermissionGranted = false;

  @override
  void initState() {
    super.initState();
    _requestPermissions();
  }

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
            return properties;
          })
          .where(
            (properties) =>
                properties['place_id'] != null &&
                properties['lat'] is num &&
                properties['lon'] is num,
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
      final latitude = prediction['lat'] as num;
      final longitude = prediction['lon'] as num;

      final target = LatLng(latitude.toDouble(), longitude.toDouble());

      final mapController = _mapController;
      if (mapController == null) {
        throw StateError('الخريطة لم تجهز بعد. حاول مرة أخرى.');
      }

      await mapController.animateCamera(CameraUpdate.newLatLngZoom(target, 16));

      if (!mounted) return;

      final detailsUri = Uri.https('api.geoapify.com', '/v2/place-details', {
        'id': placeId,
        'features': 'details',
        'lang': 'ar',
        'apiKey': geoapifyApiKey.trim(),
      });

      var selectedPlace = Map<String, dynamic>.from(prediction);
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
        } else {
          debugPrint(
            'Geoapify place details HTTP ${detailsResponse.statusCode}',
          );
        }
      } catch (error) {
        // The autocomplete result still has the name, address and coordinates.
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
              myLocationEnabled: _locationPermissionGranted,
              myLocationButtonEnabled: _locationPermissionGranted,
              initialCameraPosition: const CameraPosition(
                target: LatLng(24.7136, 46.6753),
                zoom: 14,
              ),
            ),
            Positioned(
              top: 16,
              left: 16,
              right: 16,
              child: Material(
                elevation: 4,
                borderRadius: BorderRadius.circular(12),
                child: TextField(
                  controller: _searchController,
                  onChanged: _onSearchChanged,
                  decoration: const InputDecoration(
                    hintText: 'ابحث عن مكان...',
                    prefixIcon: Icon(Icons.search),
                    border: InputBorder.none,
                    contentPadding: EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 14,
                    ),
                  ),
                ),
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
