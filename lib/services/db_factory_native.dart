import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// Initialize sqflite for native desktop (macOS, Linux, Windows).
/// On iOS/Android sqflite works out of the box — this is a no-op safeguard.
Future<void> initDbFactory() async {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;
}
