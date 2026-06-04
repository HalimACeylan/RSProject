import 'package:flutter/foundation.dart';
import 'package:fridge_app/models/recipe.dart';
import 'package:fridge_app/models/user_profile.dart';
import 'package:fridge_app/services/database_service.dart';
import 'package:fridge_app/services/dismissal_service.dart';
import 'package:fridge_app/services/fridge_service.dart';
import 'package:fridge_app/services/kb_constants.dart';
import 'package:fridge_app/services/recipe_service.dart';
import 'package:fridge_app/services/user_profile_service.dart';

/// Single scored recommendation produced by the KB recommender.
class ScoredRecipe {
  final Recipe recipe;
  final double score;
  final double matchRatio;
  final List<String> matchedIngredients;
  final List<String> missingIngredients;
  final List<String> reasons;
  final bool isFullMatch;

  const ScoredRecipe({
    required this.recipe,
    required this.score,
    required this.matchRatio,
    required this.matchedIngredients,
    required this.missingIngredients,
    required this.reasons,
    required this.isFullMatch,
  });

  /// Group `reasons` by what produced them:
  ///   `who`        — macro penalties keyed off WHO daily-value limits
  ///                  (`Cal↑`, `Fat↑`, `Sugar↑`, `Na↑`, `SatFat↑`,
  ///                  `Carbs↑`, `Prot↓`).
  ///   `bodyType`   — profile-specific recovery bonuses (`💪 Prot
  ///                  recovery`, `🔥 Cal balance`, `🍬 Sugar↓`). These come
  ///                  from `PROFILE_SCORING.bonus_weights` so they reflect
  ///                  the user's `scoringKey` (general / athlete /
  ///                  adolescent / pregnant).
  ///   `ingredient` — profile-specific ingredient nudges (`✨...`, `⚠️...`)
  ///                  pulled from `PROFILE_SCORING.ingredient_bonuses` /
  ///                  `ingredient_penalties`. Same dependence on
  ///                  `scoringKey` as `bodyType`.
  ///   `cf`         — bonus added by the collaborative-filter blend.
  Map<ReasonCategory, List<String>> get reasonsByCategory {
    final out = <ReasonCategory, List<String>>{
      ReasonCategory.who: <String>[],
      ReasonCategory.bodyType: <String>[],
      ReasonCategory.ingredient: <String>[],
      ReasonCategory.cf: <String>[],
    };
    for (final r in reasons) {
      if (r.startsWith('💪') || r.startsWith('🔥') || r.startsWith('🍬')) {
        out[ReasonCategory.bodyType]!.add(r);
      } else if (r.startsWith('✨') || r.startsWith('⚠️')) {
        out[ReasonCategory.ingredient]!.add(r);
      } else if (r.startsWith('CF ')) {
        out[ReasonCategory.cf]!.add(r);
      } else {
        out[ReasonCategory.who]!.add(r);
      }
    }
    return out;
  }
}

/// Where a reason originated. Used by the log and any future "Why
/// recommended?" UI element to group adjustments by their source.
enum ReasonCategory {
  who('WHO macro'),
  bodyType('body-type'),
  ingredient('ingredients'),
  cf('CF');

  final String label;
  const ReasonCategory(this.label);
}

/// Mutable per-day tracker — accumulates macros and eaten recipe names as
/// each meal is "consumed". Mirrors Python's `DailyMealTracker` so KB can
/// re-score recipes per meal slot with shrinking adaptive limits.
class DailyTracker {
  final UserProfile user;
  final Map<String, double> dailyLimits;
  final Map<String, double> consumed;
  int mealsEatenCount;
  final Set<String> eatenRecipeNames;

  DailyTracker({
    required this.user,
    required this.dailyLimits,
    required this.consumed,
    required this.mealsEatenCount,
    required this.eatenRecipeNames,
  });

  int get mealsRemaining {
    final r = user.mealsPerDay - mealsEatenCount;
    return r < 1 ? 1 : r;
  }

  /// `(daily_limit - consumed) / remaining_meals` — Python's
  /// `get_adaptive_meal_limits`.
  Map<String, double> adaptiveMealLimits() {
    final n = mealsRemaining;
    return {
      for (final k in nutrKeys) k: (dailyLimits[k]! - consumed[k]!) / n,
    };
  }

