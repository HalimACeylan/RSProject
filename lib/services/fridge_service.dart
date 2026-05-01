import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:fridge_app/models/fridge_item.dart';
import 'package:fridge_app/models/units.dart';
import 'package:fridge_app/services/user_household_service.dart';

/// In-memory fridge service pre-populated with sample data.
///
/// Designed with the same interface that a Firebase-backed implementation
/// would expose, making migration straightforward:
///   - Replace the `_items` list with Firestore queries.
///   - Replace `addItem` / `updateItem` / `deleteItemById` with doc writes.
class FridgeService {
  // Singleton
  FridgeService._();
  static final FridgeService instance = FridgeService._();
  static const String _rootCollection = 'households';
  static const String _nameLowerField = 'nameLower';

  FirebaseFirestore? _firestore;
  bool _firebaseEnabled = false;
  bool _isInitialized = false;

  // ── Sample data ──────────────────────────────────────────────────

  final List<FridgeItem> _items = [
    // ── Produce ────────────────────────────────────────────────────
    FridgeItem(
      id: 'item_001',
      name: 'Fresh Spinach',
      category: FridgeCategory.produce,
      amount: 250,
      unit: FridgeUnit.grams,
      expiryDate: DateTime.now().add(const Duration(days: 0)),
      addedDate: DateTime.now().subtract(const Duration(days: 3)),
      imageUrl: 'assets/images/spinach.png',
      notes: 'Packaged Bag',
    ),
    FridgeItem(
      id: 'item_002',
      name: 'Organic Avocados',
      category: FridgeCategory.produce,
      amount: 3,
      unit: FridgeUnit.pieces,
      expiryDate: DateTime.now().add(const Duration(days: 2)),
      addedDate: DateTime.now().subtract(const Duration(days: 2)),
      imageUrl: 'assets/images/avocado.png',
    ),
    FridgeItem(
      id: 'item_003',
      name: 'Mixed Veggies',
      category: FridgeCategory.produce,
      amount: 400,
      unit: FridgeUnit.grams,
      expiryDate: DateTime.now().add(const Duration(days: 5)),
      addedDate: DateTime.now().subtract(const Duration(days: 1)),
    ),
    FridgeItem(
      id: 'item_004',
      name: 'Kale',
      category: FridgeCategory.produce,
      amount: 1,
      unit: FridgeUnit.pieces,
      expiryDate: DateTime.now().add(const Duration(days: 4)),
      addedDate: DateTime.now().subtract(const Duration(days: 2)),
      notes: '1 bunch',
    ),
    FridgeItem(
      id: 'item_005',
      name: 'Fresh Basil',
      category: FridgeCategory.produce,
      amount: 30,
      unit: FridgeUnit.grams,
      expiryDate: DateTime.now().add(const Duration(days: 3)),
      addedDate: DateTime.now().subtract(const Duration(days: 1)),
    ),
    FridgeItem(
      id: 'item_006',
      name: 'Bell Peppers',
      category: FridgeCategory.produce,
      amount: 3,
      unit: FridgeUnit.pieces,
      expiryDate: DateTime.now().add(const Duration(days: 6)),
      addedDate: DateTime.now().subtract(const Duration(days: 1)),
    ),
    FridgeItem(
      id: 'item_007',
      name: 'Cherry Tomatoes',
      category: FridgeCategory.produce,
      amount: 300,
      unit: FridgeUnit.grams,
      expiryDate: DateTime.now().add(const Duration(days: 5)),
      addedDate: DateTime.now().subtract(const Duration(days: 2)),
    ),

    // ── Dairy ──────────────────────────────────────────────────────
    FridgeItem(
      id: 'item_010',
      name: 'Whole Milk',
      category: FridgeCategory.dairy,
      amount: 1,
      unit: FridgeUnit.gallons,
      expiryDate: DateTime.now().add(const Duration(days: 2)),
      addedDate: DateTime.now().subtract(const Duration(days: 5)),
      notes: 'Opened',
    ),
    FridgeItem(
      id: 'item_011',
      name: 'Greek Yogurt',
      category: FridgeCategory.dairy,
      amount: 500,
      unit: FridgeUnit.grams,
      expiryDate: DateTime.now().add(const Duration(days: 10)),
      addedDate: DateTime.now().subtract(const Duration(days: 2)),
    ),
    FridgeItem(
      id: 'item_012',
      name: 'Cheddar Cheese',
      category: FridgeCategory.dairy,
      amount: 200,
      unit: FridgeUnit.grams,
      expiryDate: DateTime.now().add(const Duration(days: 14)),
      addedDate: DateTime.now().subtract(const Duration(days: 3)),
    ),
    FridgeItem(
      id: 'item_013',
      name: 'Large Brown Eggs',
      category: FridgeCategory.dairy,
      amount: 12,
      unit: FridgeUnit.pieces,
      expiryDate: DateTime.now().add(const Duration(days: 12)),
      addedDate: DateTime.now().subtract(const Duration(days: 3)),
      notes: '12ct carton',
    ),

    // ── Meat & Seafood ─────────────────────────────────────────────
    FridgeItem(
      id: 'item_020',
      name: 'Salmon Fillet',
      category: FridgeCategory.meat,
      amount: 400,
      unit: FridgeUnit.grams,
      expiryDate: DateTime.now().add(const Duration(days: 0)),
      addedDate: DateTime.now().subtract(const Duration(days: 2)),
      notes: 'Raw, 2 fillets',
    ),
    FridgeItem(
      id: 'item_021',
      name: 'Chicken Breast',
      category: FridgeCategory.meat,
      amount: 800,
      unit: FridgeUnit.grams,
      expiryDate: DateTime.now().add(const Duration(days: 1)),
      addedDate: DateTime.now().subtract(const Duration(days: 1)),
      notes: '4 pieces',
    ),

    // ── Beverages ──────────────────────────────────────────────────
    FridgeItem(
      id: 'item_030',
      name: 'Orange Juice',
      category: FridgeCategory.beverages,
      amount: 1000,
      unit: FridgeUnit.milliliters,
      expiryDate: DateTime.now().add(const Duration(days: 8)),
      addedDate: DateTime.now().subtract(const Duration(days: 4)),
    ),

    // ── Condiments ─────────────────────────────────────────────────
    FridgeItem(
      id: 'item_040',
      name: 'Soy Sauce',
      category: FridgeCategory.condiments,
      amount: 500,
      unit: FridgeUnit.milliliters,
      expiryDate: DateTime.now().add(const Duration(days: 90)),
      addedDate: DateTime.now().subtract(const Duration(days: 30)),
    ),
    FridgeItem(
      id: 'item_041',
      name: 'Pesto Sauce',
      category: FridgeCategory.condiments,
      amount: 200,
      unit: FridgeUnit.grams,
      expiryDate: DateTime.now().add(const Duration(days: 7)),
      addedDate: DateTime.now().subtract(const Duration(days: 5)),
    ),

    // ── Grains & Bakery ────────────────────────────────────────────
    FridgeItem(
      id: 'item_050',
      name: 'Sourdough Bread',
      category: FridgeCategory.grains,
      amount: 1,
      unit: FridgeUnit.pieces,
      expiryDate: DateTime.now().add(const Duration(days: 3)),
      addedDate: DateTime.now().subtract(const Duration(days: 1)),
      notes: '1 loaf',
    ),
    FridgeItem(
      id: 'item_051',
      name: 'Pasta',
      category: FridgeCategory.grains,
      amount: 500,
      unit: FridgeUnit.grams,
      expiryDate: DateTime.now().add(const Duration(days: 180)),
      addedDate: DateTime.now().subtract(const Duration(days: 10)),
      notes: '2 packs',
    ),

    // ── Frozen ─────────────────────────────────────────────────────
    FridgeItem(
      id: 'item_060',
      name: 'Frozen Berries',
      category: FridgeCategory.frozen,
      amount: 500,
      unit: FridgeUnit.grams,
      expiryDate: DateTime.now().add(const Duration(days: 60)),
      addedDate: DateTime.now().subtract(const Duration(days: 7)),
    ),
    FridgeItem(
      id: 'item_061',
      name: 'Ice Cream',
      category: FridgeCategory.frozen,
      amount: 1000,
      unit: FridgeUnit.milliliters,
      expiryDate: DateTime.now().add(const Duration(days: 90)),
      addedDate: DateTime.now().subtract(const Duration(days: 5)),
    ),

    // ── Snacks ─────────────────────────────────────────────────────
    FridgeItem(
      id: 'item_070',
      name: 'Hummus',
      category: FridgeCategory.snacks,
      amount: 250,
      unit: FridgeUnit.grams,
      expiryDate: DateTime.now().add(const Duration(days: 6)),
      addedDate: DateTime.now().subtract(const Duration(days: 3)),
    ),
  ];

