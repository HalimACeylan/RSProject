import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

/// Central SQLite database service.  Singleton.
///
/// Copies the pre-populated asset database on first launch and handles queries.
class DatabaseService {
  DatabaseService._();
  static final DatabaseService instance = DatabaseService._();

  Database? _db;
  bool _isInitialized = false;

  /// Whether the database was successfully opened.
  bool get isReady => _db != null;

  // ── Initialization ────────────────────────────────────────────────

  /// Optional dev-mode override: pass an absolute path with
  /// `--dart-define=DB_FILE=/abs/path/to/assets/fridge_app.db`. When set, the
  /// app opens that file directly and skips the asset-copy + platform-path
  /// dance. This lets Python scripts in `datasets_to_use/` read the live app
  /// state while the app is running (desktop only — mobile asset bundles are
  /// read-only).
  static const String _dbFileOverride =
      String.fromEnvironment('DB_FILE', defaultValue: '');

  Future<void> initialize() async {
    if (_isInitialized) return;
    _isInitialized = true; // prevent re-entry
    try {
      final String dbPath;
      if (_dbFileOverride.isNotEmpty) {
        dbPath = _dbFileOverride;
        debugPrint('[DB] Using DB_FILE override: $dbPath');
      } else {
        String resolved;
        try {
          final dir = await getDatabasesPath();
          resolved = p.join(dir, 'fridge_app.db');
        } catch (_) {
          resolved = 'fridge_app.db';
        }
        dbPath = resolved;

        final dbExists = await databaseFactory.databaseExists(dbPath);
        if (!dbExists) {
          debugPrint('[DB] Pre-populated database not found locally. Copying from assets...');
          try {
            final ByteData data = await rootBundle.load('assets/fridge_app.db');
            final Uint8List bytes = data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
            await databaseFactory.writeDatabaseBytes(dbPath, bytes);
            debugPrint('[DB] Database copied successfully.');
          } catch (e) {
            debugPrint('[DB] Error copying database from assets: $e');
          }
        }
      }

      debugPrint('────────────────────────────────────────────');
      if (_dbFileOverride.isNotEmpty) {
        debugPrint('[DB] DB_FILE override ACTIVE — writing to your repo asset.');
      } else {
        debugPrint('[DB] DB_FILE override NOT SET — writing to OS sandbox.');
        debugPrint('     To inspect from DBeaver/Python:');
        debugPrint('     - On macOS desktop: re-run with --dart-define=DB_FILE=\$(pwd)/assets/fridge_app.db');
        debugPrint('     - Otherwise: open the path below directly in DBeaver.');
      }
      debugPrint('[DB] Path: $dbPath');
      debugPrint('────────────────────────────────────────────');
      _db = await openDatabase(
        dbPath,
        version: 1,
      );

      // WAL lets external read-only processes (e.g. the Python inspector in
      // datasets_to_use/) query the DB concurrently with the app without
      // hitting "database is locked". The setting persists in the file header
      // so it only needs to be applied once, but it's cheap to re-run on every
      // open. synchronous=NORMAL is the recommended pairing for WAL.
      if (_db != null) {
        try {
          await _db!.rawQuery('PRAGMA journal_mode=WAL');
          await _db!.execute('PRAGMA synchronous=NORMAL');
        } catch (e) {
          debugPrint('[DB] WAL setup failed (continuing): $e');
        }
      }
      
      // Safety check in case the asset DB was missing tables from recent migrations
      if (_db != null) {
        await _db!.execute('''
          CREATE TABLE IF NOT EXISTS consumption_logs (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            item_name TEXT NOT NULL,
            category TEXT,
            amount REAL,
            unit TEXT,
            is_from_fridge INTEGER,
            date INTEGER
          )
        ''');
        await _db!.execute('CREATE INDEX IF NOT EXISTS idx_consumption_logs_name ON consumption_logs(item_name)');

        await _db!.execute('''
          CREATE TABLE IF NOT EXISTS users (
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

        await _migrateFridgeItemsColumns();
      }
      
      debugPrint('[DB] Database opened successfully');
    } catch (e) {
      debugPrint('[DB] Failed to open database: $e');
      _db = null;
    }
  }

  /// Bring older `fridge_items` schemas up to what `FridgeService._toDbMap`
  /// writes. The original asset DB shipped with only 6 columns, so inserts
  /// from the app failed with "no column named expiry_date". Adds any missing
  /// columns idempotently using ALTER TABLE ADD COLUMN.
  Future<void> _migrateFridgeItemsColumns() async {
    if (_db == null) return;
    final existing = (await _db!.rawQuery('PRAGMA table_info(fridge_items)'))
        .map((r) => r['name'] as String)
        .toSet();
    const desired = <String, String>{
      'expiry_date': 'INTEGER',
      'added_date': 'INTEGER',
      'image_url': 'TEXT',
      'notes': 'TEXT',
      'receipt_id': 'TEXT',
      'household_id': 'TEXT',
      'is_frozen': 'INTEGER NOT NULL DEFAULT 0',
    };
    for (final entry in desired.entries) {
      if (existing.contains(entry.key)) continue;
      try {
        await _db!.execute(
          'ALTER TABLE fridge_items ADD COLUMN ${entry.key} ${entry.value}',
        );
        debugPrint('[DB] Added missing column fridge_items.${entry.key}');
      } catch (e) {
        debugPrint('[DB] Failed to add column ${entry.key}: $e');
      }
    }
  }

  // ── Generic Query Helpers ─────────────────────────────────────────

  Future<List<Map<String, dynamic>>> queryAll(String table) async {
    if (_db == null) return [];
    return _db!.query(table);
  }

  /// Search food items by name, returning up to [limit] results.
  Future<List<Map<String, dynamic>>> searchFoodItems(String query, {int limit = 30}) async {
    if (_db == null) return [];
    
    if (query.trim().isEmpty) {
      return _db!.query('food_items', limit: limit);
    }
    
    return _db!.query(
      'food_items',
      where: 'name LIKE ?',
      whereArgs: ['%${query.trim()}%'],
      limit: limit,
    );
  }

  /// Search food items by dataset category.
  Future<List<Map<String, dynamic>>> getPopularFoodItemsByCategory(String categoryKeyword, {int limit = 10}) async {
    if (_db == null) return [];
    
    return _db!.query(
      'food_items',
      where: 'category LIKE ?',
      whereArgs: ['%${categoryKeyword.trim()}%'],
      limit: limit,
    );
  }

  /// Log a consumption event.
  Future<int> logConsumption({
    required String itemName,
    required String category,
    required double amount,
    required String unit,
    required bool isFromFridge,
  }) async {
    if (_db == null) return -1;
    return _db!.insert('consumption_logs', {
      'item_name': itemName,
      'category': category,
      'amount': amount,
      'unit': unit,
      'is_from_fridge': isFromFridge ? 1 : 0,
      'date': DateTime.now().millisecondsSinceEpoch,
    });
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
}
