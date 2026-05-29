import 'package:flutter/foundation.dart';
import 'package:fridge_app/models/meal_type.dart';
import 'package:fridge_app/models/recipe.dart';
import 'package:fridge_app/models/user_profile.dart';
import 'package:fridge_app/services/database_service.dart';
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
}

/// Aggregate of what the user has eaten today, used to compute adaptive
/// per-meal limits and deficits.
class _DailyTracker {
  final UserProfile user;
  final Map<String, double> dailyLimits;
  final Map<String, double> consumed;
  final int mealsEatenCount;
  final Set<String> eatenRecipeNames;

  _DailyTracker({
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

  /// (daily_limit - consumed) / remaining_meals — what's left to spend on the
  /// next meal.
  Map<String, double> adaptiveMealLimits() {
    final n = mealsRemaining;
    return {
      for (final k in nutrKeys) k: (dailyLimits[k]! - consumed[k]!) / n,
    };
  }

  /// Pace deficits per macro: how far off the ideal per-meal trajectory the
  /// user is. Only returns non-zero entries in directions that matter
  /// (protein under-pace, everything else over-pace).
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
}

class KbRecommenderService {
  KbRecommenderService._();
  static final KbRecommenderService instance = KbRecommenderService._();

  /// Returns up to 5 ranked recipe recommendations for the current user given
  /// the current fridge contents and today's consumption history. Slot
  /// allocation: 3 full-match (>=80% ingredients) + 2 partial (30-80%).
  /// Returns empty if no profile is set.
  Future<List<ScoredRecipe>> recommend({
    int limit = 5,
    MealType mealType = MealType.all,
  }) async {
    final sw = Stopwatch()..start();
    final user = UserProfileService.instance.current;
    if (user == null) {
      debugPrint('[KB] No user profile saved — returning empty.');
      return [];
    }

    final tracker = await _buildTrackerFromToday(user);
    final fridge = FridgeService.instance
        .getAllItems()
        .map((i) => i.name.toLowerCase())
        .toList();
    final adaptiveLimits = tracker.adaptiveMealLimits();
    final deficits = tracker.deficits();
    final scoring = profileScoring[user.profileKey.dbValue] ??
        profileScoring['general_adult']!;

    final fullMatch = <ScoredRecipe>[];
    final partialMatch = <ScoredRecipe>[];
    int considered = 0;
    int mealMissed = 0;
    int prefiltered = 0;
    int disqualified = 0;

    for (final recipe in RecipeService.instance.allRecipes) {
      if (recipe.nutrition.length < 7) continue;
      // Meal-of-day filter is the cheapest check (string compare on tags),
      // so run it before ingredient tokenization.
      if (!mealType.matches(recipe.tags)) {
        mealMissed++;
        continue;
      }
      final ingNames = recipe.ingredients.map((i) => i.name.toLowerCase()).toList();
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
      if (tracker.eatenRecipeNames.contains(recipe.title.toLowerCase())) continue;

      final scored = _scoreRecipe(
        recipe: recipe,
        ingNames: ingNames,
        match: match,
        adaptiveLimits: adaptiveLimits,
        deficits: deficits,
        scoring: scoring,
      );
      if (scored == null) continue;

      if (scored.isFullMatch) {
        fullMatch.add(scored);
      } else {
        partialMatch.add(scored);
      }
    }
    sw.stop();
    debugPrint(
      '[KB] profile=${user.profileKey.dbValue} meal=${mealType.name} '
      'fridge=${fridge.length} recipes=$considered '
      'mealMissed=$mealMissed prefiltered=$prefiltered '
      'disqualified=$disqualified full=${fullMatch.length} '
      'partial=${partialMatch.length} took=${sw.elapsedMilliseconds}ms',
    );

    int cmp(ScoredRecipe a, ScoredRecipe b) {
      final s = b.score.compareTo(a.score);
      if (s != 0) return s;
      return b.matchRatio.compareTo(a.matchRatio);
    }

    fullMatch.sort(cmp);
    partialMatch.sort(cmp);

    final result = <ScoredRecipe>[];
    result.addAll(fullMatch.take(3));
    final partialNeeded = limit - result.length;
    if (partialNeeded > 0) {
      result.addAll(partialMatch.take(partialNeeded));
    }
    if (result.length < limit) {
      final overflow = limit - result.length;
      result.addAll(fullMatch.skip(3).take(overflow));
    }
    return result.take(limit).toList();
  }

  /// Ingredient match: fraction of recipe ingredients "covered" by fridge.
  ///
  /// A recipe ingredient is **covered** by a fridge entry when *every* token
  /// in the recipe ingredient appears in that fridge entry's tokens. Tokens
  /// are matched with exact equality plus simple plural tolerance (`+s`,
  /// `+es`) — `tomato` still pairs with `tomatoes`, but `broccoli soup` no
  /// longer pairs with `broccoli` because the fridge entry doesn't contribute
  /// a `soup` token. Tokenization strips parens, units (`cup`, `tbsp`, …),
  /// prep verbs (`grilled`, `steamed`, …), and tokens under 3 chars.
  static ({double ratio, List<String> matched, List<String> missing})
      ingredientMatch(List<String> fridge, List<String> ingredients) {
    if (ingredients.isEmpty) return (ratio: 0, matched: const [], missing: const []);
    final fridgeTokens = fridge.map(_tokenize).toList(growable: false);
    final matched = <String>[];
    final missing = <String>[];
    for (final ing in ingredients) {
      final ingTokens = _tokenize(ing);
      // An ingredient that tokenizes to nothing (e.g. "1 cup") can't be
      // matched meaningfully — count it missing rather than a free hit.
      if (ingTokens.isEmpty) {
        missing.add(ing);
        continue;
      }
      final hit = fridgeTokens.any((ft) => _coversAll(ft, ingTokens));
      (hit ? matched : missing).add(ing);
    }
    return (
      ratio: matched.length / ingredients.length,
      matched: matched,
      missing: missing,
    );
  }

  /// Tokens worth comparing — at least 3 letters and not a stop-word.
  static Set<String> _tokenize(String raw) {
    final clean = raw.toLowerCase().replaceAll(RegExp(r'\([^)]*\)'), ' ');
    return clean
        .split(RegExp(r'[^a-z]+'))
        .where((t) => t.length >= 3 && !_stopWords.contains(t))
        .toSet();
  }

  /// True when every token in `needle` is covered by some token in `haystack`
  /// (exact match or `+s` / `+es` plural).
  static bool _coversAll(Set<String> haystack, Set<String> needle) {
    for (final n in needle) {
      var found = false;
      for (final h in haystack) {
        if (_tokenCovers(h, n)) {
          found = true;
          break;
        }
      }
      if (!found) return false;
    }
    return true;
  }

  static bool _tokenCovers(String haystackToken, String needleToken) {
    if (haystackToken == needleToken) return true;
    // Plural tolerance only — avoids accidentally pairing things like
    // "saltwater" with "salt".
    if (haystackToken == '${needleToken}s' ||
        haystackToken == '${needleToken}es') {
      return true;
    }
    if (needleToken == '${haystackToken}s' ||
        needleToken == '${haystackToken}es') {
      return true;
    }
    return false;
  }

  static const Set<String> _stopWords = {
    // articles / connectors
    'and', 'the', 'for', 'with', 'into', 'plus',
    // common units
    'cup', 'cups', 'tbsp', 'tsp', 'oz', 'lb', 'lbs',
    'gram', 'grams', 'ml', 'liter', 'liters', 'slice', 'slices',
    'piece', 'pieces', 'pack', 'large', 'small', 'medium',
    // prep verbs / adjectives that aren't the ingredient
    'cooked', 'raw', 'fresh', 'frozen', 'dried', 'ground',
    'chopped', 'diced', 'minced', 'sliced', 'grilled', 'steamed',
    'baked', 'boiled', 'roasted', 'whole', 'plain', 'black',
  };

  // ── internals ────────────────────────────────────────────────────

  Future<_DailyTracker> _buildTrackerFromToday(UserProfile user) async {
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

    return _DailyTracker(
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
    final rules = macroRulesByProfile[user.profileKey.dbValue] ??
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
