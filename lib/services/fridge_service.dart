import 'package:fridge_app/models/fridge_item.dart';
import 'package:fridge_app/models/units.dart';
import 'package:fridge_app/services/database_service.dart';

/// Fridge service backed by local SQLite database.
///
/// Maintains the same public API as the previous Firebase-backed version
/// so that all screen widgets continue to work without changes.
class FridgeService {
  // Singleton
  FridgeService._();
  static final FridgeService instance = FridgeService._();

  final List<FridgeItem> _items = [];
  bool _isInitialized = false;

  // ── Sample data (seeds DB on first launch) ────────────────────────

  static List<FridgeItem> get _sampleItems => [
    // ── Produce ────────────────────────────────────────────────────
    FridgeItem(
      id: 'item_001', name: 'Fresh Spinach',
      category: FridgeCategory.produce, amount: 250, unit: FridgeUnit.grams,
      expiryDate: DateTime.now().add(const Duration(days: 0)),
      addedDate: DateTime.now().subtract(const Duration(days: 3)),
      imageUrl: 'assets/images/spinach.png', notes: 'Packaged Bag',
    ),
    FridgeItem(
      id: 'item_002', name: 'Organic Avocados',
      category: FridgeCategory.produce, amount: 3, unit: FridgeUnit.pieces,
      expiryDate: DateTime.now().add(const Duration(days: 2)),
      addedDate: DateTime.now().subtract(const Duration(days: 2)),
      imageUrl: 'assets/images/avocado.png',
    ),
    FridgeItem(
      id: 'item_003', name: 'Mixed Veggies',
      category: FridgeCategory.produce, amount: 400, unit: FridgeUnit.grams,
      expiryDate: DateTime.now().add(const Duration(days: 5)),
      addedDate: DateTime.now().subtract(const Duration(days: 1)),
    ),
    FridgeItem(
      id: 'item_004', name: 'Kale',
      category: FridgeCategory.produce, amount: 1, unit: FridgeUnit.pieces,
      expiryDate: DateTime.now().add(const Duration(days: 4)),
      addedDate: DateTime.now().subtract(const Duration(days: 2)),
      notes: '1 bunch',
    ),
    FridgeItem(
      id: 'item_005', name: 'Fresh Basil',
      category: FridgeCategory.produce, amount: 30, unit: FridgeUnit.grams,
      expiryDate: DateTime.now().add(const Duration(days: 3)),
      addedDate: DateTime.now().subtract(const Duration(days: 1)),
    ),
    FridgeItem(
      id: 'item_006', name: 'Bell Peppers',
      category: FridgeCategory.produce, amount: 3, unit: FridgeUnit.pieces,
      expiryDate: DateTime.now().add(const Duration(days: 6)),
      addedDate: DateTime.now().subtract(const Duration(days: 1)),
    ),
    FridgeItem(
      id: 'item_007', name: 'Cherry Tomatoes',
      category: FridgeCategory.produce, amount: 300, unit: FridgeUnit.grams,
      expiryDate: DateTime.now().add(const Duration(days: 5)),
      addedDate: DateTime.now().subtract(const Duration(days: 2)),
    ),
    // ── Dairy ──────────────────────────────────────────────────────
    FridgeItem(
      id: 'item_010', name: 'Whole Milk',
      category: FridgeCategory.dairy, amount: 1, unit: FridgeUnit.gallons,
      expiryDate: DateTime.now().add(const Duration(days: 2)),
      addedDate: DateTime.now().subtract(const Duration(days: 5)),
      notes: 'Opened',
    ),
    FridgeItem(
      id: 'item_011', name: 'Greek Yogurt',
      category: FridgeCategory.dairy, amount: 500, unit: FridgeUnit.grams,
      expiryDate: DateTime.now().add(const Duration(days: 10)),
      addedDate: DateTime.now().subtract(const Duration(days: 2)),
    ),
    FridgeItem(
      id: 'item_012', name: 'Cheddar Cheese',
      category: FridgeCategory.dairy, amount: 200, unit: FridgeUnit.grams,
      expiryDate: DateTime.now().add(const Duration(days: 14)),
      addedDate: DateTime.now().subtract(const Duration(days: 3)),
    ),
    FridgeItem(
      id: 'item_013', name: 'Large Brown Eggs',
      category: FridgeCategory.dairy, amount: 12, unit: FridgeUnit.pieces,
      expiryDate: DateTime.now().add(const Duration(days: 12)),
      addedDate: DateTime.now().subtract(const Duration(days: 3)),
      notes: '12ct carton',
    ),
    // ── Meat & Seafood ─────────────────────────────────────────────
    FridgeItem(
      id: 'item_020', name: 'Salmon Fillet',
      category: FridgeCategory.meat, amount: 400, unit: FridgeUnit.grams,
      expiryDate: DateTime.now().add(const Duration(days: 0)),
      addedDate: DateTime.now().subtract(const Duration(days: 2)),
      notes: 'Raw, 2 fillets',
    ),
    FridgeItem(
      id: 'item_021', name: 'Chicken Breast',
      category: FridgeCategory.meat, amount: 800, unit: FridgeUnit.grams,
      expiryDate: DateTime.now().add(const Duration(days: 1)),
      addedDate: DateTime.now().subtract(const Duration(days: 1)),
      notes: '4 pieces',
    ),
    // ── Beverages ──────────────────────────────────────────────────
    FridgeItem(
      id: 'item_030', name: 'Orange Juice',
      category: FridgeCategory.beverages, amount: 1000, unit: FridgeUnit.milliliters,
      expiryDate: DateTime.now().add(const Duration(days: 8)),
      addedDate: DateTime.now().subtract(const Duration(days: 4)),
    ),
    // ── Condiments ─────────────────────────────────────────────────
    FridgeItem(
      id: 'item_040', name: 'Soy Sauce',
      category: FridgeCategory.condiments, amount: 500, unit: FridgeUnit.milliliters,
      expiryDate: DateTime.now().add(const Duration(days: 90)),
      addedDate: DateTime.now().subtract(const Duration(days: 30)),
    ),
    FridgeItem(
      id: 'item_041', name: 'Pesto Sauce',
      category: FridgeCategory.condiments, amount: 200, unit: FridgeUnit.grams,
      expiryDate: DateTime.now().add(const Duration(days: 7)),
      addedDate: DateTime.now().subtract(const Duration(days: 5)),
    ),
    // ── Grains & Bakery ────────────────────────────────────────────
    FridgeItem(
      id: 'item_050', name: 'Sourdough Bread',
      category: FridgeCategory.grains, amount: 1, unit: FridgeUnit.pieces,
      expiryDate: DateTime.now().add(const Duration(days: 3)),
      addedDate: DateTime.now().subtract(const Duration(days: 1)),
      notes: '1 loaf',
    ),
    FridgeItem(
      id: 'item_051', name: 'Pasta',
      category: FridgeCategory.grains, amount: 500, unit: FridgeUnit.grams,
      expiryDate: DateTime.now().add(const Duration(days: 180)),
      addedDate: DateTime.now().subtract(const Duration(days: 10)),
      notes: '2 packs',
    ),
    // ── Frozen ─────────────────────────────────────────────────────
    FridgeItem(
      id: 'item_060', name: 'Frozen Berries',
      category: FridgeCategory.frozen, amount: 500, unit: FridgeUnit.grams,
      expiryDate: DateTime.now().add(const Duration(days: 60)),
      addedDate: DateTime.now().subtract(const Duration(days: 7)),
    ),
    FridgeItem(
      id: 'item_061', name: 'Ice Cream',
      category: FridgeCategory.frozen, amount: 1000, unit: FridgeUnit.milliliters,
      expiryDate: DateTime.now().add(const Duration(days: 90)),
      addedDate: DateTime.now().subtract(const Duration(days: 5)),
    ),
    // ── Snacks ─────────────────────────────────────────────────────
    FridgeItem(
      id: 'item_070', name: 'Hummus',
      category: FridgeCategory.snacks, amount: 250, unit: FridgeUnit.grams,
      expiryDate: DateTime.now().add(const Duration(days: 6)),
      addedDate: DateTime.now().subtract(const Duration(days: 3)),
    ),
  ];

