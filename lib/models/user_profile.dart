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

/// Stored profile fields are the ones the welcome bottom sheet actually
/// collects (or directly derives from collected answers). Biometric defaults
/// like weight/height aren't asked, so they aren't persisted; daily caloric
/// target and meals-per-day are derived from [profileKey] + [sex] at runtime
/// instead of being stored as synthesised defaults.
class UserProfile {
  final int? id;
  final ProfileKey profileKey;
  final int age;
  final Sex sex;
  final List<DietaryRestriction> dietaryRestrictions;
  final List<String> avoidIngredients;
  final DateTime createdAt;

  const UserProfile({
    this.id,
    required this.profileKey,
    required this.age,
    required this.sex,
    required this.dietaryRestrictions,
    required this.avoidIngredients,
    required this.createdAt,
  });

  /// Reasonable kcal/day for the KB recommender to scale macro limits.
  /// Values are WHO/ISSN-ish defaults per (profile, sex) — not personalised
  /// because the welcome sheet doesn't ask for weight/height/activity.
  int get dailyCalories {
    switch (profileKey) {
      case ProfileKey.athleteBodybuilder:
        return sex == Sex.male ? 3000 : 2500;
      case ProfileKey.adolescent:
        return sex == Sex.male ? 2800 : 2200;
      case ProfileKey.pregnantLactating:
        return 2300;
      case ProfileKey.generalAdult:
        return sex == Sex.male ? 2400 : 2000;
    }
  }

  /// Meals/day used by KB's adaptive tracker. Athletes/bodybuilders typically
  /// split into more frequent meals; pregnant/lactating profiles do too.
  int get mealsPerDay {
    switch (profileKey) {
      case ProfileKey.athleteBodybuilder:
        return 5;
      case ProfileKey.pregnantLactating:
        return 5;
      case ProfileKey.adolescent:
        return 4;
      case ProfileKey.generalAdult:
        return 3;
    }
  }

  Map<String, dynamic> toDbMap() => {
        if (id != null) 'id': id,
        'profile_key': profileKey.dbValue,
        'age': age,
        'sex': sex.dbValue,
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
