import 'package:flutter/material.dart';
import 'package:fridge_app/models/units.dart';

/// Categories for fridge items — aligned with what can be scanned from receipts
/// and featuring highly specific food emojis.
enum FridgeCategory {
  // Produce (Broad)
  produce(
    label: 'Produce',
    emoji: '🥬',
    color: Color(0xFF43A047),
    defaultExpiryDays: 5,
  ),
  fruits(
    label: 'Fruits',
    emoji: '🍎',
    color: Color(0xFF43A047),
    defaultExpiryDays: 7,
  ),
  vegetables(
    label: 'Vegetables',
    emoji: '🥦',
    color: Color(0xFF43A047),
    defaultExpiryDays: 5,
  ),

  // Specific Fruits
  apple(
    label: 'Apple',
    emoji: '🍎',
    color: Color(0xFFE53935),
    defaultExpiryDays: 21,
  ),
  pear(
    label: 'Pear',
    emoji: '🍐',
    color: Color(0xFF7CB342),
    defaultExpiryDays: 14,
  ),
  orange(
    label: 'Orange',
    emoji: '🍊',
    color: Color(0xFFF4511E),
    defaultExpiryDays: 21,
  ),
  lemon(
    label: 'Lemon',
    emoji: '🍋',
    color: Color(0xFFFDD835),
    defaultExpiryDays: 30,
  ),
  banana(
    label: 'Banana',
    emoji: '🍌',
    color: Color(0xFFFFEB3B),
    defaultExpiryDays: 7,
  ),
  watermelon(
    label: 'Watermelon',
    emoji: '🍉',
    color: Color(0xFFE53935),
    defaultExpiryDays: 5,
  ),
  grapes(
    label: 'Grapes',
    emoji: '🍇',
    color: Color(0xFF8E24AA),
    defaultExpiryDays: 10,
  ),
  strawberry(
    label: 'Strawberry',
    emoji: '🍓',
    color: Color(0xFFE53935),
    defaultExpiryDays: 5,
  ),
  blueberry(
    label: 'Blueberry',
    emoji: '🫐',
    color: Color(0xFF3949AB),
    defaultExpiryDays: 7,
  ),
  melon(
    label: 'Melon',
    emoji: '🍈',
    color: Color(0xFFC0CA33),
    defaultExpiryDays: 7,
  ),
  cherry(
    label: 'Cherry',
    emoji: '🍒',
    color: Color(0xFFD32F2F),
    defaultExpiryDays: 7,
  ),
  peach(
    label: 'Peach',
    emoji: '🍑',
    color: Color(0xFFFF7043),
    defaultExpiryDays: 5,
  ),
  mango(
    label: 'Mango',
    emoji: '🥭',
    color: Color(0xFFFFB300),
    defaultExpiryDays: 7,
  ),
  pineapple(
    label: 'Pineapple',
    emoji: '🍍',
    color: Color(0xFFFFCA28),
    defaultExpiryDays: 7,
  ),
  coconut(
    label: 'Coconut',
    emoji: '🥥',
    color: Color(0xFF8D6E63),
    defaultExpiryDays: 14,
  ),
  kiwi(
    label: 'Kiwi',
    emoji: '🥝',
    color: Color(0xFF7CB342),
    defaultExpiryDays: 14,
  ),
  avocado(
    label: 'Avocado',
    emoji: '🥑',
    color: Color(0xFF43A047),
    defaultExpiryDays: 5,
  ),

