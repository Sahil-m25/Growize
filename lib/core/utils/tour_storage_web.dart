// Web-specific tour "seen" flag using window.localStorage directly.
// flutter_secure_storage on web uses IndexedDB for its key which can fail
// silently in private/incognito browsers. Plain localStorage is more reliable
// for a non-sensitive boolean flag like "tour seen".
import 'dart:js_interop';

const String _key = 'arl_tour_seen_v2_web';

@JS('localStorage.getItem')
external JSString? _getItem(JSString key);

@JS('localStorage.setItem')
external void _setItem(JSString key, JSString value);

Future<bool> readTourSeen() async {
  try {
    final v = _getItem(_key.toJS);
    return v.dartify() == 'true';
  } catch (_) {
    return false;
  }
}

Future<void> writeTourSeen() async {
  try {
    _setItem(_key.toJS, 'true'.toJS);
  } catch (_) {
    // localStorage unavailable — best effort.
  }
}