  String get _activeHouseholdId => UserHouseholdService.instance.householdId;

  CollectionReference<Map<String, dynamic>> get _fridgeCollection => _firestore!
      .collection(_rootCollection)
      .doc(_activeHouseholdId)
      .collection('fridge_items');

  Future<void> initialize({
    bool seedCloudIfEmpty = true,
    bool forceReseed = false,
  }) async {
    if (_isInitialized) return;
    _isInitialized = true;

    if (Firebase.apps.isEmpty) return;

    try {
      _firestore = FirebaseFirestore.instance;
      _firebaseEnabled = true;
      if (forceReseed) {
        await _seedCloudFromLocal(overwrite: true);
      }
      await _syncFromCloud(seedCloudIfEmpty: seedCloudIfEmpty);
    } catch (_) {
      _firebaseEnabled = false;
      _firestore = null;
    }
  }

  Future<void> refreshFromCloud() async {
    if (!_firebaseEnabled) return;
    await _syncFromCloud(seedCloudIfEmpty: false);
  }

  Future<void> _syncFromCloud({required bool seedCloudIfEmpty}) async {
    final query = await _fridgeCollection.get();

    if (query.docs.isEmpty) {
      if (seedCloudIfEmpty) {
        await _seedCloudFromLocal(overwrite: false);
      }
      return;
    }

    final cloudItems = _parseCloudSnapshot(query.docs);

    _items
      ..clear()
      ..addAll(cloudItems);
  }

