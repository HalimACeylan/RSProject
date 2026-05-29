import 'dart:io';
import 'package:csv/csv.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() async {
  print('Initializing sqflite FFI...');
  sqfliteFfiInit();
  final databaseFactory = databaseFactoryFfi;

  final dbFile = File('${Directory.current.path}/assets/fridge_app.db');
  if (dbFile.existsSync()) {
    print('Deleting existing fridge_app.db...');
    dbFile.deleteSync();
  } else {
    // Ensure assets directory exists
    Directory('${Directory.current.path}/assets').createSync(recursive: true);
  }

  print('Creating database at ${dbFile.path}...');
  final db = await databaseFactory.openDatabase(
    dbFile.path,
    options: OpenDatabaseOptions(
      version: 1,
      onCreate: (db, version) async {
        await db.execute('''
          CREATE TABLE meta (
            key TEXT PRIMARY KEY,
            value TEXT
          )
        ''');

        await db.execute('''
          CREATE TABLE food_items (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            name TEXT NOT NULL,
            category TEXT,
            calories REAL, protein REAL, carbs REAL, fat REAL,
            fiber REAL, sugars REAL, sodium REAL, cholesterol REAL,
            meal_type TEXT
          )
        ''');

        await db.execute('''
          CREATE TABLE recipes (
            id INTEGER PRIMARY KEY,
            name TEXT NOT NULL,
            minutes INTEGER,
            tags TEXT,
            nutrition TEXT,
            n_steps INTEGER,
            n_ingredients INTEGER
          )
        ''');

        await db.execute('''
          CREATE TABLE recipe_steps (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            recipe_id INTEGER,
            step_number INTEGER,
            description TEXT,
            FOREIGN KEY (recipe_id) REFERENCES recipes(id)
          )
        ''');

        await db.execute('''
          CREATE TABLE recipe_ingredients (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            recipe_id INTEGER,
            name TEXT,
            FOREIGN KEY (recipe_id) REFERENCES recipes(id)
          )
        ''');

        await db.execute('''
          CREATE TABLE user_interactions (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            user_id INTEGER,
            recipe_id INTEGER,
            rating INTEGER,
            profile_tag TEXT,
            FOREIGN KEY (recipe_id) REFERENCES recipes(id)
          )
        ''');

        await db.execute('''
          CREATE TABLE fridge_items (
            id TEXT PRIMARY KEY,
            name TEXT NOT NULL,
            category TEXT,
            amount REAL,
            unit TEXT,
            expiry_date INTEGER,
            added_date INTEGER NOT NULL,
            image_url TEXT,
            notes TEXT,
            receipt_id TEXT,
            household_id TEXT,
            is_frozen INTEGER NOT NULL DEFAULT 0
          )
        ''');
        await db.execute('CREATE INDEX idx_fridge_category ON fridge_items(category)');

        await db.execute('''
          CREATE TABLE consumption_logs (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            item_name TEXT NOT NULL,
            category TEXT,
            amount REAL,
            unit TEXT,
            is_from_fridge INTEGER,
            date INTEGER
          )
        ''');
        await db.execute('CREATE INDEX idx_consumption_logs_name ON consumption_logs(item_name)');

        await db.execute('''
          CREATE TABLE users (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            profile_key TEXT NOT NULL,
            age INTEGER NOT NULL,
            sex TEXT NOT NULL,
            weight_kg REAL NOT NULL,
            height_cm REAL NOT NULL,
            activity_level TEXT NOT NULL,
            meals_per_day INTEGER NOT NULL,
            daily_calories INTEGER NOT NULL,
            dietary_restrictions TEXT,
            avoid_ingredients TEXT,
            created_at INTEGER NOT NULL
          )
        ''');

        await db.execute('''
          CREATE TABLE cooked_recipes (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            recipe_id INTEGER NOT NULL,
            recipe_name TEXT NOT NULL,
            cooked_at INTEGER NOT NULL
          )
        ''');
        await db.execute('CREATE INDEX idx_cooked_recipes_cooked_at ON cooked_recipes(cooked_at)');
      },
    ),
  );

  print('Starting CSV dataset import...');
  final stopwatch = Stopwatch()..start();

  await _importFoodItems(db);
  await _importRecipes(db);
  await _importInteractions(db);

  await db.insert('meta', {'key': 'csv_imported', 'value': DateTime.now().toIso8601String()});
  
  stopwatch.stop();
  print('CSV import complete in ${stopwatch.elapsedMilliseconds}ms');

  await db.close();
  print('Database built successfully at ${dbFile.path}');
}

