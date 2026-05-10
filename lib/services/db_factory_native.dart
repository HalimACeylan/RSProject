import 'dart:io' show Platform;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// Initialize sqflite for native platforms.
/// On iOS/Android, sqflite works out of the box — no override needed.
/// On macOS/Linux/Windows desktop, we need the FFI factory.
Future<void> initDbFactory() async {
  if (Platform.isMacOS || Platform.isLinux || Platform.isWindows) {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  }
  // On iOS/Android: do nothing — default factory is already correct.
}