  /// Python's `get_deficits` — pace gaps that drive the three recovery
  /// bonuses (protein, calorie, sugar).
  Map<String, double> deficits() {
    if (mealsEatenCount == 0) return const {};
    final d = <String, double>{};
    for (final k in nutrKeys) {
      final ideal = dailyLimits[k]! * mealsEatenCount / user.mealsPerDay;
      final diff = ideal - consumed[k]!;
      if (k == 'protein_pdv' && diff > 0) {
        d[k] = diff;
      } else if (k != 'protein_pdv' && diff < 0) {
        d[k] = diff;
      }
    }
    return d;
  }

  /// Equivalent of Python's `record_meal(name, recipe)`. Adds nutrition[i]
  /// to consumed, increments meals_eaten, and remembers the recipe name so
  /// it won't be re-suggested later today.
  void recordMeal(ScoredRecipe scored) {
    final n = scored.recipe.nutrition;
    if (n.length >= nutrKeys.length) {
      for (var i = 0; i < nutrKeys.length; i++) {
        consumed[nutrKeys[i]] = consumed[nutrKeys[i]]! + n[i];
      }
    }
    mealsEatenCount++;
    eatenRecipeNames.add(scored.recipe.title.toLowerCase());
  }
}

/// Recipe + cached static filter results (ingredient match, lowercased ings).
/// Computed once per `prepareCandidates` call; the tracker-dependent
/// `_scoreRecipe` runs against this per meal slot.
class Candidate {
  final Recipe recipe;
  final List<String> ingNames;
  final ({double ratio, List<String> matched, List<String> missing}) match;
  const Candidate({required this.recipe, required this.ingNames, required this.match});
}

class KbRecommenderService {
  KbRecommenderService._();
  static final KbRecommenderService instance = KbRecommenderService._();

  /// Build the per-day tracker (seeded from today's cooked_recipes) plus the
  /// static candidate list — recipes that pass tracker-independent filters
  /// (nutrition shape + ingredient match ≥0.3 + dietary disqualification).
  /// [RecommendationService] keeps this list around and calls
  /// [scoreCandidates] once per meal slot, advancing the tracker in between.
  Future<({DailyTracker? tracker, List<Candidate> candidates})>
      prepareCandidates() async {
    final user = UserProfileService.instance.current;
    if (user == null) {
      debugPrint('[KB] No user profile saved.');
      return (tracker: null, candidates: const <Candidate>[]);
    }
    final sw = Stopwatch()..start();
    final tracker = await _buildTrackerFromToday(user);
    final fridge = FridgeService.instance
        .getAllItems()
        .map((i) => i.name.toLowerCase())
        .toList();
    // Recipes the user explicitly told us to stop recommending. Cheap to load
    // up-front (one table scan) and lets us skip them before any scoring.
    final dismissed = await DismissalService.instance.dismissedIds();

    int considered = 0, prefiltered = 0, disqualified = 0, dismissedCount = 0;
    final out = <Candidate>[];
    for (final recipe in RecipeService.instance.allRecipes) {
      if (recipe.nutrition.length < 7) continue;
      final dbId = _dbIdOf(recipe.id);
      if (dismissed.contains(dbId)) {
        dismissedCount++;
        continue;
      }
      final ingNames =
          recipe.ingredients.map((i) => i.name.toLowerCase()).toList();
      if (ingNames.isEmpty) continue;
      considered++;
      final match = ingredientMatch(fridge, ingNames);
      if (match.ratio < 0.3) {
        prefiltered++;
        continue;
      }
      if (_isDisqualified(user, ingNames)) {
        disqualified++;
        continue;
      }
      out.add(Candidate(recipe: recipe, ingNames: ingNames, match: match));
    }
    sw.stop();
    debugPrint(
      '[KB] candidates: profile=${user.scoringKey} fridge=${fridge.length} '
      'recipes=$considered dismissed=$dismissedCount '
      'prefiltered=$prefiltered disqualified=$disqualified '
      'eligible=${out.length} took=${sw.elapsedMilliseconds}ms',
    );
    return (tracker: tracker, candidates: out);
  }

