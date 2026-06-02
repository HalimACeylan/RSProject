import 'package:flutter/material.dart';
import 'package:fridge_app/models/recipe.dart';

/// Result returned from [RecipeRatingBottomSheet].
class CookConfirmation {
  /// 1-5 star rating, or null if the user tapped "Skip".
  final int? rating;
  const CookConfirmation({this.rating});
}

/// Modal bottom sheet shown when the user taps "Mark Cooked" on the recipe
/// preparation screen. Captures a 1-5 star rating that gets written to the
/// `user_interactions` table — that table is what the Python CF service
/// already indexes for taste profiles.
class RecipeRatingBottomSheet extends StatefulWidget {
  final Recipe recipe;
  const RecipeRatingBottomSheet({super.key, required this.recipe});

  /// Convenience opener. Returns null if the user dismissed the sheet
  /// without confirming, otherwise a [CookConfirmation] (rating may still
  /// be null if "Skip" was tapped).
  static Future<CookConfirmation?> show(
    BuildContext context,
    Recipe recipe,
  ) {
    return showModalBottomSheet<CookConfirmation>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => RecipeRatingBottomSheet(recipe: recipe),
    );
  }

  @override
  State<RecipeRatingBottomSheet> createState() =>
      _RecipeRatingBottomSheetState();
}

class _RecipeRatingBottomSheetState extends State<RecipeRatingBottomSheet> {
  static const Color _accent = Color(0xFF13EC13);
  int? _selectedRating;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 12, 24, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(
                child: Container(
                  width: 48,
                  height: 6,
                  decoration: BoxDecoration(
                    color: Colors.grey[300],
                    borderRadius: BorderRadius.circular(3),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Text(
                'How was it?',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  color: Colors.grey[900],
                ),
              ),
              const SizedBox(height: 6),
              Text(
                widget.recipe.title,
                textAlign: TextAlign.center,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 14, color: Colors.grey[600]),
              ),
              const SizedBox(height: 20),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: List.generate(5, (i) {
                  final value = i + 1;
                  final filled = _selectedRating != null && _selectedRating! >= value;
                  return IconButton(
                    iconSize: 38,
                    splashRadius: 26,
                    onPressed: () => setState(() => _selectedRating = value),
                    icon: Icon(
                      filled ? Icons.star_rounded : Icons.star_outline_rounded,
                      color: filled ? Colors.amber : Colors.grey[400],
                    ),
                  );
                }),
              ),
              const SizedBox(height: 6),
              Center(
                child: Text(
                  _selectedRating == null
                      ? 'Tap a star to rate (optional)'
                      : '${_selectedRating!}/5 — ${_ratingLabel(_selectedRating!)}',
                  style: TextStyle(
                    color: _selectedRating == null
                        ? Colors.grey[600]
                        : Colors.grey[900],
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
              const SizedBox(height: 24),
              ElevatedButton(
                onPressed: () => Navigator.pop(
                  context,
                  CookConfirmation(rating: _selectedRating),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: _accent,
                  foregroundColor: Colors.black,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                  elevation: 0,
                ),
                child: Text(
                  _selectedRating == null
                      ? 'Mark cooked (no rating)'
                      : 'Save rating & mark cooked',
                  style: const TextStyle(
                    fontSize: 16, fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              const SizedBox(height: 8),
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: Text(
                  'Cancel',
                  style: TextStyle(color: Colors.grey[700]),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _ratingLabel(int v) {
    switch (v) {
      case 1: return 'Won\'t make again';
      case 2: return 'Just okay';
      case 3: return 'Pretty good';
      case 4: return 'Really liked it';
      case 5: return 'Loved it';
      default: return '';
    }
  }
}
