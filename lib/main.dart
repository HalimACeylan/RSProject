import 'dart:async';

import 'package:flutter/material.dart';
import 'package:fridge_app/routes.dart';
import 'package:fridge_app/services/database_service.dart';
import 'package:fridge_app/services/db_factory.dart';
import 'package:fridge_app/services/fridge_service.dart';
import 'package:fridge_app/services/recipe_service.dart';
import 'package:fridge_app/services/user_profile_service.dart';
import 'package:google_fonts/google_fonts.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Initialize the right SQLite factory for the current platform (web / desktop / mobile)
  await initDbFactory();

  await _initializeServices();
  runApp(const FridgeApp());
}

Future<void> _initializeServices() async {
  try {
    await DatabaseService.instance.initialize();
    await UserProfileService.instance.initialize();
    await FridgeService.instance.initialize();
    // Recipes (~20k rows) load in the background — first paint shouldn't wait
    // on the SQLite scan. Screens that need them await RecipeService.ready.
    unawaited(RecipeService.instance.initialize());
  } catch (e) {
    debugPrint('Service initialization error: $e');
  }
}

class FridgeApp extends StatelessWidget {
  const FridgeApp({super.key});

  @override
  Widget build(BuildContext context) {
    final startRoute = UserProfileService.instance.hasProfile
        ? AppRoutes.insideFridge
        : AppRoutes.welcomeLogin;
    return MaterialApp(
      title: 'FridgeApp',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF13EC13),
          brightness: Brightness.light,
        ),
        useMaterial3: true,
        textTheme: GoogleFonts.workSansTextTheme(),
      ),
      initialRoute: startRoute,
      routes: AppRoutes.routes,
    );
  }
}
