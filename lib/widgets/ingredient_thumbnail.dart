import 'package:flutter/material.dart';
import 'package:fridge_app/utils/ingredient_emoji.dart';

/// Renders up to 4 ingredient emojis collage-style on a soft pastel
/// background. Used wherever a recipe used to show a hero image but the
/// DB-imported recipes don't have one.
class IngredientThumbnail extends StatelessWidget {
  final List<String> ingredientNames;
  final double size;
  final BorderRadius? borderRadius;
  final Color? backgroundColor;

  const IngredientThumbnail({
    super.key,
    required this.ingredientNames,
    this.size = 96,
    this.borderRadius,
    this.backgroundColor,
  });

  @override
  Widget build(BuildContext context) {
    final emojis = IngredientEmoji.pickDistinct(ingredientNames);
    final radius = borderRadius ?? BorderRadius.circular(16);
    final bg = backgroundColor ?? _autoBackground(emojis.first);

    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(color: bg, borderRadius: radius),
      child: ClipRRect(
        borderRadius: radius,
        child: _buildGrid(emojis),
      ),
    );
  }

  Widget _buildGrid(List<String> emojis) {
    switch (emojis.length) {
      case 1:
        return Center(child: _emoji(emojis[0], size * 0.6));
      case 2:
        return Row(
          children: [
            Expanded(child: Center(child: _emoji(emojis[0], size * 0.42))),
            Expanded(child: Center(child: _emoji(emojis[1], size * 0.42))),
          ],
        );
      case 3:
        return Column(
          children: [
            Expanded(child: Center(child: _emoji(emojis[0], size * 0.38))),
            Expanded(
              child: Row(
                children: [
                  Expanded(child: Center(child: _emoji(emojis[1], size * 0.32))),
                  Expanded(child: Center(child: _emoji(emojis[2], size * 0.32))),
                ],
              ),
            ),
          ],
        );
      default:
        return GridView.count(
          crossAxisCount: 2,
          physics: const NeverScrollableScrollPhysics(),
          children: emojis
              .take(4)
              .map((e) => Center(child: _emoji(e, size * 0.32)))
              .toList(),
        );
    }
  }

  Widget _emoji(String e, double sz) => Text(e, style: TextStyle(fontSize: sz));

  /// Pick a soft pastel based on the first emoji so different recipes get
  /// distinguishable tiles without coordinating from the call site.
  Color _autoBackground(String emoji) {
    final code = emoji.runes.fold<int>(0, (a, b) => a + b);
    const palette = [
      Color(0xFFFFE0B2), // peach
      Color(0xFFC8E6C9), // mint
      Color(0xFFB3E5FC), // sky
      Color(0xFFF8BBD0), // rose
      Color(0xFFFFF59D), // butter
      Color(0xFFD1C4E9), // lavender
      Color(0xFFFFCCBC), // coral
    ];
    return palette[code % palette.length];
  }
}
