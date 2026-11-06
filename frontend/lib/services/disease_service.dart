import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';

import 'api_service.dart';

class DiseaseService {
  static Future<Map<String, dynamic>> predictCropDisease(
    XFile imageFile, {
    int farmId = 1,
  }) async {
    dynamic lastError;

    for (final base in ApiService.prioritizedUrls) {
      try {
        final uri = Uri.parse('$base/disease/predict?farm_id=$farmId');
        final request = http.MultipartRequest('POST', uri);

        request.files.add(
          await http.MultipartFile.fromPath('file', imageFile.path),
        );

        final streamedResponse = await request.send().timeout(const Duration(seconds: 35));
        final response = await http.Response.fromStream(streamedResponse);

        if (response.statusCode == 200) {
          ApiService.baseUrl = base;
          final data = jsonDecode(response.body);

          if (data is Map<String, dynamic>) {
            return data;
          }
          throw Exception('Invalid response format from disease prediction API');
        } else {
          lastError = 'Server returned ${response.statusCode}: ${response.body}';
        }
      } catch (e) {
        lastError = e;
        continue;
      }
    }

    throw Exception('Disease prediction failed: $lastError');
  }

  static Future<List<dynamic>> getDiseaseHistory(int farmId) async {
    return ApiService.getDiseaseHistory(farmId);
  }
}
