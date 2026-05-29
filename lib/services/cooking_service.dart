import 'package:fridge_app/models/fridge_item.dart';
import 'package:fridge_app/models/recipe.dart';
import 'package:fridge_app/services/database_service.dart';
import 'package:fridge_app/services/fridge_service.dart';

/// Outcome of a single mark-cooked operation.
class CookOutcome {
  final int removedFromFridge;
  final int loggedOnly;
  const CookOutcome({required this.removedFromFridge, required this.loggedOnly});

  int get totalIngredients => removedFromFridge + loggedOnly;
}

/// Centralises the side-effects of "the user cooked / consumed this recipe":
///
/// 1. One row in `cooked_recipes` (so KB skips re-suggesting it today and
///    CF gets a clean "liked" signal — see `RecommendationService`).
/// 2. One row per ingredient in `consumption_logs`, with `is_from_fridge`
///    set to whether we found and removed a matching fridge item.
/// 3. Matched fridge items are deleted (each item can only satisfy one
///    ingredient — duplicates aren't double-counted).
///
/// Called from `recipe_preparation_guide_screen` (Mark Cooked button) and
/// `log_consumption_screen` (Recipe mode pending entries).
class CookingService {
  CookingService._();
  static final CookingService instance = CookingService._();

  Future<CookOutcome> markCooked(Recipe recipe) async {
    final db = DatabaseService.instance;
    final cookedAt = DateTime.now().millisecondsSinceEpoch;

    final dbId = _recipeDbId(recipe.id);
    if (dbId != null) {
      await db.insert('cooked_recipes', {
        'recipe_id': dbId,
        'recipe_name': recipe.title,
        'cooked_at': cookedAt,
      });
    }

    final fridgeItems = FridgeService.instance.getAllItems();
    final claimed = <String>{};
    int removedFromFridge = 0;
    int loggedOnly = 0;

    for (final ing in recipe.ingredients) {
      FridgeItem? match;
      for (final item in fridgeItems) {
        if (claimed.contains(item.id)) continue;
        if (_ingredientMatchesFridgeItem(ing.name, item.name)) {
          match = item;
          break;
        }
      }
      final fromFridge = match != null;
      if (fromFridge) {
        claimed.add(match.id);
        await FridgeService.instance.deleteItemById(match.id);
        removedFromFridge++;
      } else {
        loggedOnly++;
      }
      await db.logConsumption(
        itemName: ing.name,
        category: 'recipe:${recipe.title}',
        amount: 1.0,
        unit: 'serving',
        isFromFridge: fromFridge,
      );
    }

    await FridgeService.instance.refreshFromDb();
    return CookOutcome(
      removedFromFridge: removedFromFridge,
      loggedOnly: loggedOnly,
    );
  }

  /// Deliberately lenient — accepts substring overlap in either direction
  /// plus any shared word (≥3 chars). Mark-cooked is a user-driven action;
  /// over-matching is friendlier than under-matching here (the user told us
  /// they cooked the recipe; we want to consume from the fridge whenever
  /// reasonable). The strict matcher in KbRecommenderService stays strict
  /// because *suggesting* recipes has the opposite cost balance.
  bool _ingredientMatchesFridgeItem(String ingredientName, String fridgeName) {
    final ingredient = ingredientName.toLowerCase();
    final item = fridgeName.toLowerCase();
    if (ingredient.contains(item) || item.contains(ingredient)) return true;
    final ingredientWords = ingredient
        .split(RegExp(r'\s+'))
        .where((word) => word.length > 2)
        .toSet();
    final itemWords = item
        .split(RegExp(r'\s+'))
        .where((word) => word.length > 2)
        .toSet();
    return ingredientWords.any(itemWords.contains);
  }

  int? _recipeDbId(String id) {
    if (!id.startsWith('db_')) return null;
    return int.tryParse(id.substring(3));
  }
}
