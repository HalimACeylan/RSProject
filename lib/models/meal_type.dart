/// Meal-of-day filter applied on the Suggested Recipes screen.
///
/// Each entry carries an emoji + label for the chip UI and the list of
/// recipe tag values it should match against. A recipe is considered to
/// belong to a meal type if any of its `tags` matches any of `tagPatterns`
/// (case-insensitive). `[MealType.all]` skips filtering entirely.
///
/// Tag values come from the RAW_recipes_filtered.csv dataset — the actual
/// counts (as of the current asset DB):
///
///   breakfast 1333  brunch 1704  lunch 2424  main-dish 6178
///   beverages 1203  cocktails 359  smoothies 185  shakes 115
///   snacks 706  appetizers 2371  desserts 1864
///
/// `dinner` isn't a real tag in the dataset, so we use `main-dish` as the
/// proxy. Patterns for lunch and dinner are deliberately disjoint to avoid
/// dumping every lunch recipe into the dinner bucket too.
enum MealType {
  all('All', '🍽️', []),
  breakfast('Breakfast', '🥞', ['breakfast', 'brunch']),
  lunch('Lunch', '🥗', ['lunch']),
  dinner('Dinner', '🍝', ['main-dish']),
  beverages('Beverages', '🥤', ['beverages', 'cocktails', 'smoothies', 'shakes']),
  snacks('Snacks', '🍪', ['snacks', 'appetizers', 'desserts']);

  final String label;
  final String emoji;
  final List<String> tagPatterns;
  const MealType(this.label, this.emoji, this.tagPatterns);

  /// Whether the supplied recipe tag list satisfies this meal-type filter.
  bool matches(List<String> recipeTags) {
    if (tagPatterns.isEmpty) return true;
    for (final t in recipeTags) {
      final lower = t.toLowerCase();
      if (tagPatterns.contains(lower)) return true;
    }
    return false;
  }
}
