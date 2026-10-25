import 'dart:async';
import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:http/http.dart' as http;
import 'package:speech_to_text/speech_to_text.dart' as stt;

import '../services/logout_helper.dart';
import '../services/ors_service.dart';
import '../services/permission_service.dart';
import '../widgets/app_bottom_navigation.dart';
import 'profile_page.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  // Keep the API key in your existing local configuration if you already have one.
  // Restrict client-side keys to the APIs and applications that need them.
  final String _geoapifyApiKey = 'd305829611ef40c487716573e326a0bb';
  final ORSService _orsService = ORSService();
  final stt.SpeechToText _speech = stt.SpeechToText();

  final TextEditingController _startController = TextEditingController();
  final TextEditingController _destinationController = TextEditingController();

  GoogleMapController? _mapController;
  Timer? _searchDebounce;
  StreamSubscription<Position>? _positionSubscription;

  bool _locationPermissionGranted = false;
  bool _isSelectingPlace = false;
  bool _isCalculatingRoute = false;
  bool _isNavigating = false;
  bool _isFinishingTrip = false;
  bool _isListening = false;
  bool _searchingForStart = false;

  int _searchRequestId = 0;
  List<Map<String, dynamic>> _predictions = [];
  String? _searchMessage;

  LatLng? _currentLocation;
  LatLng? _selectedStartLocation;
  LatLng? _selectedDestination;
  LatLng? _routeStartLocation;

  List<LatLng> _routePoints = [];
  final Set<Marker> _markers = {};
  final Set<Polyline> _polylines = {};

  double _routeDistanceMeters = 0;
  String _routeDistanceLabel = '';
  String _routeDurationLabel = '';
  String? _activeSessionId;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _requestPermissionsAndLoadLocation();
    });
  }

  Future<void> _requestPermissionsAndLoadLocation() async {
    final granted = await PermissionService.requestLocationPermission(context);
    if (!mounted) return;

    setState(() => _locationPermissionGranted = granted);
    if (!granted) {
      _showMessage('يمكنك تحديد نقطة بداية يدويًا، لكن استخدام موقعك الحالي يتطلب إذن الموقع.');
      return;
    }

    await _loadCurrentLocation(moveCamera: true);
  }

  Future<void> _loadCurrentLocation({required bool moveCamera}) async {
    try {
      if (!await Geolocator.isLocationServiceEnabled()) {
        if (mounted) _showMessage('خدمة الموقع متوقفة. فعّلها أو اختر نقطة بداية على الخريطة.');
        return;
      }

      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        if (mounted) _showMessage('إذن الموقع غير متاح. يمكنك تحديد نقطة البداية يدويًا.');
        return;
      }

      final position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: Duration(seconds: 12),
        ),
      );
      final current = LatLng(position.latitude, position.longitude);
      if (!mounted) return;
      setState(() => _currentLocation = current);

      if (moveCamera && _mapController != null) {
        await _mapController!.animateCamera(
          CameraUpdate.newLatLngZoom(current, 16),
        );
      }
    } catch (error) {
      debugPrint('Unable to retrieve current location: $error');
      if (mounted) _showMessage('تعذر تحديد موقعك الحالي. اختر نقطة البداية من الخريطة أو تحقق من إذن الموقع.');
    }
  }

  void _showMessage(String message, {bool isError = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(message),
          backgroundColor: isError ? Colors.red.shade700 : null,
        ),
      );
  }

  void _clearRouteVisuals() {
    _routePoints = [];
    _polylines.clear();
    _routeDistanceMeters = 0;
    _routeDistanceLabel = '';
    _routeDurationLabel = '';
    _routeStartLocation = null;
  }

  void _onStartSearchChanged(String value) {
    if (_isNavigating) return;
    _searchingForStart = true;
    _onSearchInputChanged(value, isStart: true);
  }

  void _onDestinationSearchChanged(String value) {
    if (_isNavigating) return;
    _searchingForStart = false;
    _onSearchInputChanged(value, isStart: false);
  }

  void _onSearchInputChanged(String input, {required bool isStart}) {
    _searchDebounce?.cancel();
    final requestId = ++_searchRequestId;

    setState(() {
      _predictions = [];
      _searchMessage = null;
      _clearRouteVisuals();
      if (isStart) {
        _selectedStartLocation = null;
        _markers.removeWhere((marker) => marker.markerId.value == 'start_marker');
      } else {
        _selectedDestination = null;
        _markers.removeWhere((marker) => marker.markerId.value == 'destination_marker');
      }
    });

    final query = input.trim();
    if (query.isEmpty) return;

    if (_geoapifyApiKey.trim().isEmpty) {
      setState(() => _searchMessage = 'يلزم إعداد مفتاح خدمة البحث عن الأماكن.');
      return;
    }

    _searchDebounce = Timer(
      const Duration(milliseconds: 350),
      () => _searchPlaces(query, isStart: isStart, requestId: requestId),
    );
  }

  Future<void> _searchPlaces(
    String query, {
    required bool isStart,
    required int requestId,
  }) async {
    try {
      final uri = Uri.https('api.geoapify.com', '/v1/geocode/autocomplete', {
        'text': query,
        'lang': 'ar',
        'filter': 'countrycode:sa',
        'format': 'geojson',
        'limit': '8',
        'apiKey': _geoapifyApiKey.trim(),
      });

      final response = await http.get(uri);
      final decoded = jsonDecode(response.body);
      final data = decoded is Map<String, dynamic> ? decoded : <String, dynamic>{};
      if (!mounted || requestId != _searchRequestId) return;

      if (response.statusCode != 200) {
        setState(() {
          _predictions = [];
          _searchMessage = _geoapifyErrorMessage(response.statusCode, data);
        });
        return;
      }

      final features = data['features'] as List<dynamic>? ?? [];
      final results = <Map<String, dynamic>>[];
      for (final item in features) {
        if (item is! Map) continue;
        final feature = Map<String, dynamic>.from(item);
        final propertiesRaw = feature['properties'];
        if (propertiesRaw is! Map) continue;
        final properties = Map<String, dynamic>.from(propertiesRaw);
        final geometryRaw = feature['geometry'];
        if (geometryRaw is Map && geometryRaw['coordinates'] is List) {
          final coordinates = geometryRaw['coordinates'] as List;
          if (coordinates.length >= 2) {
            properties['lon'] ??= coordinates[0];
            properties['lat'] ??= coordinates[1];
          }
        }
        if (properties['lat'] is num &&
            properties['lon'] is num &&
            properties['place_id'] != null) {
          results.add(properties);
        }
      }

      setState(() {
        _predictions = results;
        _searchMessage = results.isEmpty ? 'لم يتم العثور على أماكن مطابقة. جرّب اسمًا آخر.' : null;
      });
    } catch (error) {
      if (!mounted || requestId != _searchRequestId) return;
      debugPrint('Geoapify place search failed: $error');
      setState(() {
        _predictions = [];
        _searchMessage = 'تعذر الاتصال بخدمة البحث. تحقق من الإنترنت وحاول مجددًا.';
      });
    }
  }

  Future<void> _selectPrediction(Map<String, dynamic> prediction) async {
    _searchDebounce?.cancel();
    _searchRequestId++;
    final latitude = prediction['lat'];
    final longitude = prediction['lon'];
    if (latitude is! num || longitude is! num) {
      _showMessage('إحداثيات المكان غير صالحة. اختر مكانًا آخر.', isError: true);
      return;
    }

    final target = LatLng(latitude.toDouble(), longitude.toDouble());
    final name = _placeName(prediction);
    FocusScope.of(context).unfocus();

    setState(() {
      _isSelectingPlace = true;
      _predictions = [];
      _searchMessage = null;
      _clearRouteVisuals();
      if (_searchingForStart) {
        _selectedStartLocation = target;
        _startController.text = name;
        _markers.removeWhere((marker) => marker.markerId.value == 'start_marker');
        _markers.add(
          Marker(
            markerId: const MarkerId('start_marker'),
            position: target,
            infoWindow: InfoWindow(title: 'نقطة البداية: $name'),
            icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueGreen),
          ),
        );
      } else {
        _selectedDestination = target;
        _destinationController.text = name;
        _markers.removeWhere((marker) => marker.markerId.value == 'destination_marker');
        _markers.add(
          Marker(
            markerId: const MarkerId('destination_marker'),
            position: target,
            infoWindow: InfoWindow(title: 'الوجهة: $name'),
            icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueRed),
          ),
        );
      }
    });

    try {
      final controller = _mapController;
      if (controller != null) {
        await controller.animateCamera(CameraUpdate.newLatLngZoom(target, 16));
      }
    } finally {
      if (mounted) setState(() => _isSelectingPlace = false);
    }
  }

  void _chooseStartOnMap(LatLng target) {
    if (_isNavigating) return;
    _searchDebounce?.cancel();
    _searchRequestId++;
    setState(() {
      _searchingForStart = true;
      _selectedStartLocation = target;
      _startController.text = 'نقطة بداية محددة على الخريطة';
      _predictions = [];
      _searchMessage = null;
      _clearRouteVisuals();
      _markers.removeWhere((marker) => marker.markerId.value == 'start_marker');
      _markers.add(
        Marker(
          markerId: const MarkerId('start_marker'),
          position: target,
          infoWindow: const InfoWindow(title: 'نقطة البداية'),
          icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueGreen),
        ),
      );
    });
    _showMessage('تم تحديد نقطة البداية. اختَر الوجهة ثم احسب المسار.');
  }

  Future<void> _useCurrentLocationAsStart() async {
    _searchDebounce?.cancel();
    _searchRequestId++;
    setState(() {
      _selectedStartLocation = null;
      _startController.clear();
      _markers.removeWhere((marker) => marker.markerId.value == 'start_marker');
      _predictions = [];
      _searchMessage = null;
      _clearRouteVisuals();
    });
    if (_currentLocation == null) {
      await _loadCurrentLocation(moveCamera: true);
    } else {
      await _mapController?.animateCamera(
        CameraUpdate.newLatLngZoom(_currentLocation!, 16),
      );
    }
    if (_currentLocation == null) {
      _showMessage('تعذر تحديد موقعك الحالي. تحقق من إذن الموقع وخدمة الموقع.', isError: true);
      return;
    }
    _showMessage('سيُستخدم موقعك الحالي كنقطة بداية.');
  }

  Future<void> _calculateAndDrawRoute() async {
    if (_isNavigating) {
      _showMessage('أنهِ الرحلة الحالية قبل التخطيط لرحلة جديدة.');
      return;
    }

    final destination = _selectedDestination;
    if (destination == null) {
      _showMessage('ابحث عن الوجهة واخترها من نتائج البحث.', isError: true);
      return;
    }

    final startText = _startController.text.trim();
    if (startText.isNotEmpty && _selectedStartLocation == null) {
      _showMessage('اختر نقطة البداية من نتائج البحث أو اترك الحقل فارغًا لاستخدام موقعك الحالي.', isError: true);
      return;
    }

    var start = _selectedStartLocation;
    if (start == null) {
      start = _currentLocation;
      if (start == null && _locationPermissionGranted) {
        await _loadCurrentLocation(moveCamera: false);
        start = _currentLocation;
      }
    }

    if (start == null) {
      _showMessage('تعذر تحديد نقطة البداية. فعّل إذن الموقع أو اختر نقطة بداية على الخريطة.', isError: true);
      return;
    }
    final LatLng startLocation = start;

    setState(() {
      _isCalculatingRoute = true;
      _searchMessage = null;
    });

    try {
      final points = await _orsService.getPedestrianRoute(startLocation, destination);
      if (!mounted) return;
      if (points.isEmpty) {
        setState(() {
          _clearRouteVisuals();
          _searchMessage = 'لا يتوفر مسار مشاة بين هاتين النقطتين. جرّب نقطة بداية أو وجهة أخرى.';
        });
        _showMessage('لا يتوفر مسار مشاة لهذا الاختيار.', isError: true);
        return;
      }

      final distanceMeters = _calculatePolylineDistance(points);
      // ORSService currently exposes route coordinates only. Estimate walking time
      // from the returned route length at 1.2 m/s until the service returns metadata.
      final estimatedMinutes = (distanceMeters / 1.2 / 60).ceil();

      setState(() {
        _routePoints = points;
        _routeStartLocation = startLocation;
        _routeDistanceMeters = distanceMeters;
        _routeDistanceLabel = _formatDistance(distanceMeters);
        _routeDurationLabel = _formatDuration(estimatedMinutes);
        _polylines
          ..clear()
          ..add(
            Polyline(
              polylineId: const PolylineId('pedestrian_route'),
              points: points,
              color: const Color(0xFF155EEF),
              width: 6,
            ),
          );
        _markers.removeWhere((marker) =>
            marker.markerId.value == 'start_marker' ||
            marker.markerId.value == 'destination_marker');
        _markers.add(
          Marker(
            markerId: const MarkerId('start_marker'),
            position: startLocation,
            infoWindow: const InfoWindow(title: 'نقطة البداية'),
            icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueGreen),
          ),
        );
        _markers.add(
          Marker(
            markerId: const MarkerId('destination_marker'),
            position: destination,
            infoWindow: const InfoWindow(title: 'الوجهة'),
            icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueRed),
          ),
        );
      });
      await _fitRouteToCamera(points);
    } catch (error) {
      debugPrint('ORS route request failed: $error');
      if (mounted) {
        _showMessage('تعذر حساب المسار. تحقق من اتصال الإنترنت وإعدادات ORS.', isError: true);
      }
    } finally {
      if (mounted) setState(() => _isCalculatingRoute = false);
    }
  }

  double _calculatePolylineDistance(List<LatLng> points) {
    var totalMeters = 0.0;
    for (var i = 1; i < points.length; i++) {
      totalMeters += Geolocator.distanceBetween(
        points[i - 1].latitude,
        points[i - 1].longitude,
        points[i].latitude,
        points[i].longitude,
      );
    }
    return totalMeters;
  }

  String _formatDistance(double meters) {
    if (meters < 1000) return '${meters.round()} م';
    return '${(meters / 1000).toStringAsFixed(2)} كم';
  }

  String _formatDuration(int minutes) {
    if (minutes < 1) return 'أقل من دقيقة';
    if (minutes < 60) return '$minutes دقيقة تقريبًا';
    final hours = minutes ~/ 60;
    final remainingMinutes = minutes % 60;
    if (remainingMinutes == 0) return '$hours ساعة تقريبًا';
    return '$hours ساعة و$remainingMinutes دقيقة تقريبًا';
  }

  Future<void> _fitRouteToCamera(List<LatLng> points) async {
    final controller = _mapController;
    if (controller == null || points.isEmpty) return;

    var minLat = points.first.latitude;
    var maxLat = points.first.latitude;
    var minLng = points.first.longitude;
    var maxLng = points.first.longitude;
    for (final point in points.skip(1)) {
      if (point.latitude < minLat) minLat = point.latitude;
      if (point.latitude > maxLat) maxLat = point.latitude;
      if (point.longitude < minLng) minLng = point.longitude;
      if (point.longitude > maxLng) maxLng = point.longitude;
    }

    if ((maxLat - minLat).abs() < 0.0001 && (maxLng - minLng).abs() < 0.0001) {
      await controller.animateCamera(
        CameraUpdate.newLatLngZoom(points.first, 16),
      );
      return;
    }

    await controller.animateCamera(
      CameraUpdate.newLatLngBounds(
        LatLngBounds(
          southwest: LatLng(minLat, minLng),
          northeast: LatLng(maxLat, maxLng),
        ),
        72,
      ),
    );
  }

  Future<void> _startTrip() async {
    if (_isNavigating || _routePoints.isEmpty || _routeStartLocation == null || _selectedDestination == null) {
      _showMessage('احسب المسار أولًا قبل بدء الرحلة.', isError: true);
      return;
    }
    if (!_locationPermissionGranted || !await Geolocator.isLocationServiceEnabled()) {
      _showMessage('يجب تفعيل خدمة الموقع والسماح بالوصول إلى الموقع لبدء التنقل.', isError: true);
      return;
    }

    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      _showMessage('انتهت جلسة تسجيل الدخول. سجّل الدخول مجددًا.', isError: true);
      return;
    }

    try {
      final session = FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .collection('navigationSessions')
          .doc();

      await session.set({
        'startLocation': GeoPoint(
          _routeStartLocation!.latitude,
          _routeStartLocation!.longitude,
        ),
        'destination': GeoPoint(
          _selectedDestination!.latitude,
          _selectedDestination!.longitude,
        ),
        'startedAt': FieldValue.serverTimestamp(),
        'endedAt': null,
        'status': 'active',
        'distance': _routeDistanceMeters,
      });

      if (!mounted) return;
      setState(() {
        _activeSessionId = session.id;
        _isNavigating = true;
        _isFinishingTrip = false;
      });
      _startLocationTracking();
      _showMessage('بدأت الرحلة. انتبه للتوجيهات واتبع المسار المعروض.');
    } catch (error) {
      debugPrint('Failed to create navigation session: $error');
      if (mounted) {
        _showMessage('تعذر حفظ الرحلة. تحقق من اتصال الإنترنت وصلاحيات قاعدة البيانات.', isError: true);
      }
    }
  }

  void _startLocationTracking() {
    _positionSubscription?.cancel();
    _positionSubscription = Geolocator.getPositionStream(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: 5,
      ),
    ).listen(
      _handlePositionUpdate,
      onError: (Object error) {
        debugPrint('Navigation location stream failed: $error');
        if (mounted && _isNavigating) {
          _showMessage('توقف تحديث الموقع؛ قد تتأثر متابعة الرحلة. تحقق من إذن الموقع.', isError: true);
        }
      },
    );
  }

  void _handlePositionUpdate(Position position) {
    if (!mounted) return;
    final current = LatLng(position.latitude, position.longitude);
    setState(() => _currentLocation = current);

    if (_isNavigating && !_isFinishingTrip && _selectedDestination != null) {
      final distanceToDestination = Geolocator.distanceBetween(
        current.latitude,
        current.longitude,
        _selectedDestination!.latitude,
        _selectedDestination!.longitude,
      );
      if (distanceToDestination <= 25) {
        unawaited(_finishTrip(reachedDestination: true));
      }
    }
  }

  Future<void> _finishTrip({bool reachedDestination = false, bool cancelled = false}) async {
    if (!_isNavigating || _isFinishingTrip) return;
    setState(() => _isFinishingTrip = true);

    try {
      final uid = FirebaseAuth.instance.currentUser?.uid;
      final sessionId = _activeSessionId;
      if (uid == null || sessionId == null) {
        throw StateError('Active navigation session was not found.');
      }

      await FirebaseFirestore.instance
          .collection('users')
          .doc(uid)
          .collection('navigationSessions')
          .doc(sessionId)
          .update({
        'endedAt': FieldValue.serverTimestamp(),
        'status': cancelled ? 'cancelled' : 'completed',
      });

      await _positionSubscription?.cancel();
      _positionSubscription = null;
      if (!mounted) return;
      setState(() {
        _isNavigating = false;
        _isFinishingTrip = false;
        _activeSessionId = null;
      });

      if (reachedDestination) {
        _showMessage('وصلت إلى الوجهة المحددة. اكتملت الرحلة.');
      } else if (cancelled) {
        _showMessage('تم إلغاء الرحلة.');
      } else {
        _showMessage('تم إنهاء الرحلة وحفظ وقت الانتهاء.');
      }
    } catch (error) {
      debugPrint('Failed to finish navigation session: $error');
      if (mounted) {
        setState(() => _isFinishingTrip = false);
        _showMessage('تعذر حفظ انتهاء الرحلة. حاول مجددًا.', isError: true);
      }
    }
  }

  Future<void> _startVoiceDestinationSearch() async {
    if (_isNavigating || _isCalculatingRoute) return;
    try {
      final available = await _speech.initialize(
        onStatus: (status) {
          if (!mounted) return;
          if (status == 'notListening' || status == 'done') {
            setState(() => _isListening = false);
          }
        },
        onError: (error) {
          debugPrint('Speech recognition error: $error');
          if (mounted) {
            setState(() => _isListening = false);
            _showMessage('تعذر التعرّف على الصوت. يمكنك كتابة اسم الوجهة.', isError: true);
          }
        },
      );
      if (!available) {
        _showMessage('التعرّف الصوتي غير متاح على هذا الجهاز. اكتب اسم الوجهة بدلًا من ذلك.', isError: true);
        return;
      }

      setState(() {
        _isListening = true;
        _searchingForStart = false;
      });
      await _speech.listen(
        localeId: 'ar_SA',
        onResult: (result) {
          if (!mounted) return;
          final recognizedText = result.recognizedWords.trim();
          if (recognizedText.isEmpty) return;
          _destinationController.value = TextEditingValue(
            text: recognizedText,
            selection: TextSelection.collapsed(offset: recognizedText.length),
          );
          _onDestinationSearchChanged(recognizedText);
          if (result.finalResult) setState(() => _isListening = false);
        },
      );
    } catch (error) {
      debugPrint('Unable to start speech recognition: $error');
      if (mounted) {
        setState(() => _isListening = false);
        _showMessage('تعذر تشغيل البحث الصوتي. يمكنك كتابة اسم الوجهة.', isError: true);
      }
    }
  }

  String _geoapifyErrorMessage(int statusCode, Map<String, dynamic> data) {
    if (statusCode == 401 || statusCode == 403) {
      return 'مفتاح خدمة البحث غير صالح أو لا يسمح بهذا الطلب.';
    }
    if (statusCode == 429) {
      return 'وصلت خدمة البحث إلى حد الاستخدام. حاول لاحقًا.';
    }
    final message = data['message']?.toString();
    return message != null && message.isNotEmpty
        ? message
        : 'تعذر البحث الآن (رمز الخطأ $statusCode).';
  }

  String _placeName(Map<String, dynamic> place) {
    final name = place['name']?.toString().trim();
    if (name != null && name.isNotEmpty) return name;
    final address = place['address_line1']?.toString().trim();
    if (address != null && address.isNotEmpty) return address;
    final formatted = place['formatted']?.toString().trim();
    if (formatted != null && formatted.isNotEmpty) return formatted;
    return 'المكان المحدد';
  }

  Future<void> _cancelTripWithConfirmation() async {
    final shouldCancel = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('إلغاء الرحلة؟'),
        content: const Text('سيتم تسجيل هذه الرحلة كملغاة.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('متابعة الرحلة'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('إلغاء الرحلة'),
          ),
        ],
      ),
    );
    if (shouldCancel == true) await _finishTrip(cancelled: true);
  }

  @override
  void dispose() {
    _searchDebounce?.cancel();
    _positionSubscription?.cancel();
    _speech.stop();
    _startController.dispose();
    _destinationController.dispose();
    _mapController?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final showSearchPanel = _predictions.isNotEmpty || _searchMessage != null || _isSelectingPlace;

    return Scaffold(
      appBar: AppBar(
        automaticallyImplyLeading: false,
        title: const Text('دُلّني'),
      ),
      body: SafeArea(
        child: Stack(
          children: [
            GoogleMap(
              onMapCreated: (controller) {
                _mapController = controller;
                final current = _currentLocation;
                if (current != null) {
                  controller.animateCamera(CameraUpdate.newLatLngZoom(current, 16));
                }
              },
              myLocationEnabled: _locationPermissionGranted,
              myLocationButtonEnabled: _locationPermissionGranted,
              initialCameraPosition: const CameraPosition(
                target: LatLng(24.7136, 46.6753),
                zoom: 14,
              ),
              markers: _markers,
              polylines: _polylines,
              onLongPress: _chooseStartOnMap,
              compassEnabled: true,
              mapToolbarEnabled: false,
            ),
            Positioned(
              top: 12,
              left: 12,
              right: 12,
              child: Column(
                children: [
                  Material(
                    elevation: 4,
                    borderRadius: BorderRadius.circular(12),
                    color: Theme.of(context).colorScheme.surface,
                    child: TextField(
                      controller: _startController,
                      enabled: !_isNavigating,
                      onTap: () {
                        if (!_searchingForStart) {
                          _searchDebounce?.cancel();
                          setState(() {
                            _searchingForStart = true;
                            _predictions = [];
                            _searchMessage = null;
                          });
                        }
                      },
                      onChanged: _onStartSearchChanged,
                      textInputAction: TextInputAction.search,
                      decoration: InputDecoration(
                        hintText: 'نقطة البداية (اتركها فارغة لموقعك الحالي)',
                        prefixIcon: const Icon(Icons.trip_origin, color: Colors.green),
                        suffixIcon: IconButton(
                          tooltip: 'استخدام موقعي الحالي',
                          onPressed: _isNavigating ? null : _useCurrentLocationAsStart,
                          icon: const Icon(Icons.my_location),
                        ),
                        border: InputBorder.none,
                        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Material(
                    elevation: 4,
                    borderRadius: BorderRadius.circular(12),
                    color: Theme.of(context).colorScheme.surface,
                    child: TextField(
                      controller: _destinationController,
                      enabled: !_isNavigating,
                      onTap: () {
                        if (_searchingForStart) {
                          _searchDebounce?.cancel();
                          setState(() {
                            _searchingForStart = false;
                            _predictions = [];
                            _searchMessage = null;
                          });
                        }
                      },
                      onChanged: _onDestinationSearchChanged,
                      onSubmitted: (_) => _calculateAndDrawRoute(),
                      textInputAction: TextInputAction.search,
                      decoration: InputDecoration(
                        hintText: 'ابحث عن الوجهة أو استخدم الصوت',
                        prefixIcon: const Icon(Icons.search),
                        suffixIcon: IconButton(
                          tooltip: _isListening ? 'إيقاف الاستماع' : 'البحث الصوتي عن الوجهة',
                          onPressed: _isListening
                              ? () async {
                                  await _speech.stop();
                                  if (mounted) setState(() => _isListening = false);
                                }
                              : _startVoiceDestinationSearch,
                          icon: Icon(_isListening ? Icons.mic : Icons.mic_none),
                          color: _isListening ? Colors.red : null,
                        ),
                        border: InputBorder.none,
                        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            if (showSearchPanel)
              Positioned(
                top: 140,
                left: 12,
                right: 12,
                child: Material(
                  elevation: 6,
                  borderRadius: BorderRadius.circular(12),
                  color: Theme.of(context).colorScheme.surface,
                  child: _isSelectingPlace
                      ? const Padding(
                          padding: EdgeInsets.all(16),
                          child: Center(child: CircularProgressIndicator()),
                        )
                      : _searchMessage != null
                          ? Padding(
                              padding: const EdgeInsets.all(16),
                              child: Text(_searchMessage!, textAlign: TextAlign.center),
                            )
                          : ConstrainedBox(
                              constraints: const BoxConstraints(maxHeight: 240),
                              child: ListView.separated(
                                padding: EdgeInsets.zero,
                                shrinkWrap: true,
                                itemCount: _predictions.length,
                                separatorBuilder: (context, index) => const Divider(height: 1),
                                itemBuilder: (context, index) {
                                  final place = _predictions[index];
                                  final formatted = place['formatted']?.toString();
                                  return ListTile(
                                    leading: Icon(
                                      _searchingForStart ? Icons.trip_origin : Icons.place,
                                      color: _searchingForStart ? Colors.green : Colors.red,
                                    ),
                                    title: Text(
                                      _placeName(place),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                    subtitle: formatted == null || formatted.isEmpty
                                        ? null
                                        : Text(
                                            formatted,
                                            maxLines: 2,
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                    onTap: () => _selectPrediction(place),
                                  );
                                },
                              ),
                            ),
                ),
              ),
            if (!_isNavigating && _selectedDestination != null && _routePoints.isEmpty)
              Positioned(
                left: 12,
                right: 12,
                bottom: _routePoints.isEmpty ? 20 : 108,
                child: FilledButton.icon(
                  onPressed: _isCalculatingRoute ? null : _calculateAndDrawRoute,
                  icon: _isCalculatingRoute
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.alt_route),
                  label: Text(_isCalculatingRoute ? 'جارٍ حساب المسار...' : 'احسب مسار المشاة'),
                ),
              ),
            if (_routePoints.isNotEmpty)
              Positioned(
                left: 12,
                right: 12,
                bottom: 12,
                child: Card(
                  elevation: 6,
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Row(
                          children: [
                            const Icon(Icons.straighten, color: Color(0xFF155EEF)),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                'المسافة: $_routeDistanceLabel',
                                style: const TextStyle(fontWeight: FontWeight.w600),
                              ),
                            ),
                            const Icon(Icons.schedule, color: Colors.orange),
                            const SizedBox(width: 6),
                            Expanded(
                              child: Text(
                                'الوقت: $_routeDurationLabel',
                                style: const TextStyle(fontWeight: FontWeight.w600),
                                textAlign: TextAlign.end,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        if (!_isNavigating)
                          SizedBox(
                            width: double.infinity,
                            child: FilledButton.icon(
                              onPressed: _startTrip,
                              icon: const Icon(Icons.navigation),
                              label: const Text('بدء الرحلة'),
                            ),
                          )
                        else
                          Row(
                            children: [
                              Expanded(
                                child: OutlinedButton.icon(
                                  onPressed: _isFinishingTrip ? null : _cancelTripWithConfirmation,
                                  icon: const Icon(Icons.close),
                                  label: const Text('إلغاء الرحلة'),
                                ),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: FilledButton.icon(
                                  onPressed: _isFinishingTrip ? null : () => _finishTrip(),
                                  icon: const Icon(Icons.flag),
                                  label: Text(_isFinishingTrip ? 'جارٍ الحفظ...' : 'إنهاء الرحلة'),
                                ),
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
              MaterialPageRoute<void>(builder: (_) => const ProfilePage()),
            );
          } else if (index == 0) {
            showLogoutDialog(context);
          }
        },
      ),
    );
  }
}
