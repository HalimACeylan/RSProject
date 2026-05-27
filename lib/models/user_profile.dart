import 'dart:convert';

enum ProfileKey {
  generalAdult('general_adult', 'General Adult', 'Balanced nutrition focus'),
  athleteBodybuilder('athlete_bodybuilder', 'Athlete / Bodybuilder', 'High protein, muscle growth'),
  adolescent('adolescent', 'Adolescent (Growing)', 'High protein and balanced macros'),
  pregnantLactating('pregnant_lactating', 'Pregnant / Lactating', 'Folate, iron, calcium focus');

  final String dbValue;
  final String label;
  final String description;
  const ProfileKey(this.dbValue, this.label, this.description);

  static ProfileKey fromDbValue(String v) =>
      ProfileKey.values.firstWhere((p) => p.dbValue == v, orElse: () => ProfileKey.generalAdult);
}

enum Sex {
  male('M', 'Male'),
  female('F', 'Female');

  final String dbValue;
  final String label;
  const Sex(this.dbValue, this.label);

  static Sex fromDbValue(String v) =>
      Sex.values.firstWhere((s) => s.dbValue == v, orElse: () => Sex.male);
}

enum ActivityLevel {
  sedentary('sedentary', 'Sedentary (little/no exercise)', 1.2),
  light('light', 'Lightly active (1-3 days/wk)', 1.375),
  moderate('moderate', 'Moderately active (3-5 days/wk)', 1.55),
  veryActive('very_active', 'Very active (6-7 days/wk)', 1.725),
  extraActive('extra_active', 'Extra active (athlete / physical job)', 1.9);

  final String dbValue;
  final String label;
  final double multiplier;
  const ActivityLevel(this.dbValue, this.label, this.multiplier);

  static ActivityLevel fromDbValue(String v) => ActivityLevel.values
      .firstWhere((a) => a.dbValue == v, orElse: () => ActivityLevel.moderate);
}

/// Common allergen / dietary restriction groups (match Python KB ALLERGY_GROUPS).
enum DietaryRestriction {
  fish('fish', 'Fish'),
  shellfish('shellfish', 'Shellfish'),
  treeNuts('tree nuts', 'Tree nuts'),
  peanut('peanut', 'Peanuts'),
  milk('milk', 'Milk / Dairy'),
  egg('egg', 'Eggs'),
  soy('soy', 'Soy'),
  gluten('gluten', 'Gluten'),
  vegetarian('vegetarian', 'Vegetarian'),
  vegan('vegan', 'Vegan');

  final String dbValue;
  final String label;
  const DietaryRestriction(this.dbValue, this.label);

  static DietaryRestriction? fromDbValue(String v) {
    try {
      return DietaryRestriction.values.firstWhere((r) => r.dbValue == v);
    } catch (_) {
      return null;
    }
  }
}

class UserProfile {
  final int? id;
  final ProfileKey profileKey;
  final int age;
  final Sex sex;
  final double weightKg;
  final double heightCm;
  final ActivityLevel activityLevel;
  final int mealsPerDay;
  final int dailyCalories;
  final List<DietaryRestriction> dietaryRestrictions;
  final List<String> avoidIngredients;
  final DateTime createdAt;

  const UserProfile({
    this.id,
    required this.profileKey,
    required this.age,
    required this.sex,
    required this.weightKg,
    required this.heightCm,
    required this.activityLevel,
    required this.mealsPerDay,
    required this.dailyCalories,
    required this.dietaryRestrictions,
    required this.avoidIngredients,
    required this.createdAt,
  });

  /// Mifflin–St Jeor BMR × activity multiplier.
  static int computeDailyCalories({
    required Sex sex,
    required int age,
    required double weightKg,
    required double heightCm,
    required ActivityLevel activity,
  }) {
    final s = sex == Sex.male ? 5.0 : -161.0;
    final bmr = (10 * weightKg) + (6.25 * heightCm) - (5 * age) + s;
    return (bmr * activity.multiplier).round();
  }

  Map<String, dynamic> toDbMap() => {
        if (id != null) 'id': id,
        'profile_key': profileKey.dbValue,
        'age': age,
        'sex': sex.dbValue,
        'weight_kg': weightKg,
        'height_cm': heightCm,
        'activity_level': activityLevel.dbValue,
        'meals_per_day': mealsPerDay,
        'daily_calories': dailyCalories,
        'dietary_restrictions':
            jsonEncode(dietaryRestrictions.map((r) => r.dbValue).toList()),
        'avoid_ingredients': jsonEncode(avoidIngredients),
        'created_at': createdAt.millisecondsSinceEpoch,
      };

  factory UserProfile.fromDbMap(Map<String, dynamic> m) {
    final restRaw = (m['dietary_restrictions'] as String?) ?? '[]';
    final avoidRaw = (m['avoid_ingredients'] as String?) ?? '[]';
    return UserProfile(
      id: m['id'] as int?,
      profileKey: ProfileKey.fromDbValue(m['profile_key'] as String),
      age: m['age'] as int,
      sex: Sex.fromDbValue(m['sex'] as String),
      weightKg: (m['weight_kg'] as num).toDouble(),
      heightCm: (m['height_cm'] as num).toDouble(),
      activityLevel: ActivityLevel.fromDbValue(m['activity_level'] as String),
      mealsPerDay: m['meals_per_day'] as int,
      dailyCalories: m['daily_calories'] as int,
      dietaryRestrictions: (jsonDecode(restRaw) as List)
          .map((e) => DietaryRestriction.fromDbValue(e as String))
          .whereType<DietaryRestriction>()
          .toList(),
      avoidIngredients:
          (jsonDecode(avoidRaw) as List).map((e) => e as String).toList(),
      createdAt: DateTime.fromMillisecondsSinceEpoch(m['created_at'] as int),
    );
  }
}
