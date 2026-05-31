import 'package:flutter/foundation.dart';
import 'package:fridge_app/services/database_service.dart';
import 'package:fridge_app/services/user_profile_service.dart';

/// Tracks recipes the user explicitly told us not to recommend, and feeds
/// the same signal into `user_interactions` as a rating=1 row so CF picks
/// up the negative preference.
///
/// The dismissed_recipes table is keyed by recipe_id (INTEGER PRIMARY KEY)
/// so re-dismissing is idempotent. `restore(id)` undoes a dismissal but
/// leaves the rating=1 row in user_interactions as historical data.
class DismissalService {
  DismissalService._();
  static final DismissalService instance = DismissalService._();

  /// Same offset CookingService uses so dismissal interactions don't collide
  /// with synthetic CSV user ids.
  static const int _appUserIdOffset = 1000000;

  /// Recipe ids the user has told us to stop recommending.
  Future<Set<int>> dismissedIds() async {
    final rows = await DatabaseService.instance.queryAll('dismissed_recipes');
    return rows
        .map((r) => (r['recipe_id'] as num?)?.toInt())
        .whereType<int>()
        .toSet();
  }

  Future<bool> isDismissed(int recipeId) async {
    final rows = await DatabaseService.instance.queryWhere(
      'dismissed_recipes',
      where: 'recipe_id = ?',
      whereArgs: [recipeId],
      limit: 1,
    );
    return rows.isNotEmpty;
  }

  /// Mark a recipe as not-to-be-recommended. Writes into both
  /// `dismissed_recipes` (so KB and CF skip it) and `user_interactions`
  /// (rating=1 so the CF taste profile reflects the dislike).
  Future<void> dismiss(int recipeId) async {
    final db = DatabaseService.instance;
    await db.insert('dismissed_recipes', {
      'recipe_id': recipeId,
      'dismissed_at': DateTime.now().millisecondsSinceEpoch,
    });

    final user = UserProfileService.instance.current;
    if (user?.id != null) {
      await db.insert('user_interactions', {
        'user_id': _appUserIdOffset + user!.id!,
        'recipe_id': recipeId,
        'rating': 1,
        'profile_tag': user.scoringKey,
      });
    } else {
      debugPrint('[Dismiss] No active user profile — skipping interaction row.');
    }
  }

  /// Undo a dismissal. Removes the row in `dismissed_recipes`; the rating=1
  /// row in `user_interactions` stays (it's historical, removing it would
  /// require timestamping interactions to know which one to delete).
  Future<void> restore(int recipeId) async {
    await DatabaseService.instance.delete(
      'dismissed_recipes',
      where: 'recipe_id = ?',
      whereArgs: [recipeId],
    );
  }
}
