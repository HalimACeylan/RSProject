/// WHO/dataset-derived constants for the KB recommender.
/// Mirrors `datasets_to_use/who_daily_nutrient_guidelines.json` so the Dart KB
/// and the Python CF service score against the same reference.
library;

class DvReferences {
  static const double totalFatG = 78;
  static const double sugarG = 50;
  static const double sodiumMg = 2300;
  static const double proteinG = 50;
  static const double saturatedFatG = 20;
  static const double carbsG = 275;
}

class MacroRules {
  final double fatPctMax;
  final double sugarPctMax;
  final double sodiumMaxMg;
  final double proteinPctMin;
  final double satFatPctMax;
  final double carbsPctMax;
  const MacroRules({
    required this.fatPctMax,
    required this.sugarPctMax,
    required this.sodiumMaxMg,
    required this.proteinPctMin,
    required this.satFatPctMax,
    required this.carbsPctMax,
  });
}

/// Nutrition array indices.
class NutrIdx {
  static const int cal = 0;
  static const int fat = 1;
  static const int sugar = 2;
  static const int sodium = 3;
  static const int protein = 4;
  static const int satFat = 5;
  static const int carbs = 6;
}

const List<String> nutrKeys = [
  'calories',
  'total_fat_pdv',
  'sugar_pdv',
  'sodium_pdv',
  'protein_pdv',
  'saturated_fat_pdv',
  'carbs_pdv',
];

const Map<String, MacroRules> macroRulesByProfile = {
  'general_adult': MacroRules(
    fatPctMax: 30, sugarPctMax: 10, sodiumMaxMg: 2000,
    proteinPctMin: 15, satFatPctMax: 10, carbsPctMax: 60,
  ),
  'athlete_bodybuilder': MacroRules(
    fatPctMax: 30, sugarPctMax: 10, sodiumMaxMg: 2300,
    proteinPctMin: 25, satFatPctMax: 10, carbsPctMax: 55,
  ),
  'adolescent': MacroRules(
    fatPctMax: 30, sugarPctMax: 10, sodiumMaxMg: 1900,
    proteinPctMin: 18, satFatPctMax: 10, carbsPctMax: 60,
  ),
  // 'pregnant' isn't a separate `profile_key` value any more — UserProfile
  // exposes `scoringKey` which returns 'pregnant' when isPregnant is true,
  // regardless of profile_key. The rule-set stays here so KB can look it up.
  'pregnant': MacroRules(
    fatPctMax: 30, sugarPctMax: 10, sodiumMaxMg: 1800,
    proteinPctMin: 20, satFatPctMax: 10, carbsPctMax: 60,
  ),
};

class ProfileScoring {
  final Map<String, double> penaltyWeights;
  final Map<String, double> bonusWeights;
  final Map<String, double> ingredientPenalties;
  final Map<String, double> ingredientBonuses;
  const ProfileScoring({
    required this.penaltyWeights,
    required this.bonusWeights,
    required this.ingredientPenalties,
    required this.ingredientBonuses,
  });
}

