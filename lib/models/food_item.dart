/// Model for individual food items from the daily_food_nutrition_dataset.
class FoodItem {
  final int? id;
  final String name;
  final String category;
  final double calories;
  final double protein;
  final double carbs;
  final double fat;
  final double fiber;
  final double sugars;
  final double sodium;
  final double cholesterol;
  final String mealType;

  const FoodItem({
    this.id,
    required this.name,
    required this.category,
    this.calories = 0,
    this.protein = 0,
    this.carbs = 0,
    this.fat = 0,
    this.fiber = 0,
    this.sugars = 0,
    this.sodium = 0,
    this.cholesterol = 0,
    this.mealType = '',
  });

  Map<String, dynamic> toMap() {
    return {
      if (id != null) 'id': id,
      'name': name,
      'category': category,
      'calories': calories,
      'protein': protein,
      'carbs': carbs,
      'fat': fat,
      'fiber': fiber,
      'sugars': sugars,
      'sodium': sodium,
      'cholesterol': cholesterol,
      'meal_type': mealType,
    };
  }

  factory FoodItem.fromMap(Map<String, dynamic> map) {
    return FoodItem(
      id: map['id'] as int?,
      name: map['name'] as String? ?? '',
      category: map['category'] as String? ?? '',
      calories: (map['calories'] as num?)?.toDouble() ?? 0,
      protein: (map['protein'] as num?)?.toDouble() ?? 0,
      carbs: (map['carbs'] as num?)?.toDouble() ?? 0,
      fat: (map['fat'] as num?)?.toDouble() ?? 0,
      fiber: (map['fiber'] as num?)?.toDouble() ?? 0,
      sugars: (map['sugars'] as num?)?.toDouble() ?? 0,
      sodium: (map['sodium'] as num?)?.toDouble() ?? 0,
      cholesterol: (map['cholesterol'] as num?)?.toDouble() ?? 0,
      mealType: map['meal_type'] as String? ?? '',
    );
  }

  @override
  String toString() =>
      'FoodItem(name: $name, cal: $calories, protein: $protein)';
}