  /// Score the static candidate list against the current tracker state.
  /// Drops recipes already eaten today (per tracker), then sorts by
  /// `(score desc, matchRatio desc, id asc)` deterministically.
  List<ScoredRecipe> scoreCandidates(
    List<Candidate> candidates,
    DailyTracker tracker,
  ) {
    final scoring = profileScoring[tracker.user.scoringKey] ??
        profileScoring['general_adult']!;
    final adaptiveLimits = tracker.adaptiveMealLimits();
    final deficits = tracker.deficits();
    final scored = <ScoredRecipe>[];
    for (final c in candidates) {
      if (tracker.eatenRecipeNames.contains(c.recipe.title.toLowerCase())) {
        continue;
      }
      final s = _scoreRecipe(
        recipe: c.recipe,
        ingNames: c.ingNames,
        match: c.match,
        adaptiveLimits: adaptiveLimits,
        deficits: deficits,
        scoring: scoring,
      );
      if (s != null) scored.add(s);
    }
    scored.sort((a, b) {
      final s = b.score.compareTo(a.score);
      if (s != 0) return s;
      final m = b.matchRatio.compareTo(a.matchRatio);
      if (m != 0) return m;
      return _dbIdOf(a.recipe.id).compareTo(_dbIdOf(b.recipe.id));
    });
    return scored;
  }

  /// Parse the integer DB id out of a Recipe.id like `db_31490`. Returns a
  /// huge sentinel for non-DB ids so sample/hand-crafted recipes (if any
  /// re-appear) sort to the end deterministically.
  static int _dbIdOf(String recipeId) {
    if (!recipeId.startsWith('db_')) return 1 << 31;
    return int.tryParse(recipeId.substring(3)) ?? (1 << 31);
  }

  /// 3 full-match + 2 partial slot allocation — same rule as Python's
  /// `recommend_5`. Caller passes a pre-sorted list (e.g. from [scoreAll]
  /// optionally filtered by meal-type tag); we cherry-pick up to [limit]
  /// recipes, preferring full matches first, then filling partials, then
  /// overflowing back to full matches if we ran out of partials.
  static List<ScoredRecipe> allocateSlots(
    List<ScoredRecipe> sortedScored, {
    int limit = 5,
  }) {
    final full = sortedScored.where((s) => s.isFullMatch).toList(growable: false);
    final partial = sortedScored.where((s) => !s.isFullMatch).toList(growable: false);

    final result = <ScoredRecipe>[];
    result.addAll(full.take(3));
    final partialNeeded = limit - result.length;
    if (partialNeeded > 0) result.addAll(partial.take(partialNeeded));
    if (result.length < limit) {
      result.addAll(full.skip(3).take(limit - result.length));
    }
    return result.take(limit).toList();
  }

  /// Ingredient match: fraction of recipe ingredients present in fridge.
  ///
  /// Bidirectional substring on raw lowercased strings — direct port of
  /// `calc_ingredient_match` in `datasets_to_use/test_kb_recommendations.py`
  /// (`any(f in ing or ing in f for f in fridge)`). Both sides are already
  /// lowercased by the caller.
  static ({double ratio, List<String> matched, List<String> missing})
      ingredientMatch(List<String> fridge, List<String> ingredients) {
    if (ingredients.isEmpty) return (ratio: 0, matched: const [], missing: const []);
    final matched = <String>[];
    final missing = <String>[];
    for (final ing in ingredients) {
      final hit = fridge.any((f) => f.contains(ing) || ing.contains(f));
      (hit ? matched : missing).add(ing);
    }
    return (
      ratio: matched.length / ingredients.length,
      matched: matched,
      missing: missing,
    );
  }

  // ── internals ────────────────────────────────────────────────────