  Future<void> seedCloudFromLocal({bool overwrite = false}) async {
    if (!_firebaseEnabled) return;
    await _seedCloudFromLocal(overwrite: overwrite);
    await _syncFromCloud(seedCloudIfEmpty: false);
  }

  /// Clears all fridge items from the active household collection.
  Future<void> clearCloudForActiveHousehold({
    bool clearLocalCache = true,
  }) async {
    if (_firebaseEnabled) {
      final existingDocs = await _fridgeCollection.get();
      for (var i = 0; i < existingDocs.docs.length; i += 400) {
        final batch = _firestore!.batch();
        for (final doc in existingDocs.docs.skip(i).take(400)) {
          batch.delete(doc.reference);
        }
        await batch.commit();
      }
    }

    if (clearLocalCache) {
      _items.clear();
    }
  }

  Future<void> _seedCloudFromLocal({required bool overwrite}) async {
    if (!_firebaseEnabled) return;

    final batch = _firestore!.batch();
    if (overwrite) {
      final existingDocs = await _fridgeCollection.get();
      for (final doc in existingDocs.docs) {
        batch.delete(doc.reference);
      }
    }

    for (final item in _items) {
      batch.set(
        _fridgeCollection.doc(item.id),
        _toFirestoreMap(item, includeCreatedAt: true),
      );
    }
    await batch.commit();
  }

