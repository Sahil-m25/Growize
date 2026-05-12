// Top-level app widget is now defined in main.dart so the same file
// owns bootstrapping (env load, Hive, Supabase) and the widget tree.
// Keeping this file as a thin re-export so any existing imports still resolve.
export 'main.dart' show ArlApp;