  Future<DailyTracker> _buildTrackerFromToday(UserProfile user) async {
    final now = DateTime.now();
    final startOfDay = DateTime(now.year, now.month, now.day).millisecondsSinceEpoch;
    final cookedToday = await DatabaseService.instance.queryWhere(
      'cooked_recipes',
      where: 'cooked_at >= ?',
      whereArgs: [startOfDay],
    );

    // Accumulate today's macros from cooked recipes — equivalent to Python's
    // DailyMealTracker.record_meal which sums recipe["nutrition"] into
    // self.consumed. We deliberately ignore standalone consumption_logs rows
    // here: their amounts are in the user's chosen unit (cups/pieces/grams)
    // not in the %DV scale the recipe nutrition array uses, so mixing them
    // would distort adaptive limits and deficit bonuses.
    final consumed = {for (final k in nutrKeys) k: 0.0};
    final eatenRecipeNames = <String>{};
    for (final row in cookedToday) {
      final name = (row['recipe_name'] as String? ?? '').toLowerCase();
      if (name.isNotEmpty) eatenRecipeNames.add(name);

      final recipeId = (row['recipe_id'] as num?)?.toInt();
      if (recipeId == null) continue;
      final recipe = RecipeService.instance.getRecipeByDbId(recipeId);
      if (recipe == null || recipe.nutrition.length < nutrKeys.length) continue;
      for (var i = 0; i < nutrKeys.length; i++) {
        consumed[nutrKeys[i]] = consumed[nutrKeys[i]]! + recipe.nutrition[i];
      }
    }

    return DailyTracker(
      user: user,
      dailyLimits: _dailyLimits(user),
      consumed: consumed,
      // Matches Python: one record_meal per cooked recipe → one increment to
      // meals_eaten. Standalone ingredient logs don't count as "meals" here.
      mealsEatenCount: cookedToday.length,
      eatenRecipeNames: eatenRecipeNames,
    );
  }

  Map<String, double> _dailyLimits(UserProfile user) {
    final rules = macroRulesByProfile[user.scoringKey] ??
        macroRulesByProfile['general_adult']!;
    final e = user.dailyCalories.toDouble();
    return {
      'calories': e,
      'total_fat_pdv':
          (e * rules.fatPctMax / 100 / 9) / DvReferences.totalFatG * 100,
      'sugar_pdv':
          (e * rules.sugarPctMax / 100 / 4) / DvReferences.sugarG * 100,
      'sodium_pdv': rules.sodiumMaxMg / DvReferences.sodiumMg * 100,
      'protein_pdv':
          (e * rules.proteinPctMin / 100 / 4) / DvReferences.proteinG * 100,
      'saturated_fat_pdv':
          (e * rules.satFatPctMax / 100 / 9) / DvReferences.saturatedFatG * 100,
      'carbs_pdv':
          (e * rules.carbsPctMax / 100 / 4) / DvReferences.carbsG * 100,
    };
  }

  bool _isDisqualified(UserProfile user, List<String> ings) {
    for (final r in user.dietaryRestrictions) {
      final keywords =
          allergyGroups[r.dbValue] ?? <String>[r.dbValue.toLowerCase()];
      for (final kw in keywords) {
        for (final i in ings) {
          if (i.contains(kw)) return true;
        }
      }
    }
    for (final avoid in user.avoidIngredients) {
      final a = avoid.toLowerCase();
      if (ings.any((i) => i.contains(a))) return true;
    }
    final hasVegetarian = user.dietaryRestrictions.contains(DietaryRestriction.vegetarian);
    final hasVegan = user.dietaryRestrictions.contains(DietaryRestriction.vegan);
    if (hasVegetarian || hasVegan) {
      final kw = hasVegan ? animalKeywords : meatKeywords;
      for (final k in kw) {
        for (final i in ings) {
          if (i.contains(k)) return true;
        }
      }
    }
    return false;
  }