  // ── Read operations ──────────────────────────────────────────────

  /// All items in the fridge.
  List<FridgeItem> getAllItems() => List.unmodifiable(_items);

  /// Read all items directly from Firestore.
  Future<List<FridgeItem>> readAllFromCloud({bool refreshCache = true}) async {
    if (!_firebaseEnabled) return getAllItems();

    final query = await _fridgeCollection.get();
    final cloudItems = _parseCloudSnapshot(query.docs);

    if (refreshCache) {
      _items
        ..clear()
        ..addAll(cloudItems);
    }
    return cloudItems;
  }

  /// Items filtered by category.
  List<FridgeItem> getItemsByCategory(FridgeCategory category) =>
      _items.where((item) => item.category == category).toList();

  /// Query items by category directly from Firestore.
  Future<List<FridgeItem>> queryItemsByCategoryFromCloud(
    FridgeCategory category,
  ) async {
    if (!_firebaseEnabled) return getItemsByCategory(category);

    final query = await _fridgeCollection
        .where('category', isEqualTo: category.name)
        .get();
    return _parseCloudSnapshot(query.docs);
  }

  /// Items expiring within 2 days (urgent).
  List<FridgeItem> getExpiringItems() => _items
      .where(
        (item) =>
            item.freshnessStatus == FreshnessStatus.expiringSoon ||
            item.freshnessStatus == FreshnessStatus.expired,
      )
      .toList();

  /// Items expiring within 3–7 days.
  List<FridgeItem> getUseSoonItems() => _items
      .where((item) => item.freshnessStatus == FreshnessStatus.useSoon)
      .toList();

  /// Fresh items (> 7 days until expiry).
  List<FridgeItem> getFreshItems() => _items
      .where((item) => item.freshnessStatus == FreshnessStatus.fresh)
      .toList();

  /// Get a single item by ID.
  FridgeItem? getItemById(String id) {
    try {
      return _items.firstWhere((item) => item.id == id);
    } catch (_) {
      return null;
    }
  }

  // ── Stats ────────────────────────────────────────────────────────

  /// Returns a map with counts for UI stat cards.
  Map<String, int> getStats() {
    return {
      'urgent': getExpiringItems().length,
      'useSoon': getUseSoonItems().length,
      'healthy': getFreshItems().length,
      'total': _items.length,
    };
  }

  /// Available categories that currently have items.
  List<FridgeCategory> getActiveCategories() {
    final categories = _items.map((item) => item.category).toSet().toList();
    categories.sort((a, b) => a.index.compareTo(b.index));
    return categories;
  }

  // ── Write operations ─────────────────────────────────────────────

  /// Add a new item to the fridge.
  void addItem(FridgeItem item) {
    final normalizedItem = _normalizeForActiveHousehold(item);
    final existingIndex = _items.indexWhere(
      (existing) => existing.id == normalizedItem.id,
    );

    final isNewItem = existingIndex == -1;
    if (existingIndex == -1) {
      _items.add(normalizedItem);
    } else {
      _items[existingIndex] = normalizedItem;
    }

    if (_firebaseEnabled) {
      unawaited(_upsertItem(normalizedItem, includeCreatedAt: isNewItem));
    }
  }

  /// Update an existing item.
  void updateItem(FridgeItem updated) {
    final normalizedItem = _normalizeForActiveHousehold(updated);
    final index = _items.indexWhere((item) => item.id == normalizedItem.id);
    if (index != -1) {
      _items[index] = normalizedItem;
    }

    if (_firebaseEnabled) {
      unawaited(_upsertItem(normalizedItem, includeCreatedAt: false));
    }
  }

  bool _deleteItemInternal(String id) {
    final initialLength = _items.length;
    _items.removeWhere((item) => item.id == id);
    return _items.length < initialLength;
  }

