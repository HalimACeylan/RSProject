// Integration test for the SQLite schema + CRUD layer used by the app.
//
// Runs against an in-memory database (sqflite_common_ffi) seeded with the
// same CREATE TABLE statements as scripts/build_db.dart, so it verifies the
// schema is consistent and that round-tripping through UserProfile.toDbMap /
// fromDbMap and other DB helpers works as expected.

import 'package:flutter_test/flutter_test.dart';
import 'package:fridge_app/models/user_profile.dart';
import 'package:fridge_app/services/kb_recommender_service.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

const _schema = [
  '''
  CREATE TABLE meta (
    key TEXT PRIMARY KEY,
    value TEXT
  )''',
  '''
  CREATE TABLE food_items (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    name TEXT NOT NULL,
    category TEXT,
    calories REAL, protein REAL, carbs REAL, fat REAL,
    fiber REAL, sugars REAL, sodium REAL, cholesterol REAL,
    meal_type TEXT
  )''',
  '''
  CREATE TABLE recipes (
    id INTEGER PRIMARY KEY,
    name TEXT NOT NULL,
    minutes INTEGER,
    tags TEXT,
    nutrition TEXT,
    n_steps INTEGER,
    n_ingredients INTEGER
  )''',
  '''
  CREATE TABLE recipe_steps (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    recipe_id INTEGER,
    step_number INTEGER,
    description TEXT,
    FOREIGN KEY (recipe_id) REFERENCES recipes(id)
  )''',
  '''
  CREATE TABLE recipe_ingredients (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    recipe_id INTEGER,
    name TEXT,
    FOREIGN KEY (recipe_id) REFERENCES recipes(id)
  )''',
  '''
  CREATE TABLE user_interactions (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    user_id INTEGER,
    recipe_id INTEGER,
    rating INTEGER,
    profile_tag TEXT,
    FOREIGN KEY (recipe_id) REFERENCES recipes(id)
  )''',
  '''
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
  )''',
  '''
  CREATE TABLE consumption_logs (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    item_name TEXT NOT NULL,
    category TEXT,
    amount REAL,
    unit TEXT,
    is_from_fridge INTEGER,
    date INTEGER
  )''',
  '''
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
  )''',
];

