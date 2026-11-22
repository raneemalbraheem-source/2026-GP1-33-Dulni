
import 'dart:typed_data';
import 'dart:convert';

import 'package:firebase_app_check/firebase_app_check.dart';
import 'package:http/http.dart' as http;

class VoiceBackendService {
  VoiceBackendService._();

  static final VoiceBackendService instance = VoiceBackendService._();

  static const String _baseUrl = 'http://10.0.2.2:3000/api/voice';

  Future<Map<String, String>> _getHeaders() async {
    final token = await FirebaseAppCheck.instance.getToken();

    if (token == null || token.isEmpty) {
      throw Exception('Unable to verify this app. Please try again.');
    }

    return {
      'X-Firebase-AppCheck': token,
    };
  }

  Future<Map<String, dynamic>> getSttToken() async {
    final headers = await _getHeaders();

    final response = await http
        .post(
          Uri.parse('$_baseUrl/stt-token'),
          headers: headers,
        )
        .timeout(const Duration(seconds: 15));

    if (response.statusCode != 200) {
      throw Exception('Unable to initialize speech recognition.');
    }

    final data = _decodeJson(response.body);

    if (data['success'] != true ||
        data['token'] == null ||
        data['region'] == null) {
      throw Exception('Invalid speech token response.');
    }

    return {
      'token': data['token'] as String,
      'region': data['region'] as String,
    };
  }

  Future<Uint8List> generateSpeech({
    required String text,
    String voicePersona = 'sara',
  }) async {
    if (text.trim().isEmpty) {
      throw ArgumentError('Speech text cannot be empty.');
    }

    final headers = await _getHeaders();
    headers['Content-Type'] = 'application/json';

    final response = await http
        .post(
          Uri.parse('$_baseUrl/tts'),
          headers: headers,
          body: _encodeJson({
            'text': text,
            'voicePersona': voicePersona,
          }),
        )
        .timeout(const Duration(seconds: 40));

    if (response.statusCode != 200) {
      throw Exception('Unable to generate speech.');
    }

    if (response.bodyBytes.isEmpty) {
      throw Exception('The speech response is empty.');
    }

    return response.bodyBytes;
  }

  Map<String, dynamic> _decodeJson(String body) {
    return Map<String, dynamic>.from(
      jsonDecode(body) as Map,
    );
  }

  String _encodeJson(Map<String, dynamic> data) {
    return jsonEncode(data);
  }
}
