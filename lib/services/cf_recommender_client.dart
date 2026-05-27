import 'dart:async';
import 'dart:convert';
import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

class CfPrediction {
  final int recipeId;
  final double cfScore;
  final double serendipity;
  final String name;

  const CfPrediction({
    required this.recipeId,
    required this.cfScore,
    required this.serendipity,
    required this.name,
  });

  double get combinedScore => cfScore + serendipity;
}

/// HTTP client for the Python CF service in `cf_server/`. Returns null on
/// any failure (timeout, network error, bad response) so callers can fall
/// back to KB-only recommendations without leaking exceptions.
class CfRecommenderClient {
  CfRecommenderClient._();
  static final CfRecommenderClient instance = CfRecommenderClient._();

  static const Duration _timeout = Duration(seconds: 3);

  String get _baseUrl {
    if (kIsWeb) return 'http://localhost:8000';
    try {
      if (Platform.isAndroid) return 'http://10.0.2.2:8000';
    } catch (_) {/* not on a platform with Platform */}
    return 'http://localhost:8000';
  }

  Future<bool> ping() async {
    try {
      final r = await http.get(Uri.parse('$_baseUrl/health')).timeout(_timeout);
      return r.statusCode == 200;
    } catch (_) {
      return false;
    }
  }

  Future<List<CfPrediction>?> recommend({
    String? profileTag,
    List<int> likedRecipeIds = const [],
    List<int> excludeRecipeIds = const [],
    int topN = 5,
  }) async {
    try {
      final body = jsonEncode({
        if (profileTag != null) 'profile_tag': profileTag,
        'liked_recipe_ids': likedRecipeIds,
        'exclude_recipe_ids': excludeRecipeIds,
        'top_n': topN,
      });
      final r = await http
          .post(
            Uri.parse('$_baseUrl/recommend'),
            headers: const {'Content-Type': 'application/json'},
            body: body,
          )
          .timeout(_timeout);
      if (r.statusCode != 200) {
        debugPrint('[CF] non-200: ${r.statusCode} ${r.body}');
        return null;
      }
      final decoded = jsonDecode(r.body) as Map<String, dynamic>;
      final list = (decoded['recipes'] as List).cast<Map<String, dynamic>>();
      return list
          .map((m) => CfPrediction(
                recipeId: (m['recipe_id'] as num).toInt(),
                cfScore: (m['cf_score'] as num).toDouble(),
                serendipity: (m['serendipity'] as num).toDouble(),
                name: m['name'] as String? ?? '',
              ))
          .toList();
    } catch (e) {
      debugPrint('[CF] request failed: $e');
      return null;
    }
  }
}
