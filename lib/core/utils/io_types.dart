// Native implementation — re-exports real dart:io types.
// Imported via conditional import; web builds use io_types_web.dart instead.
export 'dart:io' show File, Platform;
