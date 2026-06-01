import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import 'package:arl_app/core/theme/arl_colors.dart';
import 'package:arl_app/core/version/app_version_check.dart';

/// Riverpod future provider that runs the version check once per process
/// and caches the result. Watched by [VersionBanner].
final appVersionCheckProvider = FutureProvider<AppUpdate?>((ref) {
  return AppVersionCheck.check();
});

/// Renders nothing when the app is up to date.
///
/// When a newer release is available:
///   * Non-critical → a dismissible strip below the AppBar saying
///     "New version available — tap to download" with the version name
///     in muted text. Tapping launches [AppUpdate.apkUrl] in the
///     external browser.
///   * Critical → the strip is non-dismissible AND a modal alert is
///     surfaced once on first build, blocking the user until they
///     either tap "Update now" (launches the APK URL) or close the
///     dialog (the strip stays visible).
class VersionBanner extends ConsumerStatefulWidget {
  const VersionBanner({super.key});

  @override
  ConsumerState<VersionBanner> createState() => _VersionBannerState();
}

class _VersionBannerState extends ConsumerState<VersionBanner> {
  bool _dismissed = false;
  bool _criticalDialogShown = false;

  Future<void> _openUpdateUrl(AppUpdate update) async {
    final raw = update.apkUrl ?? update.webUrl;
    if (raw == null || raw.isEmpty) return;
    final uri = Uri.tryParse(raw);
    if (uri == null) return;
    try {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (_) {
      // Best-effort — never crash the banner on a bad URL.
    }
  }

  void _maybeShowCriticalDialog(AppUpdate update) {
    if (_criticalDialogShown) return;
    _criticalDialogShown = true;
    // Schedule for after the current frame so we can pop a dialog
    // from inside a build method safely.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (ctx) => AlertDialog(
          title: const Text('Update required'),
          content: Text(
            update.releaseNotes?.isNotEmpty == true
                ? 'Version ${update.versionName} is required to continue.\n\n${update.releaseNotes}'
                : 'Version ${update.versionName} is required to continue.',
            style: const TextStyle(fontFamily: 'Inter'),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('Later'),
            ),
            FilledButton(
              onPressed: () {
                Navigator.of(ctx).pop();
                _openUpdateUrl(update);
              },
              child: const Text('Update now'),
            ),
          ],
        ),
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(appVersionCheckProvider);
    final update = async.valueOrNull;
    if (update == null) return const SizedBox.shrink();
    if (_dismissed && !update.isCritical) return const SizedBox.shrink();

    if (update.isCritical) {
      _maybeShowCriticalDialog(update);
    }

    final bg = update.isCritical ? ArlColors.earth : ArlColors.primary;

    return Material(
      color: bg,
      child: InkWell(
        onTap: () => _openUpdateUrl(update),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
          child: Row(
            children: [
              const Icon(
                Icons.system_update_alt,
                color: Colors.white,
                size: 16,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Row(
                  children: [
                    const Flexible(
                      child: Text(
                        'New version available — tap to download',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 12,
                          fontFamily: 'Inter',
                          fontWeight: FontWeight.w600,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      'v${update.versionName}',
                      style: const TextStyle(
                        color: Color(0xFFE0E0D8),
                        fontSize: 11,
                        fontFamily: 'Inter',
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              if (!update.isCritical)
                IconButton(
                  tooltip: 'Dismiss',
                  icon: const Icon(Icons.close, color: Colors.white, size: 16),
                  visualDensity: VisualDensity.compact,
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(
                    minWidth: 24,
                    minHeight: 24,
                  ),
                  onPressed: () => setState(() => _dismissed = true),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
