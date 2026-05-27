import 'package:fridge_app/services/database_service.dart';
import 'package:flutter/widgets.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;
  
  await DatabaseService.instance.initialize();
  final recipes = await DatabaseService.instance.queryAll('recipes');
  print('Recipes count: ${recipes.length}');
  
  final steps = await DatabaseService.instance.queryAll('recipe_steps');
  print('Steps count: ${steps.length}');
}
