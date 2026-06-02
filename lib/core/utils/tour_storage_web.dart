// Web-specific tour "seen" flag storage using window.localStorage directly.
// flutter_secure_storage on web uses IndexedDB for its encryption key, which
// fails silently in private/incognito browsers. This plain localStorage key
// is a reliable fallback — the tour seen flag is not sensitive data.
import 'dart:js_interop';

const String _kTourWebKey = 'arl_tour_seen_v2_web';

Future<bool> readTourSeen() async {
  try {
    final v = window.localStorage[_kTourWebKey.toJS];
    return v.dartify() == 'true';
  } catch (_) {
    return false;
  }
}

Future<void> writeTourSeen() async {
  try {
    window.localStorage[_kTourWebKey.toJS] = 'true'.toJS;
  } catch (_) {
    // localStorage unavailable — best effort.
  }
}

@JS('window')
external JSObject get window;

extension on JSObject {
  external JSAny? operator [](JSAny key);
  external void operator []=(JSAny key, JSAny value);
}