Future<Database> _freshDb() async {
  final db = await databaseFactoryFfi.openDatabase(
    inMemoryDatabasePath,
    options: OpenDatabaseOptions(version: 1),
  );
  for (final stmt in _schema) {
    await db.execute(stmt);
  }
  return db;
}

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  group('schema', () {
    test('all expected tables are created', () async {
      final db = await _freshDb();
      addTearDown(db.close);

      final rows = await db.rawQuery(
        "SELECT name FROM sqlite_master WHERE type='table' ORDER BY name",
      );
      final names = rows.map((r) => r['name'] as String).toSet();
      expect(names, containsAll(<String>{
        'meta',
        'food_items',
        'recipes',
        'recipe_steps',
        'recipe_ingredients',
        'user_interactions',
        'fridge_items',
        'consumption_logs',
        'users',
      }));
    });
  });

  group('users table', () {
    test('UserProfile round-trips through the DB unchanged', () async {
      final db = await _freshDb();
      addTearDown(db.close);

      final profile = UserProfile(
        profileKey: ProfileKey.athleteBodybuilder,
        age: 28,
        sex: Sex.female,
        weightKg: 62.5,
        heightCm: 168,
        activityLevel: ActivityLevel.veryActive,
        mealsPerDay: 5,
        dailyCalories: 2600,
        dietaryRestrictions: const [
          DietaryRestriction.peanut,
          DietaryRestriction.gluten,
        ],
        avoidIngredients: const ['sugar', 'mushrooms'],
        createdAt: DateTime.fromMillisecondsSinceEpoch(1_700_000_000_000),
      );

      final id = await db.insert('users', profile.toDbMap());
      expect(id, greaterThan(0));

      final row = (await db.query('users', where: 'id = ?', whereArgs: [id])).single;
      final loaded = UserProfile.fromDbMap(row);

      expect(loaded.profileKey, profile.profileKey);
      expect(loaded.age, profile.age);
      expect(loaded.sex, profile.sex);
      expect(loaded.weightKg, profile.weightKg);
      expect(loaded.heightCm, profile.heightCm);
      expect(loaded.activityLevel, profile.activityLevel);
      expect(loaded.mealsPerDay, profile.mealsPerDay);
      expect(loaded.dailyCalories, profile.dailyCalories);
      expect(loaded.dietaryRestrictions.toSet(), profile.dietaryRestrictions.toSet());
      expect(loaded.avoidIngredients, profile.avoidIngredients);
      expect(loaded.createdAt, profile.createdAt);
    });

    test('NOT NULL constraints reject incomplete rows', () async {
      final db = await _freshDb();
      addTearDown(db.close);

      expect(
        () => db.insert('users', {
          'profile_key': 'general_adult',
          // age missing
          'sex': 'M',
          'weight_kg': 70.0,
          'height_cm': 175.0,
          'activity_level': 'moderate',
          'meals_per_day': 3,
          'daily_calories': 2400,
          'created_at': DateTime.now().millisecondsSinceEpoch,
        }),
        throwsA(isA<DatabaseException>()),
      );
    });

    test('delete clears all rows', () async {
      final db = await _freshDb();
      addTearDown(db.close);

      for (var i = 0; i < 3; i++) {
        await db.insert('users', {
          'profile_key': 'general_adult',
          'age': 30,
          'sex': 'M',
          'weight_kg': 70.0,
          'height_cm': 175.0,
          'activity_level': 'moderate',
          'meals_per_day': 3,
          'daily_calories': 2400,
          'created_at': DateTime.now().millisecondsSinceEpoch,
        });
      }
      expect((await db.query('users')).length, 3);

      final deleted = await db.delete('users');
      expect(deleted, 3);
      expect((await db.query('users')).length, 0);
    });
  });

  group('fridge_items table', () {
    test('insert + query + update + delete with TEXT primary key', () async {
      final db = await _freshDb();
      addTearDown(db.close);

      final now = DateTime.now().millisecondsSinceEpoch;
      await db.insert('fridge_items', {
        'id': 'item_test_1',
        'name': 'Bell Pepper',
        'category': 'produce',
        'amount': 3,
        'unit': 'pieces',
        'added_date': now,
      });
      await db.insert('fridge_items', {
        'id': 'item_test_2',
        'name': 'Cheddar Cheese',
        'category': 'dairy',
        'amount': 200,
        'unit': 'grams',
        'added_date': now,
      });

      final produce = await db.query('fridge_items',
          where: 'category = ?', whereArgs: ['produce']);
      expect(produce, hasLength(1));
      expect(produce.first['name'], 'Bell Pepper');

      final updated = await db.update(
        'fridge_items',
        {'amount': 2},
        where: 'id = ?',
        whereArgs: ['item_test_1'],
      );
      expect(updated, 1);
      final after = await db.query('fridge_items',
          where: 'id = ?', whereArgs: ['item_test_1']);
      expect(after.single['amount'], 2);

      final deleted = await db.delete('fridge_items',
          where: 'id = ?', whereArgs: ['item_test_2']);
      expect(deleted, 1);
      expect((await db.query('fridge_items')).length, 1);
    });

    test('accepts the full column set written by FridgeService._toDbMap', () async {
      // Regression: an earlier asset DB shipped without expiry_date /
      // added_date / image_url / notes / receipt_id / household_id /
      // is_frozen, so inserts from the app crashed at runtime. This locks the
      // schema in.
      final db = await _freshDb();
      addTearDown(db.close);

      final id = await db.insert('fridge_items', {
        'id': '52dd1c8f-c1e5-4a47-b3b5-c5c143ead15e',
        'name': 'Steamed Broccoli (1 cup)',
        'category': 'vegetables',
        'amount': 1.0,
        'unit': 'pieces',
        'expiry_date': 1779624773033,
        'added_date': 1779192773033,
        'image_url': null,
        'notes': 'Added from database',
        'receipt_id': null,
        'household_id': 'default',
        'is_frozen': 0,
      });
      expect(id, isNot(0));

      final row = (await db.query('fridge_items')).single;
      expect(row['expiry_date'], 1779624773033);
      expect(row['added_date'], 1779192773033);
      expect(row['household_id'], 'default');
      expect(row['is_frozen'], 0);
    });
  });

  group('consumption_logs table', () {
    test('insert + date-range query returns matching rows', () async {
      final db = await _freshDb();
      addTearDown(db.close);

      final now = DateTime(2026, 5, 19, 10);
      Future<void> log(String name, DateTime when, {bool fromFridge = true}) {
        return db.insert('consumption_logs', {
          'item_name': name,
          'category': 'produce',
          'amount': 1.0,
          'unit': 'pieces',
          'is_from_fridge': fromFridge ? 1 : 0,
          'date': when.millisecondsSinceEpoch,
        });
      }

      await log('Apple', now.subtract(const Duration(days: 2)));
      await log('Banana', now.subtract(const Duration(hours: 2)));
      await log('Carrot', now, fromFridge: false);

      final startOfToday = DateTime(now.year, now.month, now.day);
      final today = await db.query(
        'consumption_logs',
        where: 'date >= ?',
        whereArgs: [startOfToday.millisecondsSinceEpoch],
      );
      expect(today, hasLength(2));
      expect(today.map((r) => r['item_name']).toSet(), {'Banana', 'Carrot'});

      final external = await db.query(
        'consumption_logs',
        where: 'is_from_fridge = 0',
      );
      expect(external, hasLength(1));
      expect(external.single['item_name'], 'Carrot');
    });
  });

  group('KB ingredient match', () {
    test('full / partial / zero match are classified correctly', () {
      // Full match: every recipe ingredient is in the fridge.
      var r = KbRecommenderService.ingredientMatch(
        ['fresh basil', 'olive oil', 'pasta', 'parmesan cheese'],
        ['fresh basil', 'olive oil', 'pasta'],
      );
      expect(r.ratio, 1.0);
      expect(r.missing, isEmpty);

      // Partial — 1 of 3 missing (substring match finds 'tomato' inside
      // 'cherry tomatoes').
      r = KbRecommenderService.ingredientMatch(
        ['cherry tomatoes', 'mozzarella'],
        ['tomato', 'mozzarella', 'basil'],
      );
      expect(r.ratio, closeTo(2 / 3, 0.001));
      expect(r.missing, ['basil']);

      // No fridge at all.
      r = KbRecommenderService.ingredientMatch(
        const [],
        ['anything'],
      );
      expect(r.ratio, 0);
      expect(r.missing, ['anything']);

      // Empty recipe ingredient list → ratio 0, no items.
      r = KbRecommenderService.ingredientMatch(['apple'], const []);
      expect(r.ratio, 0);
      expect(r.matched, isEmpty);
      expect(r.missing, isEmpty);
    });

    test('matches verbose food-table names against bare recipe ingredients', () {
      // Regression: fridge items pulled from food_items look like
      // "Steamed Broccoli (1 cup)" but recipe ingredients are bare "broccoli".
      // The old substring matcher missed every pair like this, leaving KB
      // with no candidates to score.
      final r = KbRecommenderService.ingredientMatch(
        [
          'Steamed Broccoli (1 cup)',
          'Grilled Chicken Salad',
          'Greek Yogurt (plain 1 cup)',
        ],
        ['broccoli', 'chicken breast', 'yogurt', 'paprika'],
      );
      expect(r.matched, containsAll(['broccoli', 'chicken breast', 'yogurt']));
      expect(r.missing, ['paprika']);
      expect(r.ratio, closeTo(3 / 4, 0.001));
    });
  });
}
