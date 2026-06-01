// Web stub — provides the same surface as the dart:io types used in
// document_viewer_screen.dart. These classes are never actually called
// on web (all usages are guarded by `if (kIsWeb) return`), so the
// implementations are intentionally empty.

class File {
  final String path;
  const File(this.path);
  Future<File> writeAsBytes(List<int> bytes, {bool flush = false}) async =>
      this;
}

class Platform {
  static const String pathSeparator = '/';
}
