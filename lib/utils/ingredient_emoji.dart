/// Maps an ingredient name (or any food string) to a single emoji glyph.
/// Matching is substring-based against a curated keyword → emoji table, so
/// "fresh basil leaves" and "dried basil" both resolve to 🌿.
///
/// Coverage is intentionally biased toward what appears in
/// `datasets_to_use/RAW_recipes_filtered.csv`; unmatched ingredients fall
/// back to a generic 🍽️.
library;

class IngredientEmoji {
  static const String fallback = '🍽️';

  /// Keyword → emoji. Order matters: more specific keywords come first so
  /// "egg plant" doesn't get picked up by "egg".
  static const List<MapEntry<String, String>> _entries = [
    // Vegetables (specific first)
    MapEntry('bell pepper', '🫑'),
    MapEntry('chili', '🌶️'),
    MapEntry('chile', '🌶️'),
    MapEntry('jalapeno', '🌶️'),
    MapEntry('pepper', '🫑'),
    MapEntry('eggplant', '🍆'),
    MapEntry('aubergine', '🍆'),
    MapEntry('zucchini', '🥒'),
    MapEntry('cucumber', '🥒'),
    MapEntry('carrot', '🥕'),
    MapEntry('broccoli', '🥦'),
    MapEntry('cauliflower', '🥦'),
    MapEntry('tomato', '🍅'),
    MapEntry('potato', '🥔'),
    MapEntry('sweet potato', '🍠'),
    MapEntry('yam', '🍠'),
    MapEntry('onion', '🧅'),
    MapEntry('shallot', '🧅'),
    MapEntry('scallion', '🧅'),
    MapEntry('leek', '🧅'),
    MapEntry('garlic', '🧄'),
    MapEntry('mushroom', '🍄'),
    MapEntry('spinach', '🥬'),
    MapEntry('kale', '🥬'),
    MapEntry('lettuce', '🥬'),
    MapEntry('cabbage', '🥬'),
    MapEntry('arugula', '🥬'),
    MapEntry('chard', '🥬'),
    MapEntry('greens', '🥬'),
    MapEntry('corn', '🌽'),
    MapEntry('peas', '🫛'),
    MapEntry('pea', '🫛'),
    MapEntry('beans', '🫘'),
    MapEntry('lentil', '🫘'),
    MapEntry('chickpea', '🫘'),
    MapEntry('garbanzo', '🫘'),
    MapEntry('avocado', '🥑'),
    MapEntry('olive', '🫒'),

    // Fruits
    MapEntry('apple', '🍎'),
    MapEntry('pear', '🍐'),
    MapEntry('banana', '🍌'),
    MapEntry('orange', '🍊'),
    MapEntry('tangerine', '🍊'),
    MapEntry('lemon', '🍋'),
    MapEntry('lime', '🍋'),
    MapEntry('grape', '🍇'),
    MapEntry('strawberry', '🍓'),
    MapEntry('blueberry', '🫐'),
    MapEntry('raspberry', '🍓'),
    MapEntry('berries', '🫐'),
    MapEntry('watermelon', '🍉'),
    MapEntry('melon', '🍈'),
    MapEntry('pineapple', '🍍'),
    MapEntry('mango', '🥭'),
    MapEntry('peach', '🍑'),
    MapEntry('cherry', '🍒'),
    MapEntry('kiwi', '🥝'),
    MapEntry('coconut', '🥥'),

    // Proteins
    MapEntry('chicken', '🍗'),
    MapEntry('turkey', '🍗'),
    MapEntry('duck', '🍗'),
    MapEntry('bacon', '🥓'),
    MapEntry('ham', '🥓'),
    MapEntry('beef', '🥩'),
    MapEntry('steak', '🥩'),
    MapEntry('pork', '🥩'),
    MapEntry('lamb', '🥩'),
    MapEntry('veal', '🥩'),
    MapEntry('sausage', '🌭'),
    MapEntry('hot dog', '🌭'),
    MapEntry('salmon', '🐟'),
    MapEntry('tuna', '🐟'),
    MapEntry('cod', '🐟'),
    MapEntry('tilapia', '🐟'),
    MapEntry('trout', '🐟'),
    MapEntry('fish', '🐟'),
    MapEntry('shrimp', '🦐'),
    MapEntry('prawn', '🦐'),
    MapEntry('crab', '🦀'),
    MapEntry('lobster', '🦞'),
    MapEntry('scallop', '🐚'),
    MapEntry('squid', '🦑'),
    MapEntry('octopus', '🐙'),
    MapEntry('tofu', '🥡'),
    MapEntry('tempeh', '🥡'),
    MapEntry('egg', '🥚'),

    // Dairy
    MapEntry('cheddar', '🧀'),
    MapEntry('parmesan', '🧀'),
    MapEntry('mozzarella', '🧀'),
    MapEntry('feta', '🧀'),
    MapEntry('cheese', '🧀'),
    MapEntry('butter', '🧈'),
    MapEntry('cream', '🥛'),
    MapEntry('milk', '🥛'),
    MapEntry('yogurt', '🥛'),
    MapEntry('yoghurt', '🥛'),
    MapEntry('ice cream', '🍦'),

    // Grains & bakery
    MapEntry('bread', '🍞'),
    MapEntry('baguette', '🥖'),
    MapEntry('roll', '🥐'),
    MapEntry('croissant', '🥐'),
    MapEntry('bagel', '🥯'),
    MapEntry('tortilla', '🫓'),
    MapEntry('pita', '🫓'),
    MapEntry('flatbread', '🫓'),
    MapEntry('pancake', '🥞'),
    MapEntry('waffle', '🧇'),
    MapEntry('pasta', '🍝'),
    MapEntry('spaghetti', '🍝'),
    MapEntry('noodle', '🍜'),
    MapEntry('macaroni', '🍝'),
    MapEntry('rice', '🍚'),
    MapEntry('oats', '🥣'),
    MapEntry('oatmeal', '🥣'),
    MapEntry('quinoa', '🍚'),
    MapEntry('couscous', '🍚'),
    MapEntry('barley', '🌾'),
    MapEntry('wheat', '🌾'),
    MapEntry('flour', '🌾'),
    MapEntry('cereal', '🥣'),

    // Pantry & condiments
    MapEntry('olive oil', '🫒'),
    MapEntry('oil', '🛢️'),
    MapEntry('vinegar', '🍶'),
    MapEntry('soy sauce', '🥢'),
    MapEntry('honey', '🍯'),
    MapEntry('syrup', '🍯'),
    MapEntry('jam', '🍓'),
    MapEntry('peanut', '🥜'),
    MapEntry('almond', '🥜'),
    MapEntry('walnut', '🥜'),
    MapEntry('pecan', '🥜'),
    MapEntry('cashew', '🥜'),
    MapEntry('hazelnut', '🥜'),
    MapEntry('pistachio', '🥜'),
    MapEntry('nut', '🥜'),
    MapEntry('seed', '🌰'),

    // Herbs & spices
    MapEntry('basil', '🌿'),
    MapEntry('parsley', '🌿'),
    MapEntry('cilantro', '🌿'),
    MapEntry('coriander', '🌿'),
    MapEntry('mint', '🌿'),
    MapEntry('thyme', '🌿'),
    MapEntry('rosemary', '🌿'),
    MapEntry('oregano', '🌿'),
    MapEntry('sage', '🌿'),
    MapEntry('dill', '🌿'),
    MapEntry('chive', '🌿'),
    MapEntry('ginger', '🫚'),
    MapEntry('cinnamon', '🟤'),
    MapEntry('vanilla', '🟤'),
    MapEntry('salt', '🧂'),
    MapEntry('sugar', '🍬'),
    MapEntry('cocoa', '🍫'),
    MapEntry('chocolate', '🍫'),

    // Drinks
    MapEntry('water', '💧'),
    MapEntry('wine', '🍷'),
    MapEntry('beer', '🍺'),
    MapEntry('coffee', '☕'),
    MapEntry('tea', '🍵'),
    MapEntry('juice', '🧃'),
    MapEntry('broth', '🍲'),
    MapEntry('stock', '🍲'),
  ];

  /// Resolve a single ingredient name to an emoji. Always returns something.
  static String forIngredient(String name) {
    final n = name.toLowerCase();
    for (final entry in _entries) {
      if (n.contains(entry.key)) return entry.value;
    }
    return fallback;
  }

  /// Pick up to [max] *distinct* emojis from the ingredient list, preserving
  /// order. Useful for a thumbnail collage that summarises a recipe.
  static List<String> pickDistinct(Iterable<String> ingredients, {int max = 4}) {
    final result = <String>[];
    for (final ing in ingredients) {
      final e = forIngredient(ing);
      if (e == fallback) continue;
      if (!result.contains(e)) result.add(e);
      if (result.length >= max) break;
    }
    if (result.isEmpty) result.add(fallback);
    return result;
  }
}
