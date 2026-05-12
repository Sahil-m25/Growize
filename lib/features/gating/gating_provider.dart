import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:arl_app/core/providers/repositories.dart';

/// B.T7: Enum describing the gate state.
enum GateState {
  ok,
  forceUpdate,
  maintenance,
}

/// B.T7: Gate model holding version info and gate state.
class GateStatus {
  final GateState state;
  final String currentVersion;
  final String? minimumVersion;

  GateStatus({
    required this.state,
    required this.currentVersion,
    this.minimumVersion,
  });
}

/// B.T7: Provider that checks app_config and package version.
/// Returns GateStatus.ok if the app is allowed, or forceUpdate / maintenance
/// if the app needs an update or is in maintenance mode.
final gateStatusProvider = FutureProvider<GateStatus>((ref) async {
  final packageInfo = await PackageInfo.fromPlatform();
  final currentVersion = packageInfo.version;

  try {
    final appConfig = ref.watch(appConfigRepositoryProvider);
    final config = await appConfig.all();

    // Check maintenance mode first.
    final maintenanceMode = config['maintenance_mode']?.toLowerCase() ?? 'false';
    if (maintenanceMode == 'true') {
      return GateStatus(
        state: GateState.maintenance,
        currentVersion: currentVersion,
      );
    }

    // Check minimum app version.
    final minVersion = config['min_app_version'] ?? '1.0.0';
    if (_shouldUpdate(currentVersion, minVersion)) {
      return GateStatus(
        state: GateState.forceUpdate,
        currentVersion: currentVersion,
        minimumVersion: minVersion,
      );
    }

    return GateStatus(
      state: GateState.ok,
      currentVersion: currentVersion,
    );
  } catch (e) {
    // If app_config fetch fails, allow the app to proceed (network error).
    return GateStatus(
      state: GateState.ok,
      currentVersion: currentVersion,
    );
  }
});

/// Simple version comparison: returns true if current < minimum.
/// Assumes semantic versioning (MAJOR.MINOR.PATCH).
bool _shouldUpdate(String current, String minimum) {
  try {
    final c = current.split('.').map(int.parse).toList();
    final m = minimum.split('.').map(int.parse).toList();

    for (int i = 0; i < 3; i++) {
      final cv = i < c.length ? c[i] : 0;
      final mv = i < m.length ? m[i] : 0;
      if (cv < mv) return true;
      if (cv > mv) return false;
    }
    return false;
  } catch (_) {
    return false;
  }
}
