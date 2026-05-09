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

  // ── Hand-crafted sample recipes with images ───────────────────────

  static const List<Recipe> _sampleRecipes = [
    Recipe(
      id: 'recipe_001',
      title: 'Fresh Basil Pesto Pasta',
      description:
          'A quick and aromatic pasta dish utilizing that fresh basil sitting in your crisper drawer. Perfect for a light dinner.',
      imageUrl: 'assets/images/pesto_pasta.png',
      rating: 4.8,
      ratingCount: 120,
      prepTime: '25 min',
      calories: '420 kcal',
      type: 'Italian',
      servings: 4,
      tags: ['Vegetarian', 'Quick'],
      ingredients: [
        RecipeIngredient(name: 'Fresh Basil', amount: '2 cups, packed'),
        RecipeIngredient(name: 'Parmesan Cheese', amount: '1/2 cup, grated'),
        RecipeIngredient(name: 'Pine Nuts', amount: '1/3 cup'),
        RecipeIngredient(name: 'Garlic Cloves', amount: '3 large cloves'),
        RecipeIngredient(name: 'Extra Virgin Olive Oil', amount: '1/2 cup'),
        RecipeIngredient(name: 'Pasta', amount: '1 lb'),
      ],
      steps: [
        RecipeStep(
          stepNumber: 1, title: 'Toast the nuts',
          description: 'In a small skillet over medium-low heat, toast the pine nuts, stirring often, until fragrant and golden, about 3 to 5 minutes.',
          imageUrl: 'https://lh3.googleusercontent.com/aida-public/AB6AXuCAalnXGC0OWdAThN8GDvz_vgIhgPcQDu4ik0hheIJNZ4WZMY2cHi79JYS5lRIn5sQq6pmSemf9iasEjr7qc5VZm3oMOFvg7NyBHhAuP4OXNEZe9YBzx-j2MG12XViLP7WNROCYny7RW21NWztR1gGJClAvZH9woQYj_8ojBnzA3ZHXUyD6LOHNimDpUCLht6Feb7CZ9SIWYT9ci5MOkLVqNOPuMIq1tDtEOTHYUqdL46fqfd34I7Yyxd0zRB77E8_4qjH98e61yZBG',
        ),
        RecipeStep(
          stepNumber: 2, title: 'Blend ingredients',
          description: 'Combine basil, garlic, and cooled pine nuts in a food processor. Pulse a few times until coarsely chopped.',
          imageUrl: 'https://lh3.googleusercontent.com/aida-public/AB6AXuAnDt84rtHEOSWF9ZG8IQ8BAijqrzEiAkSzuGwMhgAuBITyQFhDQgJ1FT6ZRLd8p_a1ntid_uhrsW2arhlbXkSvd8vIlXqhgupDnp_amh2lNvTxHroMJ2JAX0xccJqHZ8WRSAjOd3uTkNWOY-_PLGNA-7RR85YNkaXzM1wBIWdtrTwseqBp1u5uphVImHnScdtvT7oMpyPOV2UCAoKTN7kIyfjLHj4L6TJKYU5RzlSK54RVI3H3yvMjxB3x1ulmcEvyo5aC1RPddDlo',
        ),
        RecipeStep(stepNumber: 3, title: 'Add oil and cheese', description: 'With the motor running, slowly stream in the olive oil. Add the parmesan cheese and pulse just until combined.'),
        RecipeStep(stepNumber: 4, title: 'Toss with pasta', description: 'Cook pasta according to package instructions. Reserve 1/2 cup cooking water. Toss pasta with pesto.'),
      ],
    ),
    Recipe(
      id: 'recipe_002',
      title: 'Spicy Chicken Stir-fry',
      description: 'A vibrant stir-fry with tender chicken and fresh vegetables.',
      imageUrl: 'assets/images/chicken_stir_fry.png',
      rating: 4.5, ratingCount: 85, prepTime: '30 min', calories: '550 kcal',
      type: 'Asian', servings: 2, tags: ['Spicy', 'High Protein'],
      ingredients: [
        RecipeIngredient(name: 'Chicken Breast', amount: '2 breasts'),
        RecipeIngredient(name: 'Bell Peppers', amount: '2 sliced'),
        RecipeIngredient(name: 'Soy Sauce', amount: '3 tbsp'),
        RecipeIngredient(name: 'Garlic', amount: '2 cloves'),
        RecipeIngredient(name: 'Ginger', amount: '1 tbsp minced'),
      ],
      steps: [
        RecipeStep(stepNumber: 1, title: 'Prep', description: 'Slice chicken and vegetables.'),
        RecipeStep(stepNumber: 2, title: 'Cook Chicken', description: 'Stir-fry chicken until golden.'),
        RecipeStep(stepNumber: 3, title: 'Add Veggies', description: 'Add vegetables to the pan.'),
        RecipeStep(stepNumber: 4, title: 'Sauce', description: 'Pour in soy sauce mixture and toss.'),
      ],
    ),
    Recipe(
      id: 'recipe_003',
      title: 'Avocado & Kale Salad',
      description: 'A fresh and healthy salad to use up your avocados and kale.',
      imageUrl: 'assets/images/avocado_salad.png',
      rating: 4.6, ratingCount: 42, prepTime: '10 min', calories: '280 kcal',
      type: 'Salad', servings: 2, tags: ['Healthy', 'Vegetarian', 'Gluten-Free'],
      ingredients: [
        RecipeIngredient(name: 'Kale', amount: '1 bunch'),
        RecipeIngredient(name: 'Organic Avocados', amount: '1 ripe'),
        RecipeIngredient(name: 'Lemon Juice', amount: '2 tbsp'),
        RecipeIngredient(name: 'Olive Oil', amount: '1 tbsp'),
      ],
      steps: [
        RecipeStep(stepNumber: 1, title: 'Massage Kale', description: 'Massage kale with olive oil.'),
        RecipeStep(stepNumber: 2, title: 'Add Avocado', description: 'Dice avocado and add to bowl.'),
        RecipeStep(stepNumber: 3, title: 'Dress', description: 'Drizzle with lemon juice and serve.'),
      ],
    ),
    Recipe(
      id: 'recipe_004',
      title: 'Homemade Flatbread Pizza',
      description: 'Quick pizza using simple ingredients.',
      imageUrl: 'assets/images/pizza.png',
      rating: 4.9, ratingCount: 200, prepTime: '25 min', calories: '600 kcal',
      type: 'Dinner', servings: 2, tags: ['Comfort Food'],
      ingredients: [
        RecipeIngredient(name: 'Sourdough Bread', amount: '2 slices'),
        RecipeIngredient(name: 'Cherry Tomatoes', amount: '1 cup'),
        RecipeIngredient(name: 'Cheddar Cheese', amount: '1 cup shredded'),
        RecipeIngredient(name: 'Fresh Basil', amount: 'Few leaves'),
      ],
      steps: [
        RecipeStep(stepNumber: 1, title: 'Toppings', description: 'Top bread with cheese and tomatoes.'),
        RecipeStep(stepNumber: 2, title: 'Bake', description: 'Bake at 400F for 10-15 mins.'),
        RecipeStep(stepNumber: 3, title: 'Garnish', description: 'Add fresh basil before serving.'),
      ],
    ),
  ];

  // ── Initialization ──────────────────────────────────────────────

  Future<void> initialize() async {
    if (_isInitialized) return;
    _isInitialized = true;

    // Start with sample recipes (they have images)
    _recipes.addAll(_sampleRecipes);

    // Load DB recipes
    await _loadFromDb();
  }

  Future<void> _loadFromDb() async {
    final dbService = DatabaseService.instance;
    final recipeRows = await dbService.queryAll('recipes');

    for (final row in recipeRows) {
      final recipeId = row['id'] as int;

      // Load ingredients
      final ingRows = await dbService.queryWhere(
        'recipe_ingredients',
        where: 'recipe_id = ?',
        whereArgs: [recipeId],
      );
      final ingredients = ingRows
          .map((r) => RecipeIngredient(name: r['name'] as String? ?? '', amount: ''))
          .toList();

      // Load steps
      final stepRows = await dbService.queryWhere(
        'recipe_steps',
        where: 'recipe_id = ?',
        whereArgs: [recipeId],
        orderBy: 'step_number ASC',
      );
      final steps = stepRows
          .map((r) => RecipeStep(
                stepNumber: (r['step_number'] as int?) ?? 0,
                title: 'Step ${r['step_number']}',
                description: r['description'] as String? ?? '',
              ))
          .toList();

      // Parse nutrition: [calories, totalFat%DV, sugar%DV, sodium%DV, protein%DV, satFat%DV, carbs%DV]
      final nutritionStr = row['nutrition'] as String? ?? '';
      final nutritionValues = _parseNutritionArray(nutritionStr);
      final caloriesVal = nutritionValues.isNotEmpty ? nutritionValues[0] : 0.0;

      // Parse tags for type/dietary info
      final tagsStr = row['tags'] as String? ?? '';
      final tags = _parseTags(tagsStr);

      _recipes.add(Recipe(
        id: 'db_$recipeId',
        title: _titleCase(row['name'] as String? ?? ''),
        description: '',
        prepTime: '${row['minutes'] ?? 0} min',
        calories: '${caloriesVal.round()} kcal',
        type: _inferType(tags),
        servings: 1,
        tags: tags.take(5).toList(),
        ingredients: ingredients,
        steps: steps,
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
