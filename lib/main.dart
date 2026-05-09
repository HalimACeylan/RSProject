import 'package:flutter/material.dart';
import 'package:fridge_app/routes.dart';
import 'package:fridge_app/services/database_service.dart';
import 'package:fridge_app/services/db_factory.dart';
import 'package:fridge_app/services/fridge_service.dart';
import 'package:fridge_app/services/recipe_service.dart';
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
    // 1. Open / create the SQLite database
    await DatabaseService.instance.initialize();

    // 2. One-time CSV dataset import (skipped on subsequent launches)
    await DatabaseService.instance.importCsvIfNeeded();

    // 3. Load fridge items from DB
    await FridgeService.instance.initialize();

    // 4. Load recipes from DB
    await RecipeService.instance.initialize();
  } catch (e) {
    debugPrint('Service initialization error: $e');
  }
}

class FridgeApp extends StatelessWidget {
  const FridgeApp({super.key});

  @override
  Widget build(BuildContext context) {
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
      initialRoute: AppRoutes.welcomeLogin,
      routes: AppRoutes.routes,
    );
  }
}
