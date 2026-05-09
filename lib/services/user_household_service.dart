/// Handles user identity and household context.
///
/// Stripped of Firebase — returns local fallback values.
/// The public API is preserved so existing code continues to compile.
class UserHouseholdService {
  UserHouseholdService._();
  static final UserHouseholdService instance = UserHouseholdService._();

  static const String _fallbackUserId = 'local_debug_user';
  static const String _fallbackHouseholdId = 'local_debug_household';

  bool _isInitialized = false;
  final String _userId = _fallbackUserId;
  final String _householdId = _fallbackHouseholdId;
  final String _memberRole = 'owner';

  bool get isFirebaseEnabled => false;
  String get userId => _userId;
  String get householdId => _householdId;
  String get memberRole => _memberRole;
  bool get isAuthenticated => false;

  Future<void> initialize() async {
    if (_isInitialized) return;
    _isInitialized = true;
    // No-op — purely local mode
  }

  Map<String, dynamic> buildAuditFields({required bool includeCreatedAt}) {
    return {
      'householdId': _householdId,
      'updatedByUserId': _userId,
      'updatedAt': DateTime.now().millisecondsSinceEpoch,
      if (includeCreatedAt) 'createdByUserId': _userId,
      if (includeCreatedAt) 'createdAt': DateTime.now().millisecondsSinceEpoch,
    };
  }
}