  // Specific Vegetables
  tomato(
    label: 'Tomato',
    emoji: '🍅',
    color: Color(0xFFE53935),
    defaultExpiryDays: 10,
  ),
  potato(
    label: 'Potato',
    emoji: '🥔',
    color: Color(0xFF8D6E63),
    defaultExpiryDays: 30,
  ),
  carrot(
    label: 'Carrot',
    emoji: '🥕',
    color: Color(0xFFFB8C00),
    defaultExpiryDays: 21,
  ),
  corn(
    label: 'Corn',
    emoji: '🌽',
    color: Color(0xFFFFEB3B),
    defaultExpiryDays: 5,
  ),
  hotPepper(
    label: 'Hot Pepper',
    emoji: '🌶️',
    color: Color(0xFFD32F2F),
    defaultExpiryDays: 14,
  ),
  bellPepper(
    label: 'Bell Pepper',
    emoji: '🫑',
    color: Color(0xFF43A047),
    defaultExpiryDays: 10,
  ),
  cucumber(
    label: 'Cucumber',
    emoji: '🥒',
    color: Color(0xFF66BB6A),
    defaultExpiryDays: 7,
  ),
  leafyGreen(
    label: 'Leafy Green',
    emoji: '🥬',
    color: Color(0xFF43A047),
    defaultExpiryDays: 5,
  ),
  broccoli(
    label: 'Broccoli',
    emoji: '🥦',
    color: Color(0xFF388E3C),
    defaultExpiryDays: 5,
  ),
  garlic(
    label: 'Garlic',
    emoji: '🧄',
    color: Color(0xFFD7CCC8),
    defaultExpiryDays: 60,
  ),
  onion(
    label: 'Onion',
    emoji: '🧅',
    color: Color(0xFFBCAAA4),
    defaultExpiryDays: 30,
  ),
  mushroom(
    label: 'Mushroom',
    emoji: '🍄',
    color: Color(0xFF8D6E63),
    defaultExpiryDays: 5,
  ),
  eggplant(
    label: 'Eggplant',
    emoji: '🍆',
    color: Color(0xFF7B1FA2),
    defaultExpiryDays: 7,
  ),
  sweetPotato(
    label: 'Sweet Potato',
    emoji: '🍠',
    color: Color(0xFF7B1FA2),
    defaultExpiryDays: 30,
  ),

  // Dairy (Broad)
  dairy(
    label: 'Dairy',
    emoji: '🥛',
    color: Color(0xFF42A5F5),
    defaultExpiryDays: 7,
  ),

  // Specific Dairy & Eggs
  milk(
    label: 'Milk',
    emoji: '🥛',
    color: Color(0xFFE3F2FD),
    defaultExpiryDays: 7,
  ),
  cheese(
    label: 'Cheese',
    emoji: '🧀',
    color: Color(0xFFFFCA28),
    defaultExpiryDays: 21,
  ),
  butter(
    label: 'Butter',
    emoji: '🧈',
    color: Color(0xFFFFE082),
    defaultExpiryDays: 30,
  ),
  egg(
    label: 'Egg',
    emoji: '🥚',
    color: Color(0xFFFFECB3),
    defaultExpiryDays: 21,
  ),

  // Meat & Seafood (Broad)
  meat(
    label: 'Meat & Seafood',
    emoji: '🥩',
    color: Color(0xFFE57373),
    defaultExpiryDays: 3,
  ),

  // Specific Meat & Seafood
  poultry(
    label: 'Poultry',
    emoji: '🍗',
    color: Color(0xFF8D6E63),
    defaultExpiryDays: 3,
  ),
  beef(
    label: 'Beef',
    emoji: '🥩',
    color: Color(0xFFD32F2F),
    defaultExpiryDays: 3,
  ),
  bacon(
    label: 'Bacon',
    emoji: '🥓',
    color: Color(0xFFE57373),
    defaultExpiryDays: 7,
  ),
  hotDog(
    label: 'Hot Dog / Sausage',
    emoji: '🌭',
    color: Color(0xFFE53935),
    defaultExpiryDays: 7,
  ),
  fish(
    label: 'Fish',
    emoji: '��',
    color: Color(0xFF42A5F5),
    defaultExpiryDays: 2,
  ),
  shrimp(
    label: 'Shrimp',
    emoji: '🍤',
    color: Color(0xFFFFCC80),
    defaultExpiryDays: 2,
  ),
  squid(
    label: 'Squid',
    emoji: '🦑',
    color: Color(0xFFEF9A9A),
    defaultExpiryDays: 2,
  ),
  lobster(
    label: 'Lobster',
    emoji: '🦞',
    color: Color(0xFFD32F2F),
    defaultExpiryDays: 2,
  ),
  crab(
    label: 'Crab',
    emoji: '🦀',
    color: Color(0xFFE53935),
    defaultExpiryDays: 2,
  ),
  oyster(
    label: 'Oyster',
    emoji: '🦪',
    color: Color(0xFFB0BEC5),
    defaultExpiryDays: 2,
  ),

  // Grains & Bakery (Broad)
  grains(
    label: 'Grains & Bakery',
    emoji: '🌾',
    color: Color(0xFFD4A373),
    defaultExpiryDays: 14,
  ),

