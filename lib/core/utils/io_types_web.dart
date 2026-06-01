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
  static const bool isAndroid = false;
  static const bool isIOS = false;
  static const bool isMacOS = false;
  static const bool isWindows = false;
  static const bool isLinux = false;
  static const bool isFuchsia = false;
}
