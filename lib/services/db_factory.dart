/// Conditional export: picks the right DB factory init for the current platform.
library;

export 'db_factory_stub.dart'
    if (dart.library.io) 'db_factory_native.dart'
    if (dart.library.js_interop) 'db_factory_web.dart';
