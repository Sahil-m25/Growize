// Web-only session idle guard.
// Tracks the last user-activity timestamp in localStorage.
// On app open / tab focus, if idle > [_kIdleMinutes], the caller signs out.
import 'dart:js_interop';

const int _kIdleMinutes = 60; // sign out after 60 min of inactivity
const String _kKey = 'arl_session_last_active';

@JS('localStorage.getItem')
external JSString? _get(JSString key);

@JS('localStorage.setItem')
external void _set(JSString key, JSString value);

@JS('localStorage.removeItem')
external void _remove(JSString key);

/// Call on every meaningful interaction (tap, navigation).
void refreshWebSession() {
  _set(_kKey.toJS,
      DateTime.now().millisecondsSinceEpoch.toString().toJS);
}

/// Returns true if the user has been idle longer than [_kIdleMinutes].
/// Returns false when there is no previous record (fresh first open).
bool isWebSessionExpired() {
  try {
    final raw = _get(_kKey.toJS);
    if (raw == null) return false;
    final ms = int.tryParse(raw.toDart);
    if (ms == null) return false;
    final lastActive = DateTime.fromMillisecondsSinceEpoch(ms);
    return DateTime.now().difference(lastActive).inMinutes >= _kIdleMinutes;
  } catch (_) {
    return false;
  }
}

/// Call on sign-out so the timestamp is cleared.
void clearWebSession() {
  try { _remove(_kKey.toJS); } catch (_) {}
}
