import 'package:fridge_app/models/meal_type.dart';
import 'package:fridge_app/services/cf_recommender_client.dart';
import 'package:fridge_app/services/database_service.dart';
import 'package:fridge_app/services/fridge_service.dart';
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

  Future<RecommendationBundle> getRecommendations({
    int limit = 5,
    MealType mealType = MealType.all,
  }) async {
    final kbResults = await KbRecommenderService.instance.recommend(
      limit: limit * 2,
      mealType: mealType,
    );
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

    // CF doesn't know about the fridge. Run the same KB ingredient matcher
    // over its picks so the card UI shows an accurate "missing N items" badge
    // instead of falsely claiming the user has everything.
    final fridge = FridgeService.instance
        .getAllItems()
        .map((i) => i.name.toLowerCase())
        .toList();

    final blended = <ScoredRecipe>[];
    final seen = <String>{};
    for (final s in kbResults.take(3)) {
      blended.add(s);
      seen.add(s.recipe.id);
    }
    for (final c in cfResults) {
      final recipe = RecipeService.instance.getRecipeByDbId(c.recipeId);
      if (recipe == null || seen.contains(recipe.id)) continue;
      final ingNames =
          recipe.ingredients.map((i) => i.name.toLowerCase()).toList();
      final match = KbRecommenderService.ingredientMatch(fridge, ingNames);
      final boosted = ScoredRecipe(
        recipe: recipe,
        score: c.combinedScore + _cfBoost,
        matchRatio: match.ratio,
        matchedIngredients: match.matched,
        missingIngredients: match.missing,
        reasons: ['CF +${c.combinedScore.toStringAsFixed(1)}'],
        isFullMatch: match.ratio >= 0.8,
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

  /// Recipe ids the user has actually cooked, newest first. Comes from
  /// `cooked_recipes` (populated by the "Mark cooked" button on the prep
  /// screen) so the CF service gets a clean per-recipe taste signal instead
  /// of a heuristic over consumption log item names.
  Future<List<int>> _likedRecipeIdsFromHistory() async {
    final rows = await DatabaseService.instance.queryWhere(
      'cooked_recipes',
      orderBy: 'cooked_at DESC',
      limit: 50,
    );
    return rows
        .map((r) => (r['recipe_id'] as num?)?.toInt())
        .whereType<int>()
        .toList();
  }

  int? _extractDbId(String recipeId) {
    if (!recipeId.startsWith('db_')) return null;
    return int.tryParse(recipeId.substring(3));
  }
}
