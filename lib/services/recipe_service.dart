import 'package:fridge_app/models/recipe.dart';
import 'package:fridge_app/services/database_service.dart';
import 'package:fridge_app/services/fridge_service.dart';

/// Service to manage recipe data and matching logic.
///
/// Loads recipes from the local SQLite database (imported from RAW_recipes_filtered.csv).
/// Also keeps the 4 original hand-crafted sample recipes (which have step images).
class RecipeService {
  // Singleton
  RecipeService._();
  static final RecipeService instance = RecipeService._();

  bool _isInitialized = false;
  final List<Recipe> _recipes = [];
  Future<void>? _readyFuture;

  // ── Initialization ──────────────────────────────────────────────

  /// Completes once the recipe cache is loaded. Screens that need the cache
  /// should await this instead of assuming `initialize()` already ran — it's
  /// scheduled off the startup critical path to keep first paint fast.
  Future<void> get ready => _readyFuture ?? initialize();

  Future<void> initialize() async {
    if (_isInitialized) return _readyFuture ?? Future.value();
    _isInitialized = true;
    _readyFuture = _loadFromDb();
    return _readyFuture!;
  }

  /// Load every recipe + its ingredients + its steps in three queries total
  /// (instead of one query per recipe × 2 sub-queries). Cuts cold-start from
  /// tens of seconds to well under one second on ~20k rows.
  Future<void> _loadFromDb() async {
    final dbService = DatabaseService.instance;
    final results = await Future.wait([
      dbService.queryAll('recipes'),
      dbService.queryAll('recipe_ingredients'),
      dbService.queryWhere('recipe_steps', orderBy: 'recipe_id ASC, step_number ASC'),
    ]);
    final recipeRows = results[0];
    final ingRows = results[1];
    final stepRows = results[2];

    final ingsByRecipe = <int, List<RecipeIngredient>>{};
    for (final r in ingRows) {
      final rid = r['recipe_id'] as int?;
      if (rid == null) continue;
      (ingsByRecipe[rid] ??= <RecipeIngredient>[]).add(
        RecipeIngredient(name: r['name'] as String? ?? '', amount: ''),
      );
    }

    final stepsByRecipe = <int, List<RecipeStep>>{};
    for (final s in stepRows) {
      final rid = s['recipe_id'] as int?;
      if (rid == null) continue;
      (stepsByRecipe[rid] ??= <RecipeStep>[]).add(
        RecipeStep(
          stepNumber: (s['step_number'] as int?) ?? 0,
          title: 'Step ${s['step_number']}',
          description: s['description'] as String? ?? '',
        ),
      );
    }

    for (final row in recipeRows) {
      final recipeId = row['id'] as int;
      final nutritionValues = _parseNutritionArray(row['nutrition'] as String? ?? '');
      final caloriesVal = nutritionValues.isNotEmpty ? nutritionValues[0] : 0.0;
      final tags = _parseTags(row['tags'] as String? ?? '');

      _recipes.add(Recipe(
        id: 'db_$recipeId',
        title: _titleCase(row['name'] as String? ?? ''),
        description: '',
        prepTime: '${row['minutes'] ?? 0} min',
        calories: '${caloriesVal.round()} kcal',
        type: _inferType(tags),
        servings: 1,
        tags: tags.take(5).toList(),
        ingredients: ingsByRecipe[recipeId] ?? const [],
        steps: stepsByRecipe[recipeId] ?? const [],
        nutrition: nutritionValues,
      ));
    }
  }

  // ── Public API (unchanged) ──────────────────────────────────────

  /// Returns all recipes, calculating missing ingredients based on current fridge inventory.
  List<Recipe> getSuggestedRecipes() {
    final fridgeItems = FridgeService.instance.getAllItems();
    final fridgeItemNames = fridgeItems.map((i) => i.name.toLowerCase()).toSet();

    return _recipes.map((recipe) {
      final missing = <String>[];
      for (final ingredient in recipe.ingredients) {
        bool found = false;
        final ingLower = ingredient.name.toLowerCase();
        if (fridgeItemNames.any(
          (name) => name.contains(ingLower) || ingLower.contains(name),
        )) {
          found = true;
        }
        if (!found) {
          missing.add(ingredient.name);
        }
      }
      return recipe.copyWith(missingIngredients: missing);
    }).toList();
  }

  Recipe? getRecipeById(String id) {
    try {
      final allWithMissing = getSuggestedRecipes();
      return allWithMissing.firstWhere((r) => r.id == id);
    } catch (_) {
      return null;
    }
  }

  /// Get total recipe count.
  int get recipeCount => _recipes.length;

  /// All loaded recipes (sample + DB). Unmodifiable. Used by the KB recommender.
  List<Recipe> get allRecipes => List.unmodifiable(_recipes);

  Recipe? getRecipeByDbId(int dbId) {
    try {
      return _recipes.firstWhere((r) => r.id == 'db_$dbId');
    } catch (_) {
      return null;
    }
  }

  // ── Private helpers ─────────────────────────────────────────────

  List<double> _parseNutritionArray(String raw) {
    if (raw.isEmpty) return [];
    var s = raw.trim();
    if (s.startsWith('[')) s = s.substring(1);
    if (s.endsWith(']')) s = s.substring(0, s.length - 1);
    return s.split(',').map((e) => double.tryParse(e.trim()) ?? 0).toList();
  }

  List<String> _parseTags(String raw) {
    if (raw.isEmpty) return [];
    var s = raw.trim();
    if (s.startsWith('[')) s = s.substring(1);
    if (s.endsWith(']')) s = s.substring(0, s.length - 1);
    return s
        .split(',')
        .map((t) => t.trim().replaceAll("'", '').replaceAll('"', ''))
        .where((t) => t.isNotEmpty)
        .toList();
  }

  String _titleCase(String s) {
    if (s.isEmpty) return s;
    return s.split(' ').map((word) {
      if (word.isEmpty) return word;
      return word[0].toUpperCase() + word.substring(1);
    }).join(' ');
  }

  String _inferType(List<String> tags) {
    final tagSet = tags.map((t) => t.toLowerCase()).toSet();
    if (tagSet.contains('italian')) return 'Italian';
    if (tagSet.contains('asian') || tagSet.contains('chinese') || tagSet.contains('japanese')) return 'Asian';
    if (tagSet.contains('mexican')) return 'Mexican';
    if (tagSet.contains('indian')) return 'Indian';
    if (tagSet.contains('desserts')) return 'Dessert';
    if (tagSet.contains('breakfast')) return 'Breakfast';
    if (tagSet.contains('beverages')) return 'Beverage';
    if (tagSet.contains('salad')) return 'Salad';
    if (tagSet.contains('north-american') || tagSet.contains('american')) return 'American';
    return 'General';
  }
}