  // Specific Grains & Bakery
  bread(
    label: 'Bread',
    emoji: '🍞',
    color: Color(0xFFFFCC80),
    defaultExpiryDays: 7,
  ),
  croissant(
    label: 'Croissant',
    emoji: '🥐',
    color: Color(0xFFFFB74D),
    defaultExpiryDays: 3,
  ),
  baguette(
    label: 'Baguette',
    emoji: '🥖',
    color: Color(0xFFFFCC80),
    defaultExpiryDays: 2,
  ),
  flatbread(
    label: 'Flatbread',
    emoji: '🫓',
    color: Color(0xFFFFE082),
    defaultExpiryDays: 5,
  ),
  pretzel(
    label: 'Pretzel',
    emoji: '🥨',
    color: Color(0xFF8D6E63),
    defaultExpiryDays: 7,
  ),
  bagel(
    label: 'Bagel',
    emoji: '🥯',
    color: Color(0xFFFFCC80),
    defaultExpiryDays: 5,
  ),
  pancakes(
    label: 'Pancakes',
    emoji: '🥞',
    color: Color(0xFFFFB74D),
    defaultExpiryDays: 3,
  ),
  waffle(
    label: 'Waffle',
    emoji: '🧇',
    color: Color(0xFFFFB74D),
    defaultExpiryDays: 3,
  ),
  rice(
    label: 'Rice',
    emoji: '🍚',
    color: Color(0xFFEEEEEE),
    defaultExpiryDays: 180,
  ),
  pasta(
    label: 'Pasta',
    emoji: '🍝',
    color: Color(0xFFFFCA28),
    defaultExpiryDays: 180,
  ), // dry

  // Prepared Foods & Fast Food
  pizza(
    label: 'Pizza',
    emoji: '🍕',
    color: Color(0xFFE53935),
    defaultExpiryDays: 3,
  ),
  frozenPizza(
    label: 'Frozen Pizza',
    emoji: '❄️🍕',
    color: Color(0xFF90CAF9),
    defaultExpiryDays: 90,
  ),
  hamburger(
    label: 'Hamburger',
    emoji: '🍔',
    color: Color(0xFF8D6E63),
    defaultExpiryDays: 3,
  ),
  fries(
    label: 'Fries',
    emoji: '🍟',
    color: Color(0xFFFFCA28),
    defaultExpiryDays: 2,
  ),
  sandwich(
    label: 'Sandwich',
    emoji: '🥪',
    color: Color(0xFF81C784),
    defaultExpiryDays: 3,
  ),
  taco(
    label: 'Taco',
    emoji: '🌮',
    color: Color(0xFFFFCA28),
    defaultExpiryDays: 3,
  ),
  burrito(
    label: 'Burrito',
    emoji: '🌯',
    color: Color(0xFFD4A373),
    defaultExpiryDays: 3,
  ),
  sushi(
    label: 'Sushi',
    emoji: '🍣',
    color: Color(0xFFF06292),
    defaultExpiryDays: 1,
  ),
  bento(
    label: 'Bento',
    emoji: '🍱',
    color: Color(0xFF26A69A),
    defaultExpiryDays: 2,
  ),
  curry(
    label: 'Curry',
    emoji: '🍛',
    color: Color(0xFFFFB300),
    defaultExpiryDays: 4,
  ),
  stew(
    label: 'Stew / Soup',
    emoji: '🍲',
    color: Color(0xFF8D6E63),
    defaultExpiryDays: 4,
  ),
  dumpling(
    label: 'Dumpling',
    emoji: '🥟',
    color: Color(0xFFFFE082),
    defaultExpiryDays: 3,
  ),

  // Condiments (Broad)
  condiments(
    label: 'Condiments',
    emoji: '🫙',
    color: Color(0xFFFFA726),
    defaultExpiryDays: 60,
  ),

  // Specific Condiments & Cooking
  salt(
    label: 'Salt',
    emoji: '🧂',
    color: Color(0xFFE0E0E0),
    defaultExpiryDays: 365,
  ),
  sauce(
    label: 'Sauce',
    emoji: '🥫',
    color: Color(0xFFE53935),
    defaultExpiryDays: 90,
  ), // canned/jarred
  honey(
    label: 'Honey',
    emoji: '🍯',
    color: Color(0xFFFFB300),
    defaultExpiryDays: 365,
  ),

