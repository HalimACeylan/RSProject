/// One slot in the day's meal plan.
///
/// Mirrors the Python KB's `MEAL_PLANS` table (`test_kb_recommendations.py`):
///   3 meals → [Kahvaltı, Öğle Yemeği, Akşam Yemeği]
///   4 meals → [Kahvaltı, Öğle Yemeği, Ara Öğün, Akşam Yemeği]
///   5 meals → [Kahvaltı, Ara Öğün 1, Öğle Yemeği, Ara Öğün 2, Akşam Yemeği]
///   6 meals → [Kahvaltı, Ara Öğün 1, Öğle Yemeği, Ara Öğün 2, Akşam Yemeği, Gece Atıştırması]
///
/// We surface the same slots with English labels (Snack = Ara Öğün).
class MealSlot {
  final int index;            // 0-based position in the plan
  final int totalSlots;       // matches user.mealsPerDay
  final String label;         // 'Breakfast', 'Morning Snack', …
  final String emoji;         // 🌅 🍪 🥗 🌙 …

  const MealSlot({
    required this.index,
    required this.totalSlots,
    required this.label,
    required this.emoji,
  });

  /// Number of meals still ahead of this slot (matches Python's
  /// `tracker.meals_remaining` once meals 0..index-1 have been recorded).
  int get mealsRemainingAtStart => totalSlots - index;

  @override
  bool operator ==(Object other) =>
      other is MealSlot && other.index == index && other.totalSlots == totalSlots;

  @override
  int get hashCode => Object.hash(index, totalSlots);
}

class MealPlan {
  /// English meal plan for the given meals-per-day. Order matches the Python
  /// reference. Snack name varies with the slot's position so the UI can
  /// disambiguate the two snacks in the 5-meal plan.
  static List<MealSlot> forCount(int mealsPerDay) {
    switch (mealsPerDay) {
      case 3:
        return const [
          MealSlot(index: 0, totalSlots: 3, label: 'Breakfast', emoji: '🌅'),
          MealSlot(index: 1, totalSlots: 3, label: 'Lunch',     emoji: '🥗'),
          MealSlot(index: 2, totalSlots: 3, label: 'Dinner',    emoji: '🌙'),
        ];
      case 4:
        return const [
          MealSlot(index: 0, totalSlots: 4, label: 'Breakfast', emoji: '🌅'),
          MealSlot(index: 1, totalSlots: 4, label: 'Lunch',     emoji: '🥗'),
          MealSlot(index: 2, totalSlots: 4, label: 'Snack',     emoji: '🍪'),
          MealSlot(index: 3, totalSlots: 4, label: 'Dinner',    emoji: '🌙'),
        ];
      case 5:
        return const [
          MealSlot(index: 0, totalSlots: 5, label: 'Breakfast',        emoji: '🌅'),
          MealSlot(index: 1, totalSlots: 5, label: 'Morning Snack',    emoji: '🍪'),
          MealSlot(index: 2, totalSlots: 5, label: 'Lunch',            emoji: '🥗'),
          MealSlot(index: 3, totalSlots: 5, label: 'Afternoon Snack',  emoji: '🍩'),
          MealSlot(index: 4, totalSlots: 5, label: 'Dinner',           emoji: '🌙'),
        ];
      case 6:
        return const [
          MealSlot(index: 0, totalSlots: 6, label: 'Breakfast',        emoji: '🌅'),
          MealSlot(index: 1, totalSlots: 6, label: 'Morning Snack',    emoji: '🍪'),
          MealSlot(index: 2, totalSlots: 6, label: 'Lunch',            emoji: '🥗'),
          MealSlot(index: 3, totalSlots: 6, label: 'Afternoon Snack',  emoji: '🍩'),
          MealSlot(index: 4, totalSlots: 6, label: 'Dinner',           emoji: '🌙'),
          MealSlot(index: 5, totalSlots: 6, label: 'Late Snack',       emoji: '🌃'),
        ];
      default:
        // Fall back to a 3-meal plan for any unexpected count.
        return forCount(3);
    }
  }
}
