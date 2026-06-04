import 'package:flutter/foundation.dart';
import 'package:fridge_app/models/meal_slot.dart';
import 'package:fridge_app/services/cf_recommender_client.dart';
import 'package:fridge_app/services/database_service.dart';
import 'package:fridge_app/services/dismissal_service.dart';
import 'package:fridge_app/services/fridge_service.dart';
import 'package:fridge_app/services/kb_recommender_service.dart';
import 'package:fridge_app/services/recipe_service.dart';
import 'package:fridge_app/services/user_profile_service.dart';

/// One snapshot per meal slot — same data shape as the Python script's
/// per-meal output. Tab switching in the UI is a cache hit.
class RecommendationBundle {
  final List<MealSlot> mealPlan;
  final Map<MealSlot, List<ScoredRecipe>> bySlot;
  final bool cfAvailable;

  const RecommendationBundle({
    required this.mealPlan,
    required this.bySlot,
    required this.cfAvailable,
  });

  List<ScoredRecipe> forSlot(MealSlot slot) => bySlot[slot] ?? const [];
}

/// Iterates the user's meal plan exactly the way Python's
/// `test_kb_recommendations.py` does: at each slot the static candidate
/// list is re-scored against the current tracker state, top 5 is taken
/// (3 full + 2 partial), and the chosen recipe is "recorded" so the next
/// slot's adaptive limits tighten and that recipe isn't suggested again.
class RecommendationService {
  RecommendationService._();
  static final RecommendationService instance = RecommendationService._();

  /// Boost added to each CF pick before slot-blending. Roughly matches the
  /// +15 serendipity bonus in test_boundary_cf_recommendations.py.
  static const double _cfBoost = 15.0;

  Future<RecommendationBundle> getRecommendations({int perSlot = 5}) async {
    final base = await KbRecommenderService.instance.prepareCandidates();
    final tracker = base.tracker;
    final user = UserProfileService.instance.current;
    if (tracker == null || user == null || base.candidates.isEmpty) {
      return const RecommendationBundle(
        mealPlan: [], bySlot: {}, cfAvailable: false);
    }

    final mealPlan = MealPlan.forCount(user.mealsPerDay);

    // CF: one query, results filtered out as the tracker accumulates them.
    final liked = await _likedRecipeIdsFromHistory();
    final dismissed = await DismissalService.instance.dismissedIds();
    final kbDbIds = base.candidates
        .map((c) => _extractDbId(c.recipe.id))
        .whereType<int>()
        .take(50)
        .toList();
    final cfPicks = await CfRecommenderClient.instance.recommend(
      likedRecipeIds: liked,
      // Mix KB favourites + dismissed ids so CF never suggests recipes the
      // user already saw or rejected.
      excludeRecipeIds: [...kbDbIds, ...dismissed],
      topN: 30,
    );
    final fridge = FridgeService.instance
        .getAllItems()
        .map((i) => i.name.toLowerCase())
        .toList();
    final cfScored = _materialiseCfPicks(cfPicks ?? const [], fridge);

    final bySlot = <MealSlot, List<ScoredRecipe>>{};
    for (final slot in mealPlan) {
      final scored =
          KbRecommenderService.instance.scoreCandidates(base.candidates, tracker);
      final cfRemaining = cfScored
          .where((s) => !tracker.eatenRecipeNames
              .contains(s.recipe.title.toLowerCase()))
          .toList();
      final picks = _blendForSlot(scored, cfRemaining, perSlot);
      bySlot[slot] = picks;

      // Advance the tracker by the top pick — Python's `record_meal`.
      if (picks.isNotEmpty) tracker.recordMeal(picks.first);
    }

    _logRecommendations(mealPlan, bySlot, cfPicks != null);
    return RecommendationBundle(
      mealPlan: mealPlan,
      bySlot: bySlot,
      cfAvailable: cfPicks != null,
    );
  }

