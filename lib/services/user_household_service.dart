import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';

/// Handles authenticated user identity and household bootstrapping.
///
/// Data shape created/maintained:
/// - users/{uid}
/// - households/{householdId}
/// - households/{householdId}/members/{uid}
/// - households/{householdId}/subscriptions/current
/// - households/{householdId}/payments/payment_profile
class UserHouseholdService {
  UserHouseholdService._();
  static final UserHouseholdService instance = UserHouseholdService._();

  static const String _fallbackUserId = 'local_debug_user';
  static const String _fallbackHouseholdId = 'local_debug_household';

  FirebaseAuth? _auth;
  FirebaseFirestore? _firestore;
  bool _isInitialized = false;
  bool _firebaseEnabled = false;
  String _userId = _fallbackUserId;
  String _householdId = _fallbackHouseholdId;
  String _memberRole = 'owner';

  bool get isFirebaseEnabled => _firebaseEnabled;
  String get userId => _userId;
  String get householdId => _householdId;
  String get memberRole => _memberRole;
  bool get isAuthenticated => _firebaseEnabled && _userId != _fallbackUserId;

  Future<void> initialize() async {
    if (_isInitialized) return;
    _isInitialized = true;

    if (Firebase.apps.isEmpty) return;

    try {
      _auth = FirebaseAuth.instance;
      _firestore = FirebaseFirestore.instance;
      final user = await _ensureAuthenticatedUser();
      if (user == null) {
        _firebaseEnabled = false;
        return;
      }
      _userId = user.uid;
      await _ensureUserAndHouseholdDocuments(user);
      _firebaseEnabled = true;
    } catch (_) {
      _firebaseEnabled = false;
    }
  }

  Future<User?> _ensureAuthenticatedUser() async {
    final auth = _auth!;
    final currentUser = auth.currentUser;
    if (currentUser != null) return currentUser;

    try {
      final credential = await auth.signInAnonymously();
      final signedInUser = credential.user;
      if (signedInUser == null) {
        debugPrint(
          'Firebase auth returned null user for anonymous sign-in; '
          'falling back to local-only mode.',
        );
        return null;
      }
      return signedInUser;
    } on FirebaseAuthException catch (e) {
      debugPrint(
        'Anonymous auth failed (${e.code}): ${e.message}. '
        'Falling back to local-only mode.',
      );
      return null;
    } catch (e) {
      debugPrint(
        'Anonymous auth failed with unexpected error: $e. '
        'Falling back to local-only mode.',
      );
      return null;
    }
  }

  Future<void> _ensureUserAndHouseholdDocuments(User user) async {
    final firestore = _firestore!;
    final users = firestore.collection('users');
    final households = firestore.collection('households');

    final userRef = users.doc(user.uid);
    final userSnapshot = await userRef.get();
    final userData = userSnapshot.data();
    final existingHouseholdId = userData?['primaryHouseholdId'] as String?;

    if (existingHouseholdId != null && existingHouseholdId.isNotEmpty) {
      final householdRef = households.doc(existingHouseholdId);
      final householdSnapshot = await householdRef.get();
      if (householdSnapshot.exists) {
        final role = await _ensureMembershipAndGetRole(
          householdId: existingHouseholdId,
          user: user,
          defaultRole: 'member',
        );
        _householdId = existingHouseholdId;
        _memberRole = role;
        await userRef.set(
          _buildUserProfileData(
            user: user,
            primaryHouseholdId: existingHouseholdId,
            role: role,
            includeCreatedAt: false,
          ),
          SetOptions(merge: true),
        );
        return;
      }
    }

    final householdRef = households.doc();
    final householdId = householdRef.id;
    final inviteCode = _generateInviteCode(seed: householdId);
    await householdRef.set(
      _buildHouseholdData(
        householdId: householdId,
        ownerUserId: user.uid,
        householdName: _defaultHouseholdName(user),
        inviteCode: inviteCode,
      ),
    );
    await householdRef
        .collection('members')
        .doc(user.uid)
        .set(_buildHouseholdMemberData(user: user, role: 'owner'));
    await householdRef
        .collection('subscriptions')
        .doc('current')
        .set(_buildDefaultSubscriptionData());
    await householdRef
        .collection('payments')
        .doc('payment_profile')
        .set(_buildDefaultPaymentProfileData());
    await userRef.set(
      _buildUserProfileData(
        user: user,
        primaryHouseholdId: householdId,
        role: 'owner',
        includeCreatedAt: true,
      ),
      SetOptions(merge: true),
    );

    _householdId = householdId;
    _memberRole = 'owner';
  }

