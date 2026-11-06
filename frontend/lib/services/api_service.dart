import 'dart:convert';

import 'package:http/http.dart' as http;

class ApiService {
  // Primary URL is http://127.0.0.1:8888 (tunneled to PC port 8000 via adb reverse, bypassing Realme internal port conflicts)
  static String baseUrl = 'http://127.0.0.1:8000';

  static final List<String> candidateUrls = [
    'http://127.0.0.1:8000',
    'http://192.168.31.122:8000',
    'http://10.0.2.2:8000',
    'http://127.0.0.1:8888',
    'http://localhost:8000',
    'http://10.11.140.40:8000',
    'http://10.10.18.142:8000',
  ];

  static List<String> get prioritizedUrls {
    final list = <String>[];
    if (baseUrl.trim().isNotEmpty) {
      list.add(baseUrl.trim());
    }
    for (final base in candidateUrls) {
      if (!list.contains(base)) {
        list.add(base);
      }
    }
    return list;
  }

  static Future<http.Response> getWithFailover(String path) async {
    for (final base in prioritizedUrls) {
      try {
        final res = await http
            .get(Uri.parse('$base$path'))
            .timeout(const Duration(seconds: 4));
        if (res.statusCode == 200) {
          baseUrl = base;
          return res;
        }
      } catch (_) {
        continue;
      }
    }
    throw Exception('Backend connection failed across all hosts ($candidateUrls)');
  }

  static Future<http.Response> postWithFailover(String path, Map<String, dynamic> body) async {
    for (final base in prioritizedUrls) {
      try {
        final res = await http
            .post(
              Uri.parse('$base$path'),
              headers: {'Content-Type': 'application/json'},
              body: jsonEncode(body),
            )
            .timeout(const Duration(seconds: 4));
        if (res.statusCode == 200) {
          baseUrl = base;
          return res;
        }
      } catch (_) {
        continue;
      }
    }
    throw Exception('POST request failed across all hosts ($candidateUrls)');
  }

  // ==========================================================
  // SENSOR DATA
  // ==========================================================

  static Future<Map<String, dynamic>> getSensorData() async {
    final response = await getWithFailover('/sensors/');
    return Map<String, dynamic>.from(jsonDecode(response.body));
  }

  // ==========================================================
  // DEVICE PUMP CONTROL
  // ==========================================================

  static Future<Map<String, dynamic>> setDeviceControl({
    required String mode,
    bool manualPumpRequest = false,
  }) async {
    final response = await postWithFailover('/api/device/control', {
      'mode': mode,
      'manual_pump_request': manualPumpRequest,
    });
    return Map<String, dynamic>.from(jsonDecode(response.body));
  }

  // ==========================================================
  // WEATHER & RAIN FORECAST
  // ==========================================================

  static Future<Map<String, dynamic>> getWeather(String city) async {
    final encoded = Uri.encodeComponent(city.trim().isEmpty ? 'Bengaluru' : city.trim());
    final response = await getWithFailover('/weather/?city=$encoded');
    return Map<String, dynamic>.from(jsonDecode(response.body));
  }

  // ==========================================================
  // FARM
  // ==========================================================

  static Future<Map<String, dynamic>> getFarm(int farmId) async {
    final response = await getWithFailover('/farms/$farmId');
    final List<dynamic> data = jsonDecode(response.body);

    if (data.isEmpty) {
      throw Exception('Farm not found');
    }

    return Map<String, dynamic>.from(data.first);
  }

  // ==========================================================
  // IRRIGATION HISTORY
  // ==========================================================

  static Future<List<dynamic>> getIrrigationHistory(int farmId) async {
    final response = await getWithFailover('/irrigation/$farmId');
    return List<dynamic>.from(jsonDecode(response.body));
  }

  // ==========================================================
  // IRRIGATION SUMMARY
  // ==========================================================

  static Future<Map<String, dynamic>> getIrrigationSummary(int farmId) async {
    final response = await getWithFailover('/irrigation/$farmId/summary');
    return Map<String, dynamic>.from(jsonDecode(response.body));
  }

  // ==========================================================
  // DISEASE HISTORY
  // ==========================================================

  static Future<List<dynamic>> getDiseaseHistory(int farmId) async {
    final response = await getWithFailover('/disease/$farmId');
    return List<dynamic>.from(jsonDecode(response.body));
  }
}
