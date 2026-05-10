import 'package:csv/csv.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

/// Central SQLite database service.  Singleton.
///
/// Handles DB creation, table schema, and one-time CSV dataset import.
class DatabaseService {
  DatabaseService._();
  static final DatabaseService instance = DatabaseService._();

  Database? _db;
  bool _isInitialized = false;

  /// Whether the database was successfully opened.
  bool get isReady => _db != null;

  // ── Initialization ────────────────────────────────────────────────

  Future<void> initialize() async {
    if (_isInitialized) return;
    _isInitialized = true; // prevent re-entry
    try {
      // On web, getDatabasesPath() is not supported.
      String dbPath;
      try {
        final dir = await getDatabasesPath();
        dbPath = p.join(dir, 'fridge_app.db');
      } catch (_) {
        dbPath = 'fridge_app.db';
      }
      debugPrint('[DB] Opening database at: $dbPath');
      _db = await openDatabase(
        dbPath,
        version: 1,
        onCreate: _onCreate,
      );
      debugPrint('[DB] Database opened successfully');
    } catch (e) {
      debugPrint('[DB] Failed to open database: $e');
      _db = null;
    }
  }

  Future<void> _onCreate(Database db, int version) async {
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
        profile_tag TEXT
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
        added_date INTEGER,
        image_url TEXT,
        notes TEXT,
        receipt_id TEXT,
        household_id TEXT,
        is_frozen INTEGER DEFAULT 0
      )
    ''');

    // Indices for common queries
    await db.execute('CREATE INDEX idx_food_items_name ON food_items(name)');
    await db.execute('CREATE INDEX idx_food_items_category ON food_items(category)');
    await db.execute('CREATE INDEX idx_food_items_meal ON food_items(meal_type)');
    await db.execute('CREATE INDEX idx_recipes_name ON recipes(name)');
    await db.execute('CREATE INDEX idx_recipe_steps_rid ON recipe_steps(recipe_id)');
    await db.execute('CREATE INDEX idx_recipe_ingredients_rid ON recipe_ingredients(recipe_id)');
    await db.execute('CREATE INDEX idx_interactions_user ON user_interactions(user_id)');
    await db.execute('CREATE INDEX idx_interactions_recipe ON user_interactions(recipe_id)');
    await db.execute('CREATE INDEX idx_fridge_category ON fridge_items(category)');
  }

  // ── CSV Import ────────────────────────────────────────────────────

  /// Import all CSV datasets if they haven't been imported yet.
  /// Returns true if an import was performed.
  Future<bool> importCsvIfNeeded() async {
    if (_db == null) return false;
    final result = await _db!.query('meta', where: 'key = ?', whereArgs: ['csv_imported']);
    if (result.isNotEmpty) return false;

    debugPrint('[DB] Starting CSV dataset import...');
    final stopwatch = Stopwatch()..start();

    await _importFoodItems();
    await _importRecipes();
    await _importInteractions();

    await _db!.insert('meta', {'key': 'csv_imported', 'value': DateTime.now().toIso8601String()});
    stopwatch.stop();
    debugPrint('[DB] CSV import complete in ${stopwatch.elapsedMilliseconds}ms');
    return true;
  }

  Future<void> _importFoodItems() async {
    final csvString = await rootBundle.loadString('datasets_to_use/daily_food_nutrition_dataset.csv');
    final rows = const CsvToListConverter(eol: '\n').convert(csvString);
    if (rows.isEmpty) return;

    // Skip header row
    final batch = _db!.batch();
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
        // Water_Intake (index 11) intentionally skipped per user request
      });
    }
    await batch.commit(noResult: true);
    debugPrint('[DB] Imported ${rows.length - 1} food items');
  }

  Future<void> _importRecipes() async {
    final csvString = await rootBundle.loadString('datasets_to_use/RAW_recipes_filtered.csv');
    // This CSV has quoted fields with commas inside, so CsvToListConverter handles it.
    final rows = const CsvToListConverter(eol: '\n').convert(csvString);
    if (rows.isEmpty) return;

    // Header: name, id, minutes, tags, nutrition, n_steps, steps, ingredients, n_ingredients
    int imported = 0;
    const batchSize = 500;

    for (var batchStart = 1; batchStart < rows.length; batchStart += batchSize) {
      final batch = _db!.batch();
      final end = (batchStart + batchSize).clamp(0, rows.length);

      for (var i = batchStart; i < end; i++) {
        final r = rows[i];
        if (r.length < 9) continue;

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

        // Parse steps - stored as Python-style list string: "['step1', 'step2']"
        final stepsStr = _str(r[6]);
        final steps = _parsePythonList(stepsStr);
        for (var s = 0; s < steps.length; s++) {
          batch.insert('recipe_steps', {
            'recipe_id': recipeId,
            'step_number': s + 1,
            'description': steps[s],
          });
        }

        // Parse ingredients
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
    debugPrint('[DB] Imported $imported recipes');
  }

  Future<void> _importInteractions() async {
    final csvString = await rootBundle.loadString('datasets_to_use/synthetic_interactions.csv');
    final rows = const CsvToListConverter(eol: '\n').convert(csvString);
    if (rows.isEmpty) return;

    // Header: user_id, recipe_id, rating, profile_tag
    const batchSize = 1000;
    for (var batchStart = 1; batchStart < rows.length; batchStart += batchSize) {
      final batch = _db!.batch();
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
    debugPrint('[DB] Imported ${rows.length - 1} user interactions');
  }

  // ── Generic Query Helpers ─────────────────────────────────────────

  Future<List<Map<String, dynamic>>> queryAll(String table) async {
    if (_db == null) return [];
    return _db!.query(table);
  }

  Future<List<Map<String, dynamic>>> queryWhere(
    String table, {
    String? where,
    List<Object?>? whereArgs,
    int? limit,
    String? orderBy,
  }) async {
    if (_db == null) return [];
    return _db!.query(table,
        where: where, whereArgs: whereArgs, limit: limit, orderBy: orderBy);
  }

  Future<int> insert(String table, Map<String, dynamic> values,
      {ConflictAlgorithm? conflictAlgorithm}) async {
    if (_db == null) return -1;
    return _db!.insert(table, values,
        conflictAlgorithm: conflictAlgorithm ?? ConflictAlgorithm.replace);
  }

  Future<int> update(String table, Map<String, dynamic> values,
      {String? where, List<Object?>? whereArgs}) async {
    if (_db == null) return 0;
    return _db!.update(table, values, where: where, whereArgs: whereArgs);
  }

  Future<int> delete(String table,
      {String? where, List<Object?>? whereArgs}) async {
    if (_db == null) return 0;
    return _db!.delete(table, where: where, whereArgs: whereArgs);
  }

  Future<int> count(String table) async {
    if (_db == null) return 0;
    final result = await _db!.rawQuery('SELECT COUNT(*) as cnt FROM $table');
    return Sqflite.firstIntValue(result) ?? 0;
  }

  // ── Private Helpers ───────────────────────────────────────────────

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

  /// Parse a Python-style list string like "['a', 'b', 'c']" into a Dart List<String>.
  List<String> _parsePythonList(String raw) {
    if (raw.isEmpty) return [];
    // Remove outer brackets
    var s = raw.trim();
    if (s.startsWith('[')) s = s.substring(1);
    if (s.endsWith(']')) s = s.substring(0, s.length - 1);
    if (s.trim().isEmpty) return [];

    final results = <String>[];
    // Split by ', ' while respecting quotes
    final buffer = StringBuffer();
    var inQuote = false;
    var quoteChar = "'";

    for (var i = 0; i < s.length; i++) {
      final c = s[i];
      if (!inQuote && (c == "'" || c == '"')) {
        inQuote = true;
        quoteChar = c;
      } else if (inQuote && c == quoteChar) {
        // Check for escaped quote
        if (i + 1 < s.length && s[i + 1] == quoteChar) {
          buffer.write(c);
          i++; // skip next
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
}
