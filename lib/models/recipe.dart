/// Ingredient requirement for a recipe.
class RecipeIngredient {
  final String name;
  final String amount;

  const RecipeIngredient({required this.name, required this.amount});

  Map<String, dynamic> toMap() => {'name': name, 'amount': amount};

  factory RecipeIngredient.fromMap(Map<String, dynamic> map) {
    return RecipeIngredient(
      name: map['name'] as String,
      amount: map['amount'] as String,
    );
  }
}

/// A step in the recipe preparation instructions.
class RecipeStep {
  final int stepNumber;
  final String title;
  final String description;
  final String? imageUrl;

  const RecipeStep({
    required this.stepNumber,
    required this.title,
    required this.description,
    this.imageUrl,
  });

  Map<String, dynamic> toMap() => {
    'stepNumber': stepNumber,
    'title': title,
    'description': description,
    'imageUrl': imageUrl,
  };

  factory RecipeStep.fromMap(Map<String, dynamic> map) {
    return RecipeStep(
      stepNumber: map['stepNumber'] as int,
      title: map['title'] as String,
      description: map['description'] as String,
      imageUrl: map['imageUrl'] as String?,
    );
  }
}

/// Comprehensive recipe model for the application.
class Recipe {
  final String id;
  final String title;
  final String description;
  final String? imageUrl;
  final double rating;
  final int ratingCount;
  final String prepTime;
  final String calories;
  final String type; // e.g. 'Italian', 'Salad'
  final int servings;
  final List<String> tags; // e.g. 'Vegetarian', 'Gluten-Free'

  // Ingredients with amounts for display
  final List<RecipeIngredient> ingredients;

  // Instructions
  final List<RecipeStep> steps;

  // Computed / Logic
  final List<String> missingIngredients; // Names of missing items

  const Recipe({
    required this.id,
    required this.title,
    this.description = '',
    this.imageUrl,
    this.rating = 0.0,
    this.ratingCount = 0,
    this.prepTime = '',
    this.calories = '',
    this.type = '',
    this.servings = 1,
    this.tags = const [],
    this.ingredients = const [],
    this.steps = const [],
    this.missingIngredients = const [],
  });

  // ── Computed ─────────────────────────────────────────────────────

  /// Whether the user has all ingredients for this recipe.
  bool get hasAllIngredients => missingIngredients.isEmpty;

  /// Match percentage: how many ingredients are available.
  double get matchPercentage {
    if (ingredients.isEmpty) return 1.0;
    final available = ingredients.length - missingIngredients.length;
    return available / ingredients.length;
  }

  // ── Serialization ────────────────────────────────────────────────

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'title': title,
      'description': description,
      'imageUrl': imageUrl,
      'rating': rating,
      'ratingCount': ratingCount,
      'prepTime': prepTime,
      'calories': calories,
      'type': type,
      'servings': servings,
      'tags': tags,
      'ingredients': ingredients.map((x) => x.toMap()).toList(),
      'steps': steps.map((x) => x.toMap()).toList(),
      'missingIngredients': missingIngredients,
    };
  }

  factory Recipe.fromMap(Map<String, dynamic> map) {
    return Recipe(
      id: map['id'] as String,
      title: map['title'] as String,
      description: map['description'] as String? ?? '',
      imageUrl: map['imageUrl'] as String?,
      rating: (map['rating'] as num?)?.toDouble() ?? 0.0,
      ratingCount: (map['ratingCount'] as num?)?.toInt() ?? 0,
      prepTime: map['prepTime'] as String? ?? '',
      calories: map['calories'] as String? ?? '',
      type: map['type'] as String? ?? '',
      servings: (map['servings'] as num?)?.toInt() ?? 1,
      tags: List<String>.from(map['tags'] ?? []),
      ingredients:
          (map['ingredients'] as List<dynamic>?)
              ?.map((x) => RecipeIngredient.fromMap(x as Map<String, dynamic>))
              .toList() ??
          [],
      steps:
          (map['steps'] as List<dynamic>?)
              ?.map((x) => RecipeStep.fromMap(x as Map<String, dynamic>))
              .toList() ??
          [],
      missingIngredients: List<String>.from(map['missingIngredients'] ?? []),
    );
  }

  Recipe copyWith({
    String? id,
    String? title,
    String? description,
    String? imageUrl,
    double? rating,
    int? ratingCount,
    String? prepTime,
    String? calories,
    String? type,
    int? servings,
    List<String>? tags,
    List<RecipeIngredient>? ingredients,
    List<RecipeStep>? steps,
    List<String>? missingIngredients,
  }) {
    return Recipe(
      id: id ?? this.id,
      title: title ?? this.title,
      description: description ?? this.description,
      imageUrl: imageUrl ?? this.imageUrl,
      rating: rating ?? this.rating,
      ratingCount: ratingCount ?? this.ratingCount,
      prepTime: prepTime ?? this.prepTime,
      calories: calories ?? this.calories,
      type: type ?? this.type,
      servings: servings ?? this.servings,
      tags: tags ?? this.tags,
      ingredients: ingredients ?? this.ingredients,
      steps: steps ?? this.steps,
      missingIngredients: missingIngredients ?? this.missingIngredients,
    );
  }

  @override
  String toString() =>
      'Recipe(id: $id, title: $title, match: ${(matchPercentage * 100).round()}%)';
}
