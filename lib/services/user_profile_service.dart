import 'package:fridge_app/models/user_profile.dart';
import 'package:fridge_app/services/database_service.dart';

/// Single-user profile service. The app stores exactly one row in `users`.
class UserProfileService {
  UserProfileService._();
  static final UserProfileService instance = UserProfileService._();

  UserProfile? _cached;
  bool _initialized = false;

  /// `meta` key under which we stash the active profile id. Lets the welcome
  /// screen's picker persist its selection across launches.
  static const String _selectedKey = 'selected_user_id';

  Future<void> initialize() async {
    if (_initialized) return;
    _initialized = true;
    _cached = await _loadActive();
  }

  bool get hasProfile => _cached != null;
  UserProfile? get current => _cached;

  /// All saved profiles, newest first.
  Future<List<UserProfile>> listAll() async {
    final rows = await DatabaseService.instance
        .queryWhere('users', orderBy: 'id DESC');
    return rows.map((r) => UserProfile.fromDbMap(r)).toList();
  }

  /// Mark the given profile id as the active one (in-memory cache + meta
  /// table) so it survives the next launch too.
  Future<bool> selectById(int id) async {
    final rows = await DatabaseService.instance.queryWhere(
      'users',
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );
    if (rows.isEmpty) return false;
    _cached = UserProfile.fromDbMap(rows.first);
    await _writeSelectedId(id);
    return true;
  }

  Future<void> save(UserProfile profile) async {
    final id = await DatabaseService.instance
        .insert('users', profile.toDbMap());
    _cached = UserProfile(
      id: id,
      profileKey: profile.profileKey,
      age: profile.age,
      sex: profile.sex,
      isPregnant: profile.isPregnant,
      dietaryRestrictions: profile.dietaryRestrictions,
      avoidIngredients: profile.avoidIngredients,
      createdAt: profile.createdAt,
    );
    // A freshly-created profile is always the active one.
    await _writeSelectedId(id);
  }

  Future<void> clear() async {
    await DatabaseService.instance.delete('users');
    await DatabaseService.instance.delete(
      'meta',
      where: 'key = ?',
      whereArgs: [_selectedKey],
    );
    _cached = null;
  }

  // ── meta helpers ────────────────────────────────────────────────

  Future<UserProfile?> _loadActive() async {
    final selectedId = await _readSelectedId();
    if (selectedId != null) {
      final rows = await DatabaseService.instance.queryWhere(
        'users',
        where: 'id = ?',
        whereArgs: [selectedId],
        limit: 1,
      );
      if (rows.isNotEmpty) return UserProfile.fromDbMap(rows.first);
    }
    // Fall back to the newest row (covers fresh installs and the case where
    // the persisted id no longer exists — e.g. the table was wiped).
    final rows = await DatabaseService.instance
        .queryWhere('users', orderBy: 'id DESC', limit: 1);
    return rows.isEmpty ? null : UserProfile.fromDbMap(rows.first);
  }

  Future<int?> _readSelectedId() async {
    final rows = await DatabaseService.instance.queryWhere(
      'meta',
      where: 'key = ?',
      whereArgs: [_selectedKey],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return int.tryParse((rows.first['value'] as String?) ?? '');
  }

  Future<void> _writeSelectedId(int id) async {
    await DatabaseService.instance
        .insert('meta', {'key': _selectedKey, 'value': id.toString()});
  }
}
