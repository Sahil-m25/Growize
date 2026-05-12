import 'package:hive_flutter/hive_flutter.dart';

abstract final class HiveBoxes {
  static const String home       = 'home_cache';
  static const String projects   = 'projects_cache';
  static const String financials = 'financials_cache';
  static const String gallery    = 'gallery_cache';
  static const String documents  = 'documents_cache';
  static const String activity   = 'activity_cache';
  static const String auth       = 'auth_cache';
}

bool _initialized = false;

/// Initialises Hive and opens the boxes the app reads/writes to.
/// Idempotent — safe to call multiple times.
Future<void> initHive() async {
  if (_initialized) return;
  await Hive.initFlutter();
  await Future.wait([
    Hive.openBox<dynamic>(HiveBoxes.home),
    Hive.openBox<dynamic>(HiveBoxes.projects),
    Hive.openBox<dynamic>(HiveBoxes.financials),
    Hive.openBox<dynamic>(HiveBoxes.gallery),
    Hive.openBox<dynamic>(HiveBoxes.documents),
    Hive.openBox<dynamic>(HiveBoxes.activity),
    Hive.openBox<dynamic>(HiveBoxes.auth),
  ]);
  _initialized = true;
}

/// Quick getter so callers don't need to remember box names.
Box<dynamic> hiveBox(String name) => Hive.box<dynamic>(name);