  /// Remove an item by ID.
  void deleteItem(String id) {
    final deleted = _deleteItemInternal(id);
    if (deleted && _firebaseEnabled) {
      unawaited(_deleteItemFromCloud(id));
    }
  }

  /// Async delete API kept intentionally for future Firebase writes.
  Future<bool> deleteItemById(String id) async {
    final deleted = _deleteItemInternal(id);
    if (!deleted) return false;

    if (_firebaseEnabled) {
      try {
        await _deleteItemFromCloud(id);
      } catch (_) {
        return false;
      }
    }

    return true;
  }

  /// Search items by name (case-insensitive).
  List<FridgeItem> searchItems(String query) {
    if (query.isEmpty) return getAllItems();
    final lower = query.toLowerCase();
    return _items
        .where((item) => item.name.toLowerCase().contains(lower))
        .toList();
  }

  /// Search items by name directly from Firestore.
  Future<List<FridgeItem>> queryItemsByNameFromCloud(
    String query, {
    int limit = 30,
  }) async {
    final normalizedQuery = query.trim().toLowerCase();
    if (normalizedQuery.isEmpty || !_firebaseEnabled) {
      return searchItems(query);
    }

    try {
      final snapshot = await _fridgeCollection
          .orderBy(_nameLowerField)
          .startAt([normalizedQuery])
          .endAt(['$normalizedQuery\uf8ff'])
          .limit(limit)
          .get();
      final results = _parseCloudSnapshot(snapshot.docs);
      if (results.isNotEmpty) return results;
    } catch (_) {
      // Fallback to local cache for first-time records without the index field.
    }

    await refreshFromCloud();
    return searchItems(query);
  }

  Future<void> _upsertItem(
    FridgeItem item, {
    required bool includeCreatedAt,
  }) async {
    await _fridgeCollection
        .doc(item.id)
        .set(
          _toFirestoreMap(item, includeCreatedAt: includeCreatedAt),
          SetOptions(merge: true),
        );
  }

  Future<void> _deleteItemFromCloud(String id) async {
    await _fridgeCollection.doc(id).delete();
  }

  Map<String, dynamic> _normalizeFirestoreMap(
    Map<String, dynamic> map,
    String docId,
  ) {
    final normalized = Map<String, dynamic>.from(map);
    normalized['id'] = (normalized['id'] as String?) ?? docId;
    normalized['addedDate'] = _dateToEpochMillis(normalized['addedDate']);
    normalized['expiryDate'] = _dateToEpochMillis(normalized['expiryDate']);
    return normalized;
  }

  int? _dateToEpochMillis(dynamic value) {
    if (value == null) return null;
    if (value is int) return value;
    if (value is Timestamp) return value.millisecondsSinceEpoch;
    if (value is DateTime) return value.millisecondsSinceEpoch;
    return null;
  }

  List<FridgeItem> _parseCloudSnapshot(
    List<QueryDocumentSnapshot<Map<String, dynamic>>> docs,
  ) {
    return docs.map((doc) {
      final data = _normalizeFirestoreMap(doc.data(), doc.id);
      return FridgeItem.fromMap(data);
    }).toList();
  }

  FridgeItem _normalizeForActiveHousehold(FridgeItem item) {
    final householdId = _activeHouseholdId;
    if (item.householdId == householdId) return item;
    return item.copyWith(householdId: householdId);
  }

  Map<String, dynamic> _toFirestoreMap(
    FridgeItem item, {
    required bool includeCreatedAt,
  }) {
    final normalizedItem = _normalizeForActiveHousehold(item);
    final map = normalizedItem.toMap();
    map[_nameLowerField] = normalizedItem.name.toLowerCase();
    map.addAll(
      UserHouseholdService.instance.buildAuditFields(
        includeCreatedAt: includeCreatedAt,
      ),
    );
    return map;
  }
}
