import 'package:sqflite/sqflite.dart';
import 'package:sqflite_common_ffi_web/sqflite_ffi_web.dart';

/// Initialize sqflite for web using sql.js (SQLite compiled to WASM).
Future<void> initDbFactory() async {
  databaseFactory = databaseFactoryFfiWeb;
}