  /// 3 KB full + 2 CF + KB partial overflow + KB full overflow. Dedupes by
  /// recipe id.
  List<ScoredRecipe> _blendForSlot(
    List<ScoredRecipe> kbScored,
    List<ScoredRecipe> cfScored,
    int limit,
  ) {
    final kbFull = kbScored.where((s) => s.isFullMatch).toList();
    final kbPartial = kbScored.where((s) => !s.isFullMatch).toList();
    final out = <ScoredRecipe>[];
    final seen = <String>{};
    void add(ScoredRecipe s) {
      if (out.length < limit && seen.add(s.recipe.id)) out.add(s);
    }

    kbFull.take(3).forEach(add);
    cfScored.forEach(add);
    kbPartial.forEach(add);
    kbFull.skip(3).forEach(add);
    return out;
  }

  List<ScoredRecipe> _materialiseCfPicks(
    List<CfPrediction> picks,
    List<String> fridge,
  ) {
    final out = <ScoredRecipe>[];
    for (final c in picks) {
      final recipe = RecipeService.instance.getRecipeByDbId(c.recipeId);
      if (recipe == null) continue;
      final ingNames =
          recipe.ingredients.map((i) => i.name.toLowerCase()).toList();
      final match = KbRecommenderService.ingredientMatch(fridge, ingNames);
      out.add(ScoredRecipe(
        recipe: recipe,
        score: c.combinedScore + _cfBoost,
        matchRatio: match.ratio,
        matchedIngredients: match.matched,
        missingIngredients: match.missing,
        reasons: ['CF +${c.combinedScore.toStringAsFixed(1)}'],
        isFullMatch: match.ratio >= 0.8,
      ));
    }
    return out;
  }

  /// Mirrors Python's per-meal print block so the console output can be
  /// diff'd directly against test_kb_recommendations.py.
  void _logRecommendations(
    List<MealSlot> mealPlan,
    Map<MealSlot, List<ScoredRecipe>> bySlot,
    bool cfAvailable,
  ) {
    debugPrint('[REC] meal plan: ${mealPlan.map((m) => m.label).join(" → ")}'
        '  cfAvailable=$cfAvailable');
    for (final slot in mealPlan) {
      final picks = bySlot[slot] ?? const [];
      final full = picks.where((s) => s.isFullMatch).length;
      final partial = picks.length - full;
      debugPrint('[REC] ${slot.emoji} ${slot.label} '
          '(slot ${slot.index + 1}/${slot.totalSlots}) — '
          '$full full + $partial partial');
      for (var i = 0; i < picks.length; i++) {
        final s = picks[i];
        final tag = s.isFullMatch ? '🟢' : '🟡';
        final title = s.recipe.title.length > 48
            ? '${s.recipe.title.substring(0, 48)}…'
            : s.recipe.title;
        final missing = s.missingIngredients.isEmpty
            ? ''
            : '  missing: ${s.missingIngredients.take(3).join(", ")}'
                '${s.missingIngredients.length > 3 ? "…" : ""}';
        debugPrint(
          '[REC]   ${i + 1}. $tag [${s.score.toStringAsFixed(1)}p] '
          '${title.padRight(50)} '
          'match=${(s.matchRatio * 100).toStringAsFixed(0)}%$missing',
        );
        final why = _formatWhy(s);
        if (why.isNotEmpty) debugPrint('[REC]      why → $why');
      }
    }
  }

  /// Human-readable breakdown of a recipe's score adjustments, grouped by
  /// origin. Empty when nothing nudged the score (perfect baseline).
  String _formatWhy(ScoredRecipe s) {
    final groups = s.reasonsByCategory;
    final parts = <String>[];
    void emit(ReasonCategory c) {
      final items = groups[c] ?? const [];
      if (items.isEmpty) return;
      parts.add('${c.label}: ${items.join(", ")}');
    }

    emit(ReasonCategory.who);
    emit(ReasonCategory.bodyType);
    emit(ReasonCategory.ingredient);
    emit(ReasonCategory.cf);
    return parts.join(' | ');
  }

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
