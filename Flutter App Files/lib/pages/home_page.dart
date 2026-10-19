import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

import 'profile_page.dart';
import '../widgets/app_bottom_navigation.dart';
import '../services/logout_helper.dart';
import 'dart:convert';
import 'package:http/http.dart' as http;
import '../services/permission_service.dart';


  class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}


class _HomePageState extends State<HomePage> {

  final TextEditingController _searchController = TextEditingController();
  List<dynamic> _predictions = [];

final String _apiKey = 'AIzaSyDbR0749RMXFBdJsqa0Ow6OFAveZACeo_k';

@override
void initState() {
  super.initState();
  _requestPermissions();
}

Future<void> _requestPermissions() async {
  await PermissionService.requestLocationPermission(context);

  await PermissionService.requestMicrophonePermission(context);
}

Future<void> searchPlaces(String input) async {
   if (input.isEmpty) {
    setState(() {
      _predictions = [];
    });
    return;
  }

  final url =
      'https://maps.googleapis.com/maps/api/place/autocomplete/json'
      '?input=$input'
      '&language=ar'
      '&key=$_apiKey';

  final response = await http.get(Uri.parse(url));

  print(response.statusCode);
  print(response.body);

  if (response.statusCode == 200) {
    final data = jsonDecode(response.body);

    setState(() {
      _predictions = data['predictions'] ?? [];
    });
  }
 }


  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        automaticallyImplyLeading: false,
        title: const Text('دلني'),
       

      ),
    
      body: SafeArea(
      child: Stack(
      children: [
       GoogleMap(
        initialCameraPosition: CameraPosition(
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
          onChanged: (value) {  
          print('Searching: $value');
          searchPlaces(value); 
          //print(value);

           },
            decoration: InputDecoration(
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
      if (_predictions.isNotEmpty)
  Positioned(
    top: 80,
    left: 16,
    right: 16,
    child: Material(
      elevation: 4,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        constraints: const BoxConstraints(
          maxHeight: 250,
        ),
        color: Colors.white,
        child: ListView.builder(
          shrinkWrap: true,
          itemCount: _predictions.length,
          itemBuilder: (context, index) {
            return ListTile(
              title: Text(
                _predictions[index]['description'],
              ),
            );
          },
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
      MaterialPageRoute(
        builder: (_) => const ProfilePage(),
      ),
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