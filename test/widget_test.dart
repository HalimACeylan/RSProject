import 'package:flutter_test/flutter_test.dart';
import 'package:fridge_app/main.dart';
import 'package:fridge_app/screens/welcome_login_screen.dart';

void main() {
  testWidgets('Welcome Login Screen loads correctly', (
    WidgetTester tester,
  ) async {
    // Build our app and trigger a frame.
    await tester.pumpWidget(const FridgeApp());

    // Verify that the WelcomeLoginScreen is displayed initially
    expect(find.byType(WelcomeLoginScreen), findsOneWidget);

    // Verify specific text elements are present
    expect(find.text('FridgeFresh'), findsOneWidget);
    expect(
      find.text(
        'Eat fresh, waste less. Scan receipts & find recipes instantly.',
      ),
      findsOneWidget,
    );
    expect(find.text('Get Started'), findsOneWidget);
    expect(find.text('I have an account'), findsOneWidget);
    expect(find.text('Continue as Guest'), findsOneWidget);
  });
}
