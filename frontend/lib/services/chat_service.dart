import 'dart:convert';
import 'package:http/http.dart' as http;
import 'api_service.dart';

class ChatService {
  static String get baseUrl => ApiService.baseUrl;

  // ==========================================================
  // SEND CHAT MESSAGE
  // ==========================================================
  static Future<Map<String, dynamic>> sendChatMessage(
    String message, {
    int farmId = 1,
    List<Map<String, String>> history = const [],
  }) async {
    final payload = {
      'farm_id': farmId,
      'message': message,
      'history': history,
    };

    // 1. Try current verified baseUrl first if available
    if (ApiService.baseUrl.isNotEmpty) {
      try {
        final url = Uri.parse('${ApiService.baseUrl}/agent/chat');
        final response = await http
            .post(
              url,
              headers: {'Content-Type': 'application/json'},
              body: jsonEncode(payload),
            )
            .timeout(const Duration(seconds: 25));

        if (response.statusCode == 200) {
          return Map<String, dynamic>.from(jsonDecode(response.body));
        }
      } catch (_) {
        // Active baseUrl unreachable or timed out, attempt failover across candidates
      }
    }

    // 2. Failover across prioritized candidate URLs
    dynamic lastError;

    for (final base in ApiService.prioritizedUrls) {
      if (base == ApiService.baseUrl) continue; // Already tried above
      try {
        final url = Uri.parse('$base/agent/chat');
        final response = await http
            .post(
              url,
              headers: {'Content-Type': 'application/json'},
              body: jsonEncode(payload),
            )
            .timeout(const Duration(seconds: 12));

        if (response.statusCode == 200) {
          ApiService.baseUrl = base;
          return Map<String, dynamic>.from(jsonDecode(response.body));
        } else {
          lastError = 'Server returned ${response.statusCode}: ${response.body}';
        }
      } catch (e) {
        lastError = e;
        continue;
      }
    }

    throw Exception('Failed to communicate with Farming Assistant ($lastError)');
  }

  // ==========================================================
  // PROMPT SUGGESTIONS
  // ==========================================================
  static Future<List<String>> getSuggestions() async {
    for (final base in ApiService.prioritizedUrls) {
      try {
        final url = Uri.parse('$base/agent/suggestions');
        final response = await http.get(url).timeout(const Duration(seconds: 3));

        if (response.statusCode == 200) {
          ApiService.baseUrl = base;
          final data = jsonDecode(response.body);
          final List<dynamic> suggestions = data['suggestions'] ?? [];
          return suggestions.map((s) => s.toString()).toList();
        }
      } catch (_) {
        continue;
      }
    }
    return _defaultSuggestions();
  }

  // ==========================================================
  // AGENT STATUS
  // ==========================================================
  static Future<Map<String, dynamic>> getAgentStatus() async {
    for (final base in ApiService.prioritizedUrls) {
      try {
        final url = Uri.parse('$base/agent/status');
        final response = await http.get(url).timeout(const Duration(seconds: 3));

        if (response.statusCode == 200) {
          ApiService.baseUrl = base;
          return Map<String, dynamic>.from(jsonDecode(response.body));
        }
      } catch (_) {
        continue;
      }
    }

    return {
      'groq_configured': true,
      'active_model': 'Agricultural AI Advisor',
      'message': 'Assistant Online',
    };
  }

  static List<String> _defaultSuggestions() {
    return [
      'What is the current soil moisture & temperature?',
      'When was the last watering session?',
      'What crop is planted on my farm?',
      'Were any diseases detected recently?',
      'Check irrigation logs',
    ];
  }
}
