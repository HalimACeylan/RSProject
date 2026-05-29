import 'package:fridge_app/models/user_profile.dart';
import 'package:fridge_app/services/database_service.dart';

/// Single-user profile service. The app stores exactly one row in `users`.
class UserProfileService {
  UserProfileService._();
  static final UserProfileService instance = UserProfileService._();

  UserProfile? _cached;
  bool _initialized = false;

  Future<void> initialize() async {
    if (_initialized) return;
    _initialized = true;
    // Latest row wins. Each completed bottom-sheet flow inserts a new row, so
    // the user can run the setup again to "switch user" and the most recent
    // setup is what gets loaded on next launch.
    final rows = await DatabaseService.instance
        .queryWhere('users', orderBy: 'id DESC', limit: 1);
    if (rows.isNotEmpty) {
      _cached = UserProfile.fromDbMap(rows.first);
    }
  }

  bool get hasProfile => _cached != null;
  UserProfile? get current => _cached;

  Future<void> save(UserProfile profile) async {
    final id = await DatabaseService.instance
        .insert('users', profile.toDbMap());
    _cached = UserProfile(
      id: id,
      profileKey: profile.profileKey,
      age: profile.age,
      sex: profile.sex,
      weightKg: profile.weightKg,
      heightCm: profile.heightCm,
      activityLevel: profile.activityLevel,
      mealsPerDay: profile.mealsPerDay,
      dailyCalories: profile.dailyCalories,
      dietaryRestrictions: profile.dietaryRestrictions,
      avoidIngredients: profile.avoidIngredients,
      createdAt: profile.createdAt,
    );
  }

  Future<void> clear() async {
    await DatabaseService.instance.delete('users');
    _cached = null;
  }
}
