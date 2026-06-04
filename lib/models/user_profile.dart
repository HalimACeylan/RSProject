import 'dart:convert';

enum ProfileKey {
  generalAdult('general_adult', 'General Adult', 'Balanced nutrition focus'),
  athleteBodybuilder('athlete_bodybuilder', 'Athlete / Bodybuilder',
      'High protein, muscle growth'),
  adolescent('adolescent', 'Adolescent (Growing)', 'High protein and balanced macros');

  final String dbValue;
  final String label;
  final String description;
  const ProfileKey(this.dbValue, this.label, this.description);

  /// Maps current values first, then folds legacy strings from older installs:
  ///   athlete / bodybuilder → athlete_bodybuilder
  ///   pregnant / lactating / pregnant_lactating → generalAdult (those
  ///     installs' is_pregnant column will already have been migrated to 1
  ///     by [DatabaseService._migrateProfileKeys] so scoring still uses the
  ///     pregnant rule-set).
  static ProfileKey fromDbValue(String v) {
    for (final p in ProfileKey.values) {
      if (p.dbValue == v) return p;
    }
    switch (v) {
      case 'athlete':
      case 'bodybuilder':
        return ProfileKey.athleteBodybuilder;
      case 'pregnant':
      case 'lactating':
      case 'pregnant_lactating':
        return ProfileKey.generalAdult;
      default:
        return ProfileKey.generalAdult;
    }
  }
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
  /// Boolean flag that overrides scoring to use the pregnant rule-set when
  /// true. Only meaningful for female users — the welcome sheet doesn't
  /// surface the question to males.
  final bool isPregnant;
  final List<DietaryRestriction> dietaryRestrictions;
  final List<String> avoidIngredients;
  final DateTime createdAt;

  const UserProfile({
    this.id,
    required this.profileKey,
    required this.age,
    required this.sex,
    this.isPregnant = false,
    required this.dietaryRestrictions,
    required this.avoidIngredients,
    required this.createdAt,
  });

  /// String key the KB uses for macro-rule + scoring lookup. Pregnancy
  /// dominates: a pregnant athlete still gets the pregnant rule-set.
  String get scoringKey =>
      isPregnant ? 'pregnant' : profileKey.dbValue;

  /// Reasonable kcal/day for the KB recommender to scale macro limits.
  /// Values are WHO/ISSN-ish defaults per (profile, sex). Pregnancy
  /// overrides to a fixed 2300 kcal regardless of base profile.
  int get dailyCalories {
    if (isPregnant) return 2300;
    switch (profileKey) {
      case ProfileKey.athleteBodybuilder:
        return sex == Sex.male ? 3000 : 2500;
      case ProfileKey.adolescent:
        return sex == Sex.male ? 2800 : 2200;
      case ProfileKey.generalAdult:
        return sex == Sex.male ? 2400 : 2000;
    }
  }

  /// Meals/day for the adaptive tracker. Mirrors Python.
  int get mealsPerDay {
    if (isPregnant) return 4;
    switch (profileKey) {
      case ProfileKey.athleteBodybuilder:
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
        'is_pregnant': isPregnant ? 1 : 0,
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
      isPregnant: (m['is_pregnant'] as int? ?? 0) == 1,
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