/// Verbatim port of PROFILE_SCORING from test_kb_recommendations.py.
/// 'pregnant' is looked up via [UserProfile.scoringKey] when isPregnant is
/// true, otherwise the profile_key value is used directly.
const Map<String, ProfileScoring> profileScoring = {
  'general_adult': ProfileScoring(
    penaltyWeights: {
      'calories': 1.0, 'total_fat_pdv': 1.0, 'sugar_pdv': 1.2,
      'sodium_pdv': 1.0, 'protein_low': 0.8, 'saturated_fat_pdv': 1.0, 'carbs_pdv': 0.8,
    },
    bonusWeights: {
      'protein_recovery': 0.8, 'calorie_balance': 1.0, 'sugar_balance': 1.0,
    },
    ingredientPenalties: {
      'fatty meat': -5, 'butter': -3, 'cream': -3, 'lard': -5,
      'palm oil': -4, 'coconut oil': -3, 'ghee': -4,
    },
    ingredientBonuses: {
      'vegetables': 3, 'fruits': 2, 'whole grains': 3, 'fish': 2,
      'olive oil': 2, 'nuts': 2,
    },
  ),
  'athlete_bodybuilder': ProfileScoring(
    penaltyWeights: {
      'calories': 0.6, 'total_fat_pdv': 0.8, 'sugar_pdv': 1.5,
      'sodium_pdv': 0.7, 'protein_low': 2.0, 'saturated_fat_pdv': 1.0, 'carbs_pdv': 0.5,
    },
    bonusWeights: {
      'protein_recovery': 2.0, 'calorie_balance': 0.5, 'sugar_balance': 1.2,
    },
    ingredientPenalties: {
      'fatty meat': -2, 'butter': -3, 'cream': -4, 'lard': -5,
      'sugar': -5, 'candy': -8, 'soda': -8, 'syrup': -4,
    },
    ingredientBonuses: {
      'chicken': 5, 'salmon': 5, 'egg': 4, 'fish': 5,
      'broccoli': 3, 'spinach': 3, 'oats': 3, 'rice': 2,
      'sweet potato': 3, 'avocado': 3, 'nuts': 2,
    },
  ),
  'adolescent': ProfileScoring(
    penaltyWeights: {
      'calories': 0.8, 'total_fat_pdv': 1.0, 'sugar_pdv': 1.5,
      'sodium_pdv': 1.2, 'protein_low': 1.5, 'saturated_fat_pdv': 1.2, 'carbs_pdv': 0.7,
    },
    bonusWeights: {
      'protein_recovery': 1.5, 'calorie_balance': 0.8, 'sugar_balance': 1.5,
    },
    ingredientPenalties: {
      'candy': -8, 'soda': -8, 'sugar': -4, 'syrup': -5,
      'fatty meat': -3, 'lard': -5, 'cream': -3,
    },
    ingredientBonuses: {
      'milk': 3, 'egg': 3, 'chicken': 3, 'fish': 3,
      'vegetables': 3, 'fruits': 3, 'whole grains': 3,
      'cheese': 2, 'yogurt': 3,
    },
  ),
  'pregnant': ProfileScoring(
    penaltyWeights: {
      'calories': 0.8, 'total_fat_pdv': 1.0, 'sugar_pdv': 1.3,
      'sodium_pdv': 1.5, 'protein_low': 1.3, 'saturated_fat_pdv': 1.2, 'carbs_pdv': 0.7,
    },
    bonusWeights: {
      'protein_recovery': 1.3, 'calorie_balance': 0.7, 'sugar_balance': 1.2,
    },
    ingredientPenalties: {
      'alcohol': -50, 'wine': -50, 'beer': -50, 'rum': -50,
      'raw fish': -10, 'sushi': -10,
      'fatty meat': -4, 'lard': -5, 'cream': -3,
      'caffeine': -3, 'coffee': -2,
    },
    ingredientBonuses: {
      'spinach': 5, 'egg': 4, 'fish': 4, 'salmon': 4,
      'milk': 3, 'yogurt': 3, 'cheese': 2,
      'vegetables': 3, 'fruits': 3, 'whole grains': 3,
      'lentil': 4, 'beans': 3, 'iron': 5,
    },
  ),
};

/// Allergen → ingredient-keyword map. Mirrors ALLERGY_GROUPS in the Python KB.
const Map<String, List<String>> allergyGroups = {
  'fish': ['salmon', 'tuna', 'tilapia', 'cod', 'trout', 'halibut', 'fish', 'mahi', 'snapper', 'sardine', 'anchovy'],
  'shellfish': ['shrimp', 'crab', 'lobster', 'clam', 'oyster', 'mussel', 'scallop', 'prawn', 'crawfish'],
  'tree nuts': ['almond', 'walnut', 'pecan', 'cashew', 'pistachio', 'hazelnut', 'macadamia', 'pine nut'],
  'peanut': ['peanut', 'goober'],
  'milk': ['milk', 'cheese', 'cream', 'butter', 'yogurt', 'whey', 'lactose', 'ghee'],
  'egg': ['egg', 'mayo'],
  'soy': ['soy', 'tofu', 'edamame', 'miso', 'tempeh'],
  'gluten': ['wheat', 'flour', 'bread', 'pasta', 'barley', 'rye', 'seitan', 'bulgur'],
};

const List<String> meatKeywords = [
  'chicken', 'beef', 'pork', 'lamb', 'turkey', 'sausage',
  'bacon', 'ham', 'steak', 'meat', 'veal',
];

const List<String> animalKeywords = [
  ...meatKeywords,
  'milk', 'egg', 'cheese', 'cream', 'butter', 'honey', 'yogurt', 'gelatin', 'whey',
];