Future<void> _importFoodItems(Database db) async {
  final csvFile = File('datasets_to_use/daily_food_nutrition_dataset.csv');
  if (!csvFile.existsSync()) {
    print('Warning: food dataset not found');
    return;
  }
  
  final csvString = await csvFile.readAsString();
  final rows = const CsvToListConverter(eol: '\n').convert(csvString);
  if (rows.isEmpty) return;

  final batch = db.batch();
  for (var i = 1; i < rows.length; i++) {
    final r = rows[i];
    if (r.length < 11) continue;
    batch.insert('food_items', {
      'name': _str(r[0]),
      'category': _str(r[1]),
      'calories': _num(r[2]),
      'protein': _num(r[3]),
      'carbs': _num(r[4]),
      'fat': _num(r[5]),
      'fiber': _num(r[6]),
      'sugars': _num(r[7]),
      'sodium': _num(r[8]),
      'cholesterol': _num(r[9]),
      'meal_type': _str(r[10]),
    });
  }
  await batch.commit(noResult: true);
  print('Imported ${rows.length - 1} food items');
}

Future<void> _importRecipes(Database db) async {
  final csvFile = File('datasets_to_use/RAW_recipes_filtered.csv');
  if (!csvFile.existsSync()) {
    print('Warning: recipe dataset not found');
    return;
  }

  final csvString = await csvFile.readAsString();
  final rows = const CsvToListConverter().convert(csvString);
  if (rows.isEmpty) return;

  int imported = 0;
  const batchSize = 500;

  for (var batchStart = 1; batchStart < rows.length; batchStart += batchSize) {
    final batch = db.batch();
    final end = (batchStart + batchSize).clamp(0, rows.length);

    for (var i = batchStart; i < end; i++) {
      final r = rows[i];
      if (r.length < 9) {
        if (i == 1) print('Row 1 length is ${r.length}. Content: $r');
        continue;
      }

      final recipeId = _intVal(r[1]);
      if (recipeId == null) continue;

      batch.insert('recipes', {
        'id': recipeId,
        'name': _str(r[0]),
        'minutes': _intVal(r[2]) ?? 0,
        'tags': _str(r[3]),
        'nutrition': _str(r[4]),
        'n_steps': _intVal(r[5]) ?? 0,
        'n_ingredients': _intVal(r[8]) ?? 0,
      }, conflictAlgorithm: ConflictAlgorithm.ignore);

      final stepsStr = _str(r[6]);
      final steps = _parsePythonList(stepsStr);
      for (var s = 0; s < steps.length; s++) {
        batch.insert('recipe_steps', {
          'recipe_id': recipeId,
          'step_number': s + 1,
          'description': steps[s],
        });
      }

      final ingredientsStr = _str(r[7]);
      final ingredients = _parsePythonList(ingredientsStr);
      for (final ing in ingredients) {
        batch.insert('recipe_ingredients', {
          'recipe_id': recipeId,
          'name': ing,
        });
      }

      imported++;
    }
    await batch.commit(noResult: true);
  }
  print('Imported $imported recipes');
}

Future<void> _importInteractions(Database db) async {
  final csvFile = File('datasets_to_use/synthetic_interactions.csv');
  if (!csvFile.existsSync()) {
    print('Warning: interactions dataset not found');
    return;
  }

  final csvString = await csvFile.readAsString();
  final rows = const CsvToListConverter(eol: '\n').convert(csvString);
  if (rows.isEmpty) return;

  const batchSize = 1000;
  for (var batchStart = 1; batchStart < rows.length; batchStart += batchSize) {
    final batch = db.batch();
    final end = (batchStart + batchSize).clamp(0, rows.length);
    for (var i = batchStart; i < end; i++) {
      final r = rows[i];
      if (r.length < 4) continue;
      batch.insert('user_interactions', {
        'user_id': _intVal(r[0]),
        'recipe_id': _intVal(r[1]),
        'rating': _intVal(r[2]),
        'profile_tag': _str(r[3]),
      });
    }
    await batch.commit(noResult: true);
  }
  print('Imported ${rows.length - 1} user interactions');
}

String _str(dynamic v) => v?.toString().trim() ?? '';

double _num(dynamic v) {
  if (v == null) return 0;
  if (v is num) return v.toDouble();
  return double.tryParse(v.toString().trim()) ?? 0;
}

int? _intVal(dynamic v) {
  if (v == null) return null;
  if (v is int) return v;
  if (v is double) return v.toInt();
  return int.tryParse(v.toString().trim());
}

List<String> _parsePythonList(String raw) {
  if (raw.isEmpty) return [];
  var s = raw.trim();
  if (s.startsWith('[')) s = s.substring(1);
  if (s.endsWith(']')) s = s.substring(0, s.length - 1);
  if (s.trim().isEmpty) return [];

  final results = <String>[];
  final buffer = StringBuffer();
  var inQuote = false;
  var quoteChar = "'";

  for (var i = 0; i < s.length; i++) {
    final c = s[i];
    if (!inQuote && (c == "'" || c == '"')) {
      inQuote = true;
      quoteChar = c;
    } else if (inQuote && c == quoteChar) {
      if (i + 1 < s.length && s[i + 1] == quoteChar) {
        buffer.write(c);
        i++;
      } else {
        inQuote = false;
      }
    } else if (!inQuote && c == ',') {
      final item = buffer.toString().trim();
      if (item.isNotEmpty) results.add(item);
      buffer.clear();
    } else {
      buffer.write(c);
    }
  }
  final last = buffer.toString().trim();
  if (last.isNotEmpty) results.add(last);

  return results;
}
