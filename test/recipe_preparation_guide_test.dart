import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fridge_app/models/fridge_item.dart';
import 'package:fridge_app/models/recipe.dart';
import 'package:fridge_app/models/units.dart';
import 'package:fridge_app/screens/recipe_preparation_guide_screen.dart';
import 'package:fridge_app/services/fridge_service.dart';

void main() {
  testWidgets('Cooked button removes used ingredients from fridge', (
    WidgetTester tester,
  ) async {
    const targetItemId = 'item_021';
    final service = FridgeService.instance;

    final existingItem = service.getItemById(targetItemId);
    final itemSnapshot =
        existingItem ??
        FridgeItem(
          id: targetItemId,
          name: 'Chicken Breast',
          category: FridgeCategory.meat,
          amount: 1,
          unit: FridgeUnit.pieces,
          addedDate: DateTime.now(),
        );

    if (existingItem == null) {
      service.addItem(itemSnapshot);
    }

    addTearDown(() {
      service.deleteItem(targetItemId);
      service.addItem(itemSnapshot);
    });

    const recipe = Recipe(
      id: 'recipe_test_consume',
      title: 'Chicken Test Dish',
      ingredients: [
        RecipeIngredient(name: 'Chicken Breast', amount: '1 serving'),
      ],
      steps: [],
    );

    await tester.pumpWidget(
      const MaterialApp(home: RecipePreparationGuideScreen(recipe: recipe)),
    );
    await tester.pumpAndSettle();

    expect(service.getItemById(targetItemId), isNotNull);

    await tester.tap(find.byKey(const ValueKey('recipe_cooked_button')));
    await tester.pumpAndSettle();

    expect(find.text('Use Ingredients?'), findsOneWidget);
    await tester.tap(find.text('Remove'));
    await tester.pumpAndSettle();

    expect(service.getItemById(targetItemId), isNull);
    expect(find.textContaining('Removed 1 ingredient item'), findsOneWidget);
  });
}