  // Snacks & Sweets
  snacks(
    label: 'Snacks',
    emoji: '🍿',
    color: Color(0xFFBA68C8),
    defaultExpiryDays: 14,
  ),
  popcorn(
    label: 'Popcorn',
    emoji: '🍿',
    color: Color(0xFFFFCA28),
    defaultExpiryDays: 14,
  ),
  chips(
    label: 'Chips',
    emoji: '🥔🍟',
    color: Color(0xFFFFCA28),
    defaultExpiryDays: 30,
  ), // composite attempt or use potato
  cookie(
    label: 'Cookie',
    emoji: '🍪',
    color: Color(0xFF8D6E63),
    defaultExpiryDays: 14,
  ),
  chocolate(
    label: 'Chocolate',
    emoji: '🍫',
    color: Color(0xFF5D4037),
    defaultExpiryDays: 180,
  ),
  candy(
    label: 'Candy',
    emoji: '🍬',
    color: Color(0xFFE91E63),
    defaultExpiryDays: 180,
  ),
  lollipop(
    label: 'Lollipop',
    emoji: '🍭',
    color: Color(0xFFF06292),
    defaultExpiryDays: 180,
  ),
  iceCream(
    label: 'Ice Cream',
    emoji: '🍦',
    color: Color(0xFF90CAF9),
    defaultExpiryDays: 60,
  ),
  cake(
    label: 'Cake',
    emoji: '🍰',
    color: Color(0xFFEC407A),
    defaultExpiryDays: 5,
  ),
  pie(
    label: 'Pie',
    emoji: '🥧',
    color: Color(0xFFFFB74D),
    defaultExpiryDays: 5,
  ),

  // Beverages (Broad)
  beverages(
    label: 'Beverages',
    emoji: '🧃',
    color: Color(0xFF26C6DA),
    defaultExpiryDays: 14,
  ),

  // Specific Beverages
  water(
    label: 'Water',
    emoji: '💧',
    color: Color(0xFF29B6F6),
    defaultExpiryDays: 365,
  ),
  juice(
    label: 'Juice',
    emoji: '🧃',
    color: Color(0xFF66BB6A),
    defaultExpiryDays: 14,
  ),
  soda(
    label: 'Soda / Pop',
    emoji: '🥤',
    color: Color(0xFFE53935),
    defaultExpiryDays: 180,
  ),
  tea(
    label: 'Tea',
    emoji: '🍵',
    color: Color(0xFF81C784),
    defaultExpiryDays: 180,
  ),
  coffee(
    label: 'Coffee',
    emoji: '☕',
    color: Color(0xFF5D4037),
    defaultExpiryDays: 30,
  ),
  beer(
    label: 'Beer',
    emoji: '🍺',
    color: Color(0xFFFFCA28),
    defaultExpiryDays: 180,
  ),
  wine(
    label: 'Wine',
    emoji: '🍷',
    color: Color(0xFF880E4F),
    defaultExpiryDays: 365,
  ),
  liquor(
    label: 'Liquor',
    emoji: '🥃',
    color: Color(0xFFFFB300),
    defaultExpiryDays: 365,
  ),

  // Frozen (Broad)
  frozen(
    label: 'Frozen',
    emoji: '🧊',
    color: Color(0xFF90CAF9),
    defaultExpiryDays: 90,
  ),
  iceCube(
    label: 'Ice',
    emoji: '🧊',
    color: Color(0xFFB3E5FC),
    defaultExpiryDays: 365,
  ),

  // Other (Catch-all)
  other(
    label: 'Other',
    emoji: '📦',
    color: Color(0xFF9E9E9E),
    defaultExpiryDays: 7,
  );

  final String label;
  final String emoji;
  final Color color;
  final int defaultExpiryDays;

  const FridgeCategory({
    required this.label,
    required this.emoji,
    required this.color,
    required this.defaultExpiryDays,
  });

  String get displayName => '$emoji $label';
}

/// Freshness status computed from the expiry date.
enum FreshnessStatus {
  fresh,
  useSoon,
  expiringSoon,
  expired;

  String get label {
    switch (this) {
      case FreshnessStatus.fresh:
        return 'Fresh';
      case FreshnessStatus.useSoon:
        return 'Use Soon';
      case FreshnessStatus.expiringSoon:
        return 'Expiring Soon';
      case FreshnessStatus.expired:
        return 'Expired';
    }
  }
}

