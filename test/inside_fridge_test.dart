import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fridge_app/routes.dart';
import 'package:fridge_app/screens/food_item_details_screen.dart';
import 'package:fridge_app/screens/inside_fridge_screen.dart';
import 'package:fridge_app/services/fridge_service.dart';

void main() {
  testWidgets('Inside Fridge Screen loads correctly', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(const MaterialApp(home: InsideFridgeScreen()));

    // ── Header ──────────────────────────────────────────────────────
    expect(find.text('Inside My Fridge'), findsOneWidget);
    expect(find.text('Inventory Management'), findsOneWidget);

    // ── Search Bar ──────────────────────────────────────────────────
    expect(find.text('Find ingredients...'), findsOneWidget);

    // ── Stat badge labels ───────────────────────────────────────────
    expect(find.text('Urgent'), findsOneWidget);
    expect(find.text('Use Soon'), findsOneWidget);
    expect(find.text('Healthy'), findsOneWidget);

    // ── Stat count labels ───────────────────────────────────────────
    expect(find.text('Expiring soon'), findsOneWidget);
    expect(find.text('Use this week'), findsOneWidget);
    expect(find.text('Total fresh items'), findsOneWidget);

    // ── Bottom Navigation ───────────────────────────────────────────
    expect(find.text('Scan'), findsOneWidget);
    expect(find.text('Fridge'), findsOneWidget);
    expect(find.text('Cook'), findsOneWidget);
    expect(find.text('Profile'), findsOneWidget);

    // ── FAB ─────────────────────────────────────────────────────────
    expect(find.byIcon(Icons.add), findsOneWidget);
  });

  testWidgets('Inside Fridge Screen shows urgent section heading', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(const MaterialApp(home: InsideFridgeScreen()));

    final urgentItems = FridgeService.instance.getExpiringItems();

    if (urgentItems.isNotEmpty) {
      expect(find.text('Use Immediately'), findsOneWidget);
      // Verify the urgent items count label is displayed
      expect(find.text('${urgentItems.length} items'), findsWidgets);
    }
  });

  testWidgets('Inside Fridge Screen shows category sections', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(const MaterialApp(home: InsideFridgeScreen()));

    // Check at least a few known items from the sample data are present
    // (they may be off-screen, so we just verify the widget tree contains them)
    final allItems = FridgeService.instance.getAllItems();
    expect(allItems.isNotEmpty, true);

    // Verify the first item in the list (Fresh Spinach) is rendered
    // It should appear either in urgent or category section
    expect(find.text(allItems.first.name), findsWidgets);
  });

  testWidgets('Deleting an item from details removes it from fridge list', (
    WidgetTester tester,
  ) async {
    const testItemId = 'item_001';
    final service = FridgeService.instance;
    final testItem = service.getItemById(testItemId);

    expect(testItem, isNotNull);
    addTearDown(() {
      if (service.getItemById(testItemId) == null && testItem != null) {
        service.addItem(testItem);
      }
    });

    await tester.pumpWidget(
      MaterialApp(
        home: const InsideFridgeScreen(),
        routes: {
          AppRoutes.foodItemDetails: (context) => const FoodItemDetailsScreen(),
        },
      ),
    );
    await tester.pumpAndSettle();

    expect(service.getItemById(testItemId), isNotNull);
    expect(
      service.getExpiringItems().any((item) => item.id == testItemId),
      isTrue,
    );

    final urgentCardFinder = find.byKey(
      const ValueKey('urgent_item_$testItemId'),
    );
    expect(urgentCardFinder, findsOneWidget);
    await tester.ensureVisible(urgentCardFinder);
    await tester.tap(urgentCardFinder);
    await tester.pumpAndSettle();

    final removeButtonFinder = find.text('Remove from Fridge');
    expect(removeButtonFinder, findsOneWidget);
    await tester.ensureVisible(removeButtonFinder);
    await tester.tap(removeButtonFinder);
    await tester.pumpAndSettle();

    expect(find.text('Remove Item'), findsOneWidget);
    await tester.tap(find.text('Delete'));
    await tester.pumpAndSettle();

    expect(service.getItemById(testItemId), isNull);
    expect(find.byKey(const ValueKey('urgent_item_$testItemId')), findsNothing);
  });
}