  // ── Initialization ──────────────────────────────────────────────

  Future<void> initialize() async {
    if (_isInitialized) return;
    _isInitialized = true;

    final dbService = DatabaseService.instance;
    final count = await dbService.count('fridge_items');
    if (count == 0) {
      // Seed DB with sample data
      for (final item in _sampleItems) {
        await dbService.insert('fridge_items', _toDbMap(item));
      }
    }

    // Load from DB into memory cache
    await _loadFromDb();
  }

  /// No-op — kept for API compatibility with screens that used the Firebase version.
  Future<void> refreshFromCloud() async {
    await _loadFromDb();
  }

  Future<void> _loadFromDb() async {
    final rows = await DatabaseService.instance.queryAll('fridge_items');
    _items
      ..clear()
      ..addAll(rows.map(_fromDbMap));
  }

  // ── Read operations ──────────────────────────────────────────────

  List<FridgeItem> getAllItems() => List.unmodifiable(_items);

  List<FridgeItem> getItemsByCategory(FridgeCategory category) =>
      _items.where((item) => item.category == category).toList();

  List<FridgeItem> getExpiringItems() => _items
      .where((item) =>
          item.freshnessStatus == FreshnessStatus.expiringSoon ||
          item.freshnessStatus == FreshnessStatus.expired)
      .toList();

