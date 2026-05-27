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

      debugPrint('[DB] Opening database at: $dbPath');
      _db = await openDatabase(
        dbPath,
        version: 1,
      );
      
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
      }
      
      debugPrint('[DB] Database opened successfully');
    } catch (e) {
      debugPrint('[DB] Failed to open database: $e');
      _db = null;
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