  Future<String> _ensureMembershipAndGetRole({
    required String householdId,
    required User user,
    required String defaultRole,
  }) async {
    final memberRef = _firestore!
        .collection('households')
        .doc(householdId)
        .collection('members')
        .doc(user.uid);
    final memberSnapshot = await memberRef.get();
    if (memberSnapshot.exists) {
      final role = memberSnapshot.data()?['role'] as String?;
      return role ?? defaultRole;
    }

    await memberRef.set(
      _buildHouseholdMemberData(user: user, role: defaultRole),
    );
    return defaultRole;
  }

  Future<void> joinHousehold(
    String householdId, {
    required String inviteCode,
    String role = 'member',
  }) async {
    if (!_firebaseEnabled) return;

    final firestore = _firestore!;
    final householdRef = firestore.collection('households').doc(householdId);
    final householdSnapshot = await householdRef.get();
    if (!householdSnapshot.exists) {
      throw StateError('Household does not exist.');
    }
    final householdData = householdSnapshot.data();
    final expectedInviteCode = householdData?['inviteCode'] as String?;
    if (expectedInviteCode == null || expectedInviteCode != inviteCode) {
      throw StateError('Invalid household invite code.');
    }

    final memberRef = householdRef.collection('members').doc(_userId);
    final memberSnapshot = await memberRef.get();
    final isNewMembership = !memberSnapshot.exists;
    final roleToWrite = memberSnapshot.data()?['role'] as String? ?? role;
    final memberData = _buildHouseholdMemberData(
      user: _auth!.currentUser!,
      role: roleToWrite,
    )..['inviteCode'] = inviteCode;

    final batch = firestore.batch();
    batch.set(memberRef, memberData, SetOptions(merge: true));
    batch.set(firestore.collection('users').doc(_userId), {
      'primaryHouseholdId': householdId,
      'role': roleToWrite,
      'updatedAt': FieldValue.serverTimestamp(),
      'lastSignInAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
    batch.set(householdRef, {
      'updatedAt': FieldValue.serverTimestamp(),
      if (isNewMembership) 'memberCount': FieldValue.increment(1),
    }, SetOptions(merge: true));
    await batch.commit();

    _householdId = householdId;
    _memberRole = roleToWrite;
  }

  Future<String?> rotateHouseholdInviteCode() async {
    if (!_firebaseEnabled) return null;
    if (!(_memberRole == 'owner' || _memberRole == 'admin')) return null;

    final code = _generateInviteCode(seed: _householdId);
    await _firestore!.collection('households').doc(_householdId).set({
      'inviteCode': code,
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
    return code;
  }

  Future<Map<String, dynamic>?> readCurrentUserFromCloud() async {
    if (!_firebaseEnabled) return null;
    final snapshot = await _firestore!.collection('users').doc(_userId).get();
    return snapshot.data();
  }

  Future<Map<String, dynamic>?> readCurrentHouseholdFromCloud() async {
    if (!_firebaseEnabled) return null;
    final snapshot = await _firestore!
        .collection('households')
        .doc(_householdId)
        .get();
    return snapshot.data();
  }

  Future<List<Map<String, dynamic>>> queryHouseholdMembersFromCloud({
    String? role,
    int limit = 50,
  }) async {
    if (!_firebaseEnabled) return const [];

    Query<Map<String, dynamic>> query = _firestore!
        .collection('households')
        .doc(_householdId)
        .collection('members');

    if (role != null && role.trim().isNotEmpty) {
      query = query.where('role', isEqualTo: role.trim());
    }

    final snapshot = await query.limit(limit).get();
    return snapshot.docs.map((doc) {
      final data = Map<String, dynamic>.from(doc.data());
      data['id'] = doc.id;
      return data;
    }).toList();
  }

  Future<void> updateCurrentUserProfile({
    String? displayName,
    String? photoUrl,
  }) async {
    if (!_firebaseEnabled) return;
    final data = <String, dynamic>{'updatedAt': FieldValue.serverTimestamp()};
    if (displayName != null) data['displayName'] = displayName;
    if (photoUrl != null) data['photoUrl'] = photoUrl;

    await _firestore!
        .collection('users')
        .doc(_userId)
        .set(data, SetOptions(merge: true));
  }

  Future<void> updateCurrentHousehold({
    String? name,
    String? planTier,
    String? billingStatus,
    bool? aiReceiptParsingEnabled,
  }) async {
    if (!_firebaseEnabled) return;
    final data = <String, dynamic>{'updatedAt': FieldValue.serverTimestamp()};
    if (name != null) data['name'] = name;
    if (planTier != null) data['planTier'] = planTier;
    if (billingStatus != null) data['billingStatus'] = billingStatus;
    if (aiReceiptParsingEnabled != null) {
      data['aiReceiptParsingEnabled'] = aiReceiptParsingEnabled;
    }

    await _firestore!
        .collection('households')
        .doc(_householdId)
        .set(data, SetOptions(merge: true));
  }

  Future<void> upsertCurrentSubscription({
    required String planId,
    required String status,
    String interval = 'month',
    int amountCents = 0,
    String currency = 'USD',
    int seatCount = 1,
    String? stripeSubscriptionId,
    DateTime? trialEndsAt,
    DateTime? currentPeriodStart,
    DateTime? currentPeriodEnd,
  }) async {
    if (!_firebaseEnabled) return;

    final householdRef = _firestore!.collection('households').doc(_householdId);
    await householdRef.collection('subscriptions').doc('current').set({
      'id': 'current',
      'provider': 'stripe',
      'planId': planId,
      'status': status,
      'interval': interval,
      'amountCents': amountCents,
      'currency': currency,
      'seatCount': seatCount,
      'stripeSubscriptionId': stripeSubscriptionId,
      'trialEndsAt': trialEndsAt == null
          ? null
          : Timestamp.fromDate(trialEndsAt),
      'currentPeriodStart': currentPeriodStart == null
          ? null
          : Timestamp.fromDate(currentPeriodStart),
      'currentPeriodEnd': currentPeriodEnd == null
          ? null
          : Timestamp.fromDate(currentPeriodEnd),
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));

    await householdRef.set({
      'planTier': planId,
      'billingStatus': status,
      'stripeSubscriptionId': stripeSubscriptionId,
      'currentPeriodEnd': currentPeriodEnd == null
          ? null
          : Timestamp.fromDate(currentPeriodEnd),
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  Future<void> updateCurrentPaymentProfile({
    String? customerId,
    String? defaultPaymentMethodId,
    String? billingEmail,
    String? billingName,
    String? taxCountry,
    String? taxId,
  }) async {
    if (!_firebaseEnabled) return;
    final data = <String, dynamic>{'updatedAt': FieldValue.serverTimestamp()};
    if (customerId != null) data['customerId'] = customerId;
    if (defaultPaymentMethodId != null) {
      data['defaultPaymentMethodId'] = defaultPaymentMethodId;
    }
    if (billingEmail != null) data['billingEmail'] = billingEmail;
    if (billingName != null) data['billingName'] = billingName;
    if (taxCountry != null) data['taxCountry'] = taxCountry;
    if (taxId != null) data['taxId'] = taxId;

    await _firestore!
        .collection('households')
        .doc(_householdId)
        .collection('payments')
        .doc('payment_profile')
        .set(data, SetOptions(merge: true));
  }

  Map<String, dynamic> buildAuditFields({required bool includeCreatedAt}) {
    return {
      'householdId': _householdId,
      'updatedByUserId': _userId,
      'updatedAt': FieldValue.serverTimestamp(),
      if (includeCreatedAt) 'createdByUserId': _userId,
      if (includeCreatedAt) 'createdAt': FieldValue.serverTimestamp(),
    };
  }

  String _defaultHouseholdName(User user) {
    final displayName = user.displayName?.trim();
    if (displayName != null && displayName.isNotEmpty) {
      return '$displayName Household';
    }
    return 'My Household';
  }

  String _generateInviteCode({required String seed}) {
    final safeSeed = seed.replaceAll(RegExp(r'[^a-zA-Z0-9]'), '').toUpperCase();
    final left = safeSeed.padRight(3, 'X').substring(0, 3);
    final millis = DateTime.now().millisecondsSinceEpoch
        .toRadixString(36)
        .toUpperCase();
    final right = millis.padLeft(4, '0').substring(millis.length - 4);
    return '$left-$right';
  }

  Map<String, dynamic> _buildUserProfileData({
    required User user,
    required String primaryHouseholdId,
    required String role,
    required bool includeCreatedAt,
  }) {
    return {
      'uid': user.uid,
      'email': user.email,
      'displayName': user.displayName,
      'photoUrl': user.photoURL,
      'isAnonymous': user.isAnonymous,
      'authProviderIds': user.providerData.map((p) => p.providerId).toList(),
      'primaryHouseholdId': primaryHouseholdId,
      'role': role,
      'status': 'active',
      'planTier': 'free',
      'billingStatus': 'none',
      'updatedAt': FieldValue.serverTimestamp(),
      'lastSignInAt': FieldValue.serverTimestamp(),
      if (includeCreatedAt) 'createdAt': FieldValue.serverTimestamp(),
    };
  }

  Map<String, dynamic> _buildHouseholdData({
    required String householdId,
    required String ownerUserId,
    required String householdName,
    required String inviteCode,
  }) {
    return {
      'id': householdId,
      'name': householdName,
      'ownerUserId': ownerUserId,
      'inviteCode': inviteCode,
      'memberCount': 1,
      'status': 'active',
      'planTier': 'free',
      'billingStatus': 'trialing',
      'billingCycle': 'monthly',
      'seatLimit': 5,
      'stripeCustomerId': null,
      'stripeSubscriptionId': null,
      'trialEndsAt': null,
      'currentPeriodEnd': null,
      'aiReceiptParsingEnabled': false,
      'updatedAt': FieldValue.serverTimestamp(),
      'createdAt': FieldValue.serverTimestamp(),
    };
  }

  Map<String, dynamic> _buildHouseholdMemberData({
    required User user,
    required String role,
  }) {
    return {
      'userId': user.uid,
      'role': role,
      'status': 'active',
      'displayName': user.displayName,
      'email': user.email,
      'photoUrl': user.photoURL,
      'joinedAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    };
  }

  Map<String, dynamic> _buildDefaultSubscriptionData() {
    return {
      'id': 'current',
      'provider': 'stripe',
      'planId': 'free',
      'status': 'trialing',
      'interval': 'month',
      'amountCents': 0,
      'currency': 'USD',
      'seatCount': 1,
      'cancelAtPeriodEnd': false,
      'trialEndsAt': null,
      'currentPeriodStart': null,
      'currentPeriodEnd': null,
      'updatedAt': FieldValue.serverTimestamp(),
      'createdAt': FieldValue.serverTimestamp(),
    };
  }

  Map<String, dynamic> _buildDefaultPaymentProfileData() {
    return {
      'id': 'payment_profile',
      'provider': 'stripe',
      'customerId': null,
      'defaultPaymentMethodId': null,
      'taxCountry': null,
      'taxId': null,
      'billingEmail': null,
      'billingName': null,
      'updatedAt': FieldValue.serverTimestamp(),
      'createdAt': FieldValue.serverTimestamp(),
    };
  }
}
