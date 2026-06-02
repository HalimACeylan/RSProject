// Integration test for the SQLite schema + CRUD layer used by the app.
//
// Runs against an in-memory database (sqflite_common_ffi) seeded with the
// same CREATE TABLE statements as scripts/build_db.dart, so it verifies the
// schema is consistent and that round-tripping through UserProfile.toDbMap /
// fromDbMap and other DB helpers works as expected.

import 'package:flutter_test/flutter_test.dart';
import 'package:fridge_app/models/meal_slot.dart';
import 'package:fridge_app/models/recipe.dart';
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
    is_pregnant INTEGER NOT NULL DEFAULT 0,
    dietary_restrictions TEXT,
    avoid_ingredients TEXT,
    created_at INTEGER NOT NULL
  )''',
  '''
  CREATE TABLE cooked_recipes (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    recipe_id INTEGER NOT NULL,
    recipe_name TEXT NOT NULL,
    cooked_at INTEGER NOT NULL
  )''',
  '''
  CREATE TABLE dismissed_recipes (
    recipe_id INTEGER PRIMARY KEY,
    dismissed_at INTEGER NOT NULL
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
        'cooked_recipes',
        'dismissed_recipes',
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
        isPregnant: true,
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
      expect(loaded.isPregnant, isTrue);
      expect(loaded.dietaryRestrictions.toSet(), profile.dietaryRestrictions.toSet());
      expect(loaded.avoidIngredients, profile.avoidIngredients);
      expect(loaded.createdAt, profile.createdAt);
      // Pregnancy dominates calorie + meal defaults regardless of profile_key.
      expect(loaded.dailyCalories, 2300);
      expect(loaded.mealsPerDay, 4);
      expect(loaded.scoringKey, 'pregnant');
    });

    test('non-pregnant profile uses profile_key for scoring/calories', () {
      final profile = UserProfile(
        profileKey: ProfileKey.athleteBodybuilder,
        age: 28,
        sex: Sex.male,
        dietaryRestrictions: const [],
        avoidIngredients: const [],
        createdAt: DateTime.fromMillisecondsSinceEpoch(0),
      );
      expect(profile.scoringKey, 'athlete_bodybuilder');
      expect(profile.dailyCalories, 3000);
      expect(profile.mealsPerDay, 5);
    });

    test('legacy profile_key values fold via fromDbValue', () {
      // Older installs may have stored split keys (athlete, bodybuilder,
      // pregnant, lactating, pregnant_lactating) — fromDbValue collapses
      // them. The split-pregnancy half is handled at DB-migration time by
      // also flipping is_pregnant; fromDbValue alone falls back to
      // generalAdult so we never crash.
      expect(ProfileKey.fromDbValue('athlete'), ProfileKey.athleteBodybuilder);
      expect(ProfileKey.fromDbValue('bodybuilder'), ProfileKey.athleteBodybuilder);
      expect(ProfileKey.fromDbValue('pregnant'), ProfileKey.generalAdult);
      expect(ProfileKey.fromDbValue('lactating'), ProfileKey.generalAdult);
      expect(ProfileKey.fromDbValue('pregnant_lactating'), ProfileKey.generalAdult);
      expect(ProfileKey.fromDbValue('unknown'), ProfileKey.generalAdult);
      for (final p in ProfileKey.values) {
        expect(ProfileKey.fromDbValue(p.dbValue), p);
      }
    });

    test('NOT NULL constraints reject incomplete rows', () async {
      final db = await _freshDb();
      addTearDown(db.close);

      expect(
        () => db.insert('users', {
          'profile_key': 'general_adult',
          // age missing
          'sex': 'M',
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

  group('user_interactions table', () {
    test('insert with offset user_id keeps app rows separate from synthetic', () async {
      // Mirrors what CookingService.markCooked writes when the user supplies
      // a rating: user_id is shifted by 1_000_000 so it never collides with
      // the ~600 synthetic users imported from synthetic_interactions.csv.
      final db = await _freshDb();
      addTearDown(db.close);

      // Pretend the synthetic CSV has a (user_id=42, recipe_id=31490) row.
      await db.insert('user_interactions', {
        'user_id': 42,
        'recipe_id': 31490,
        'rating': 5,
        'profile_tag': 'meat_lover',
      });
      // App user with profile id=42 rates the same recipe — offset keeps
      // the rows distinct.
      const offset = 1000000;
      await db.insert('user_interactions', {
        'user_id': offset + 42,
        'recipe_id': 31490,
        'rating': 3,
        'profile_tag': 'general_adult',
      });

      final synth = await db.query(
        'user_interactions',
        where: 'user_id < ?', whereArgs: [offset],
      );
      final app = await db.query(
        'user_interactions',
        where: 'user_id >= ?', whereArgs: [offset],
      );
      expect(synth, hasLength(1));
      expect(synth.single['profile_tag'], 'meat_lover');
      expect(app, hasLength(1));
      expect(app.single['profile_tag'], 'general_adult');
      expect(app.single['rating'], 3);
    });
  });

  group('dismissed_recipes table', () {
    test('insert + idempotent re-dismiss + restore', () async {
      final db = await _freshDb();
      addTearDown(db.close);

      // DatabaseService.insert defaults to ConflictAlgorithm.replace, so a
      // re-dismiss in production overwrites the timestamp. Match that here.
      Future<void> dismiss(int rid, int at) => db.insert(
            'dismissed_recipes',
            {'recipe_id': rid, 'dismissed_at': at},
            conflictAlgorithm: ConflictAlgorithm.replace,
          );

      await dismiss(31490, 1700000000000);
      await dismiss(31490, 1700000999000); // re-dismiss replaces

      var rows = await db.query('dismissed_recipes');
      expect(rows, hasLength(1));
      expect(rows.single['dismissed_at'], 1700000999000);

      // Restore deletes the row.
      final deleted = await db.delete(
        'dismissed_recipes',
        where: 'recipe_id = ?',
        whereArgs: [31490],
      );
      expect(deleted, 1);
      rows = await db.query('dismissed_recipes');
      expect(rows, isEmpty);
    });
  });

  group('cooked_recipes table', () {
    test('insert + date-range query returns recent cooks', () async {
      final db = await _freshDb();
      addTearDown(db.close);

      final now = DateTime(2026, 5, 19, 18).millisecondsSinceEpoch;
      await db.insert('cooked_recipes', {
        'recipe_id': 31490,
        'recipe_name': 'a bit different  breakfast pizza',
        'cooked_at': now - const Duration(days: 2).inMilliseconds,
      });
      await db.insert('cooked_recipes', {
        'recipe_id': 44061,
        'recipe_name': "amish  tomato ketchup  for canning",
        'cooked_at': now,
      });

      final today = DateTime(2026, 5, 19).millisecondsSinceEpoch;
      final recent = await db.query(
        'cooked_recipes',
        where: 'cooked_at >= ?',
        whereArgs: [today],
      );
      expect(recent, hasLength(1));
      expect(recent.single['recipe_id'], 44061);
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
      // Full match: every recipe ingredient is covered by some fridge entry.
      var r = KbRecommenderService.ingredientMatch(
        ['fresh basil', 'olive oil', 'pasta', 'parmesan cheese'],
        ['fresh basil', 'olive oil', 'pasta'],
      );
      expect(r.ratio, 1.0);
      expect(r.missing, isEmpty);

      // Plural tolerance: "tomato" is covered by "tomatoes" in
      // "cherry tomatoes". Basil isn't in the fridge.
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

    test('verbose fridge names still match single-word recipe ingredients', () {
      // Production callers lowercase before invoking; mimic that here.
      // 'broccoli' is a substring of 'steamed broccoli (1 cup)' → matched.
      // 'yogurt' is a substring of 'greek yogurt (plain 1 cup)' → matched.
      // 'chicken breast' isn't a substring of any fridge entry (nor any of
      //   them a substring of 'chicken breast') → missing.
      // 'paprika' has no fridge entry → missing.
      final r = KbRecommenderService.ingredientMatch(
        [
          'steamed broccoli (1 cup)',
          'chicken (4oz grilled)',
          'greek yogurt (plain 1 cup)',
        ],
        ['broccoli', 'chicken breast', 'yogurt', 'paprika'],
      );
      expect(r.matched, containsAll(['broccoli', 'yogurt']));
      expect(r.missing, containsAll(['chicken breast', 'paprika']));
      expect(r.ratio, closeTo(2 / 4, 0.001));
    });

    test('MealPlan.forCount mirrors Python MEAL_PLANS', () {
      // English equivalents of the Python KB's MEAL_PLANS table.
      expect(MealPlan.forCount(3).map((m) => m.label).toList(),
          ['Breakfast', 'Lunch', 'Dinner']);
      expect(MealPlan.forCount(4).map((m) => m.label).toList(),
          ['Breakfast', 'Lunch', 'Snack', 'Dinner']);
      expect(MealPlan.forCount(5).map((m) => m.label).toList(),
          ['Breakfast', 'Morning Snack', 'Lunch', 'Afternoon Snack', 'Dinner']);
      expect(MealPlan.forCount(6).map((m) => m.label).toList(), [
        'Breakfast', 'Morning Snack', 'Lunch',
        'Afternoon Snack', 'Dinner', 'Late Snack',
      ]);
      // Slot indices are 0-based and total tracks the parent plan size.
      final five = MealPlan.forCount(5);
      expect(five[2].index, 2);
      expect(five[2].totalSlots, 5);
      expect(five[2].mealsRemainingAtStart, 3); // 5 - 2
      // Unknown counts fall back to the 3-meal plan.
      expect(MealPlan.forCount(99).map((m) => m.label).toList(),
          ['Breakfast', 'Lunch', 'Dinner']);
    });

    test('reasonsByCategory groups WHO / body-type / ingredient / CF', () {
      // Mock reasons sampled from real KB output: a WHO macro penalty,
      // a profile-specific recovery bonus, two ingredient nudges, and a
      // CF score boost. The categoriser sorts them by source so the UI
      // can answer "why was this recommended?" without re-running KB.
      const recipe = Recipe(id: 'db_1', title: 'Sample');
      final scored = ScoredRecipe(
        recipe: recipe,
        score: 95,
        matchRatio: 1.0,
        matchedIngredients: const [],
        missingIngredients: const [],
        isFullMatch: true,
        reasons: const [
          'Prot↓ 8<75 (-30.0)',     // WHO macro
          'Cal↑ 600>500 (-5.0)',    // WHO macro
          '💪Prot recovery +12.0',   // body-type bonus
          '✨chicken +5',            // profile ingredient bonus
          '⚠️butter -3',             // profile ingredient penalty
          'CF +18.4',                // collaborative-filter boost
        ],
      );

      final groups = scored.reasonsByCategory;
      expect(groups[ReasonCategory.who],
          ['Prot↓ 8<75 (-30.0)', 'Cal↑ 600>500 (-5.0)']);
      expect(groups[ReasonCategory.bodyType], ['💪Prot recovery +12.0']);
      expect(groups[ReasonCategory.ingredient],
          ['✨chicken +5', '⚠️butter -3']);
      expect(groups[ReasonCategory.cf], ['CF +18.4']);
    });

    test('"broccoli 1 cup" matches "broccoli" but not "broccoli soup"', () {
      // Regression pinning the user-reported rule: extra words on the recipe
      // side disqualify the match, since the fridge entry doesn't contribute
      // a `soup` token.
      final r = KbRecommenderService.ingredientMatch(
        ['broccoli 1 cup'],
        ['broccoli', 'broccoli soup', 'creamy broccoli soup'],
      );
      expect(r.matched, ['broccoli']);
      expect(r.missing, containsAll(['broccoli soup', 'creamy broccoli soup']));
    });
  });
}