  List<FridgeItem> getUseSoonItems() => _items
      .where((item) => item.freshnessStatus == FreshnessStatus.useSoon)
      .toList();

  List<FridgeItem> getFreshItems() => _items
      .where((item) => item.freshnessStatus == FreshnessStatus.fresh)
      .toList();

  FridgeItem? getItemById(String id) {
    try {
      return _items.firstWhere((item) => item.id == id);
    } catch (_) {
      return null;
    }
  }

  // ── Stats ────────────────────────────────────────────────────────

  Map<String, int> getStats() {
    return {
      'urgent': getExpiringItems().length,
      'useSoon': getUseSoonItems().length,
      'healthy': getFreshItems().length,
      'total': _items.length,
    };
  }

  List<FridgeCategory> getActiveCategories() {
    final categories = _items.map((item) => item.category).toSet().toList();
    categories.sort((a, b) => a.index.compareTo(b.index));
    return categories;
  }

  // ── Write operations ─────────────────────────────────────────────

  void addItem(FridgeItem item) {
    final existingIndex = _items.indexWhere((e) => e.id == item.id);
    if (existingIndex == -1) {
      _items.add(item);
    } else {
      _items[existingIndex] = item;
    }
    DatabaseService.instance.insert('fridge_items', _toDbMap(item));
  }

  void updateItem(FridgeItem updated) {
    final index = _items.indexWhere((item) => item.id == updated.id);
    if (index != -1) {
      _items[index] = updated;
    }
    DatabaseService.instance.update(
      'fridge_items',
      _toDbMap(updated),
      where: 'id = ?',
      whereArgs: [updated.id],
    );
  }

  void deleteItem(String id) {
    _items.removeWhere((item) => item.id == id);
    DatabaseService.instance.delete('fridge_items', where: 'id = ?', whereArgs: [id]);
  }

  Future<bool> deleteItemById(String id) async {
    final initialLength = _items.length;
    _items.removeWhere((item) => item.id == id);
    if (_items.length >= initialLength) return false;
    await DatabaseService.instance.delete('fridge_items', where: 'id = ?', whereArgs: [id]);
    return true;
  }

  List<FridgeItem> searchItems(String query) {
    if (query.isEmpty) return getAllItems();
    final lower = query.toLowerCase();
    return _items.where((item) => item.name.toLowerCase().contains(lower)).toList();
  }

  // ── DB Map helpers ──────────────────────────────────────────────

  Map<String, dynamic> _toDbMap(FridgeItem item) {
    return {
      'id': item.id,
      'name': item.name,
      'category': item.category.name,
      'amount': item.amount,
      'unit': item.unit.name,
      'expiry_date': item.expiryDate?.millisecondsSinceEpoch,
      'added_date': item.addedDate.millisecondsSinceEpoch,
      'image_url': item.imageUrl,
      'notes': item.notes,
      'receipt_id': item.receiptId,
      'household_id': item.householdId,
      'is_frozen': item.isFrozen ? 1 : 0,
    };
  }

  FridgeItem _fromDbMap(Map<String, dynamic> map) {
    return FridgeItem(
      id: map['id'] as String,
      name: map['name'] as String,
      category: FridgeCategory.values.firstWhere(
        (c) => c.name == map['category'],
        orElse: () => FridgeCategory.other,
      ),
      amount: (map['amount'] as num?)?.toDouble() ?? 1,
      unit: FridgeUnit.values.firstWhere(
        (u) => u.name == map['unit'],
        orElse: () => FridgeUnit.pieces,
      ),
      expiryDate: map['expiry_date'] != null
          ? DateTime.fromMillisecondsSinceEpoch(map['expiry_date'] as int)
          : null,
      addedDate: DateTime.fromMillisecondsSinceEpoch(map['added_date'] as int),
      imageUrl: map['image_url'] as String?,
      notes: map['notes'] as String?,
      receiptId: map['receipt_id'] as String?,
      householdId: map['household_id'] as String? ?? 'default',
      isFrozen: (map['is_frozen'] as int?) == 1,
    );
  }
}