  ScoredRecipe? _scoreRecipe({
    required Recipe recipe,
    required List<String> ingNames,
    required ({double ratio, List<String> matched, List<String> missing}) match,
    required Map<String, double> adaptiveLimits,
    required Map<String, double> deficits,
    required ProfileScoring scoring,
  }) {
    final nutr = recipe.nutrition;
    var score = 100.0;
    final reasons = <String>[];
    final pw = scoring.penaltyWeights;
    final bw = scoring.bonusWeights;

    // Macro penalty checks: (key, idx, base_max_penalty, label).
    const checks = [
      ['calories', NutrIdx.cal, 25.0, 'Cal'],
      ['total_fat_pdv', NutrIdx.fat, 20.0, 'Fat'],
      ['sugar_pdv', NutrIdx.sugar, 20.0, 'Sugar'],
      ['sodium_pdv', NutrIdx.sodium, 15.0, 'Na'],
      ['saturated_fat_pdv', NutrIdx.satFat, 15.0, 'SatFat'],
      ['carbs_pdv', NutrIdx.carbs, 10.0, 'Carbs'],
    ];
    for (final c in checks) {
      final key = c[0] as String;
      final idx = c[1] as int;
      final baseMp = c[2] as double;
      final lbl = c[3] as String;
      final lim = adaptiveLimits[key]!;
      final w = pw[key] ?? 1.0;
      final mp = baseMp * w;
      if (lim > 0 && nutr[idx] > lim) {
        final pen = (nutr[idx] - lim) / lim * mp * 2;
        final clamped = pen < mp ? pen : mp;
        score -= clamped;
        reasons.add('$lbl↑ ${nutr[idx].toStringAsFixed(0)}>${lim.toStringAsFixed(0)} (-${clamped.toStringAsFixed(1)})');
      }
    }

    // Protein under-target penalty.
    final pl = adaptiveLimits['protein_pdv']!;
    final protW = pw['protein_low'] ?? 1.0;
    if (nutr[NutrIdx.protein] < pl && pl > 0) {
      final raw = (pl - nutr[NutrIdx.protein]) / pl * 30 * protW;
      final cap = 15 * protW;
      final pen = raw < cap ? raw : cap;
      score -= pen;
      reasons.add('Prot↓ ${nutr[NutrIdx.protein].toStringAsFixed(0)}<${pl.toStringAsFixed(0)} (-${pen.toStringAsFixed(1)})');
    }

    // Protein recovery bonus.
    if (deficits.containsKey('protein_pdv') &&
        deficits['protein_pdv']! > 0 &&
        nutr[NutrIdx.protein] > pl) {
      final w = bw['protein_recovery'] ?? 1.0;
      final raw = pl > 0 ? (nutr[NutrIdx.protein] - pl) / pl * 15 * w : 0.0;
      final cap = 15 * w;
      final b = raw < cap ? raw : cap;
      score += b;
      reasons.add('💪Prot recovery +${b.toStringAsFixed(1)}');
    }

    // Calorie balance bonus.
    final calLim = adaptiveLimits['calories']!;
    if (deficits.containsKey('calories') &&
        deficits['calories']! < 0 &&
        nutr[NutrIdx.cal] < calLim) {
      final w = bw['calorie_balance'] ?? 1.0;
      final raw = calLim > 0 ? (calLim - nutr[NutrIdx.cal]) / calLim * 10 * w : 0.0;
      final cap = 10 * w;
      final b = raw < cap ? raw : cap;
      score += b;
      reasons.add('🔥Cal balance +${b.toStringAsFixed(1)}');
    }

    // Sugar balance bonus.
    final sugLim = adaptiveLimits['sugar_pdv'] ?? 999;
    if (deficits.containsKey('sugar_pdv') &&
        deficits['sugar_pdv']! < 0 &&
        nutr[NutrIdx.sugar] < sugLim * 0.5) {
      final w = bw['sugar_balance'] ?? 1.0;
      score += 5 * w;
      reasons.add('🍬Sugar↓ +${(5 * w).toStringAsFixed(1)}');
    }

    // Profile-specific ingredient penalties and bonuses.
    scoring.ingredientPenalties.forEach((term, penalty) {
      if (ingNames.any((i) => i.contains(term))) {
        score += penalty;
        reasons.add('⚠️$term $penalty');
      }
    });
    scoring.ingredientBonuses.forEach((term, bonus) {
      if (ingNames.any((i) => i.contains(term))) {
        score += bonus;
        reasons.add('✨$term +$bonus');
      }
    });

    // Clamp to [0, 130].
    final clamped = score < 0 ? 0.0 : (score > 130 ? 130.0 : score);

    return ScoredRecipe(
      recipe: recipe,
      score: clamped,
      matchRatio: match.ratio,
      matchedIngredients: match.matched,
      missingIngredients: match.missing,
      reasons: reasons,
      isFullMatch: match.ratio >= 0.8,
    );
  }
}
