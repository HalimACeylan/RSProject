import 'package:fridge_app/services/cf_recommender_client.dart';
import 'package:fridge_app/services/database_service.dart';
import 'package:fridge_app/services/kb_recommender_service.dart';
import 'package:fridge_app/services/recipe_service.dart';

/// Result of a recommendation pass. `cfAvailable` lets the UI surface whether
/// the Python CF service responded or we fell back to KB-only.
class RecommendationBundle {
  final List<ScoredRecipe> recipes;
  final bool cfAvailable;
  const RecommendationBundle({required this.recipes, required this.cfAvailable});
}

/// Blends KB scores with CF predictions. KB owns 3 of 5 slots (full-match
/// guarantee), CF contributes diversity for the remaining 2 by adding a small
/// score bonus to its picks before re-ranking. Falls back gracefully if the
/// Python service is offline.
class RecommendationService {
  RecommendationService._();
  static final RecommendationService instance = RecommendationService._();

  /// CF score bonus applied per slot when blending. Tuned to roughly match the
  /// "+15 serendipity bonus" magnitude in test_boundary_cf_recommendations.py.
  static const double _cfBoost = 15.0;

  Future<RecommendationBundle> getRecommendations({int limit = 5}) async {
    final kbResults = await KbRecommenderService.instance.recommend(limit: limit * 2);
    if (kbResults.isEmpty) {
      return const RecommendationBundle(recipes: [], cfAvailable: false);
    }

    final liked = await _likedRecipeIdsFromHistory();
    final excluded = kbResults
        .map((s) => _extractDbId(s.recipe.id))
        .whereType<int>()
        .toList();
    final cfResults = await CfRecommenderClient.instance.recommend(
      likedRecipeIds: liked,
      excludeRecipeIds: excluded,
      topN: limit,
    );

    if (cfResults == null || cfResults.isEmpty) {
      return RecommendationBundle(
        recipes: kbResults.take(limit).toList(),
        cfAvailable: false,
      );
    }

    final blended = <ScoredRecipe>[];
    final seen = <String>{};
    for (final s in kbResults.take(3)) {
      blended.add(s);
      seen.add(s.recipe.id);
    }
    for (final c in cfResults) {
      final recipe = RecipeService.instance.getRecipeByDbId(c.recipeId);
      if (recipe == null || seen.contains(recipe.id)) continue;
      final boosted = ScoredRecipe(
        recipe: recipe,
        score: c.combinedScore + _cfBoost,
        matchRatio: 0,
        matchedIngredients: const [],
        missingIngredients: const [],
        reasons: ['CF +${c.combinedScore.toStringAsFixed(1)}'],
        isFullMatch: false,
      );
      blended.add(boosted);
      seen.add(recipe.id);
      if (blended.length >= limit) break;
    }
    if (blended.length < limit) {
      for (final s in kbResults.skip(3)) {
        if (seen.add(s.recipe.id)) blended.add(s);
        if (blended.length >= limit) break;
      }
    }

    return RecommendationBundle(recipes: blended, cfAvailable: true);
  }

  /// Pulls DB recipe ids the user has interacted with via consumption logs +
  /// (future) recipe ratings. Right now we extract from consumption_logs by
  /// best-effort matching item_name to recipe ingredients, but a richer signal
  /// will come from when we record "I cooked this recipe" events.
  Future<List<int>> _likedRecipeIdsFromHistory() async {
    final logs = await DatabaseService.instance.queryAll('consumption_logs');
    if (logs.isEmpty) return const [];
    // Heuristic: any recipe whose title contains a consumed item name is
    // considered "interacted with". Cheap, no schema additions.
    final names = logs
        .map((r) => (r['item_name'] as String? ?? '').toLowerCase())
        .where((s) => s.isNotEmpty)
        .toSet();
    if (names.isEmpty) return const [];
    final ids = <int>[];
    for (final recipe in RecipeService.instance.allRecipes) {
      final t = recipe.title.toLowerCase();
      if (names.any((n) => t.contains(n))) {
        final dbId = _extractDbId(recipe.id);
        if (dbId != null) ids.add(dbId);
        if (ids.length >= 30) break;
      }
    }
    return ids;
  }

  int? _extractDbId(String recipeId) {
    if (!recipeId.startsWith('db_')) return null;
    return int.tryParse(recipeId.substring(3));
  }
}
