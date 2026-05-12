import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Connectivity stream. We seed with the *current* connectivity state
/// before subscribing to changes — otherwise the stream is silent until
/// a transition happens, and any consumer reading `valueOrNull` defaults
/// to "offline" on a perfectly online device. That was the bug behind
/// the persistent "Offline — showing cached data" banner on first launch.
final connectivityProvider = StreamProvider<List<ConnectivityResult>>((ref) async* {
  final c = Connectivity();
  // 1. Emit the current state immediately.
  try {
    yield await c.checkConnectivity();
  } catch (_) {
    // Plugin error → assume online so we don't lock the user out.
    yield const [ConnectivityResult.wifi];
  }
  // 2. Then keep emitting on every change.
  yield* c.onConnectivityChanged;
});

/// True when the device has any active connectivity. Defaults to TRUE
/// while we're still waiting for the first stream value — avoids the
/// false-offline flash on cold start.
final isOnlineProvider = Provider<bool>((ref) {
  final result = ref.watch(connectivityProvider).valueOrNull;
  if (result == null) return true; // unknown yet — assume online
  return result.any((r) => r != ConnectivityResult.none);
});
