import 'package:flutter_test/flutter_test.dart';
import 'package:fridge_app/main.dart';
import 'package:fridge_app/screens/welcome_login_screen.dart';

void main() {
  testWidgets('Welcome Login Screen loads correctly', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(const FridgeApp());

    expect(find.byType(WelcomeLoginScreen), findsOneWidget);
    expect(find.text('FridgeFresh'), findsOneWidget);
    expect(find.text('Get Started'), findsOneWidget);
  });
}
