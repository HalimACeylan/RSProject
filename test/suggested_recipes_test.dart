import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fridge_app/screens/suggested_recipes_screen.dart';

void main() {
  testWidgets('Suggested Recipes supports searching by recipe name', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(const MaterialApp(home: SuggestedRecipesScreen()));
    await tester.pumpAndSettle();

    final searchField = find.byKey(const ValueKey('recipe_name_search_field'));
    expect(searchField, findsOneWidget);

    await tester.enterText(searchField, 'pizza');
    await tester.pumpAndSettle();

    expect(find.text('Homemade Flatbread Pizza'), findsOneWidget);
    expect(find.text('Fresh Basil Pesto Pasta'), findsNothing);
  });

  testWidgets(
    'Suggested Recipes supports multi ingredient filters with removable cards',
    (WidgetTester tester) async {
      await tester.pumpWidget(
        const MaterialApp(home: SuggestedRecipesScreen()),
      );
      await tester.pumpAndSettle();

      final ingredientSearch = find.byKey(
        const ValueKey('ingredient_filter_search_field'),
      );
      expect(ingredientSearch, findsOneWidget);

      await tester.enterText(ingredientSearch, 'chicken');
      await tester.pumpAndSettle();

      final chickenSuggestion = find.byKey(
        const ValueKey('ingredient_suggestion_item_021'),
      );
      expect(chickenSuggestion, findsOneWidget);
      await tester.tap(chickenSuggestion);
      await tester.pumpAndSettle();

      expect(
        find.byKey(const ValueKey('selected_ingredient_item_021')),
        findsOneWidget,
      );
      expect(find.text('Spicy Chicken Stir-fry'), findsOneWidget);
      expect(find.text('Fresh Basil Pesto Pasta'), findsNothing);

      final selectedChickenChip = find.byKey(
        const ValueKey('selected_ingredient_item_021'),
      );
      final deleteChipIcon = find.descendant(
        of: selectedChickenChip,
        matching: find.byIcon(Icons.close),
      );
      expect(deleteChipIcon, findsOneWidget);
      await tester.tap(deleteChipIcon);
      await tester.pumpAndSettle();

      expect(
        find.byKey(const ValueKey('selected_ingredient_item_021')),
        findsNothing,
      );
      expect(find.text('Fresh Basil Pesto Pasta'), findsOneWidget);
    },
  );

  testWidgets(
    'Suggested Recipes applies multiple ingredient filters together',
    (WidgetTester tester) async {
      await tester.pumpWidget(
        const MaterialApp(home: SuggestedRecipesScreen()),
      );
      await tester.pumpAndSettle();

      final ingredientSearch = find.byKey(
        const ValueKey('ingredient_filter_search_field'),
      );
      expect(ingredientSearch, findsOneWidget);

      await tester.enterText(ingredientSearch, 'fresh basil');
      await tester.pumpAndSettle();

      final basilSuggestion = find.byKey(
        const ValueKey('ingredient_suggestion_item_005'),
      );
      expect(basilSuggestion, findsOneWidget);
      await tester.tap(basilSuggestion);
      await tester.pumpAndSettle();

      await tester.enterText(ingredientSearch, 'pasta');
      await tester.pumpAndSettle();

      final pastaSuggestion = find.byKey(
        const ValueKey('ingredient_suggestion_item_051'),
      );
      expect(pastaSuggestion, findsOneWidget);
      await tester.tap(pastaSuggestion);
      await tester.pumpAndSettle();

      expect(find.text('Fresh Basil Pesto Pasta'), findsOneWidget);
      expect(find.text('Spicy Chicken Stir-fry'), findsNothing);
    },
  );
}