/// Core domain model representing an item stored in the fridge.
///
/// Price is intentionally omitted — spending data will be derived from
/// linked receipts via [receiptId] in the future.
///
/// [amount] + [unit] represent quantity using the standardized unit system:
///   - Weight: grams (g) / ounces (oz)
///   - Volume: milliliters (ml) / gallons (gal)
///   - Countable: pieces (pcs)
class FridgeItem {
  final String id;
  final String name;
  final FridgeCategory category;
  final double amount;
  final FridgeUnit unit;
  final DateTime? expiryDate;
  final DateTime addedDate;
  final String? imageUrl;
  final String? notes;
  final String? receiptId;
  final String householdId;
  final bool isFrozen;

  const FridgeItem({
    required this.id,
    required this.name,
    required this.category,
    this.amount = 1,
    this.unit = FridgeUnit.pieces,
    this.expiryDate,
    required this.addedDate,
    this.imageUrl,
    this.notes,
    this.receiptId,
    this.householdId = 'default',
    this.isFrozen = false,
  });

  // ── Computed properties ──────────────────────────────────────────

  /// Days remaining until expiry. Null if no expiry set.
  int? get daysUntilExpiry {
    if (expiryDate == null) return null;
    return expiryDate!.difference(DateTime.now()).inDays;
  }

  /// Freshness derived from days until expiry.
  FreshnessStatus get freshnessStatus {
    final days = daysUntilExpiry;
    if (days == null) return FreshnessStatus.fresh;
    if (days < 0) return FreshnessStatus.expired;
    if (days <= 2) return FreshnessStatus.expiringSoon;
    if (days <= 7) return FreshnessStatus.useSoon;
    return FreshnessStatus.fresh;
  }

  /// Human-readable expiry string for the UI.
  String get expiryDisplayText {
    final days = daysUntilExpiry;
    if (days == null) return 'No expiry';
    if (days < 0) return 'Expired ${-days} day${-days == 1 ? '' : 's'} ago';
    if (days == 0) return 'Expires today';
    if (days == 1) return 'Expires tomorrow';
    return '$days days left';
  }

  /// Formatted amount with unit (e.g. "250 g", "1 gal", "3 pcs").
  String get amountDisplay => UnitConverter.format(amount, unit);

  /// Amount converted to metric base unit (grams or ml).
  /// Returns null for pieces.
  double? get amountInMetric => UnitConverter.toMetric(amount, unit);

  /// Amount converted to imperial unit (oz or gal).
  /// Returns null for pieces.
  double? get amountInImperial => UnitConverter.toImperial(amount, unit);

  // ── Serialization (Firebase-ready) ───────────────────────────────

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'name': name,
      'category': category.name,
      'amount': amount,
      'unit': unit.name,
      'expiryDate': expiryDate?.millisecondsSinceEpoch,
      'addedDate': addedDate.millisecondsSinceEpoch,
      'imageUrl': imageUrl,
      'notes': notes,
      'receiptId': receiptId,
      'householdId': householdId,
      'isFrozen': isFrozen,
    };
  }

  factory FridgeItem.fromMap(Map<String, dynamic> map) {
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
      expiryDate: map['expiryDate'] != null
          ? DateTime.fromMillisecondsSinceEpoch(map['expiryDate'] as int)
          : null,
      addedDate: DateTime.fromMillisecondsSinceEpoch(map['addedDate'] as int),
      imageUrl: map['imageUrl'] as String?,
      notes: map['notes'] as String?,
      receiptId: map['receiptId'] as String?,
      householdId: map['householdId'] as String? ?? 'default',
      isFrozen: map['isFrozen'] as bool? ?? false,
    );
  }

  // ── Copy helper ──────────────────────────────────────────────────

  FridgeItem copyWith({
    String? id,
    String? name,
    FridgeCategory? category,
    double? amount,
    FridgeUnit? unit,
    DateTime? expiryDate,
    DateTime? addedDate,
    String? imageUrl,
    String? notes,
    String? receiptId,
    String? householdId,
    bool? isFrozen,
  }) {
    return FridgeItem(
      id: id ?? this.id,
      name: name ?? this.name,
      category: category ?? this.category,
      amount: amount ?? this.amount,
      unit: unit ?? this.unit,
      expiryDate: expiryDate ?? this.expiryDate,
      addedDate: addedDate ?? this.addedDate,
      imageUrl: imageUrl ?? this.imageUrl,
      notes: notes ?? this.notes,
      receiptId: receiptId ?? this.receiptId,
      householdId: householdId ?? this.householdId,
      isFrozen: isFrozen ?? this.isFrozen,
    );
  }

  @override
  String toString() =>
      'FridgeItem(id: $id, name: $name, $amountDisplay, category: ${category.label})';
}
