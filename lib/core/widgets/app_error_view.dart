import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:arl_app/core/theme/arl_colors.dart';

/// Branded, self-contained "something went wrong" view.
///
/// Two uses:
///   1. As the global [ErrorWidget.builder] replacement so an unexpected
///      build-time exception renders a calm branded card instead of the
///      red-and-yellow Flutter error screen. In that role it can be
///      inserted ANYWHERE in the tree — possibly above the [MaterialApp]
///      — so it deliberately provides its own [Directionality] and a
///      transparent [Material] and never assumes a Scaffold ancestor.
///   2. As a reusable inline error placeholder for screens that want a
///      friendlier fallback than a bare message.
///
/// The raw exception is only surfaced in debug builds; release builds
/// show a generic, reassuring message (Sentry still captures the detail).
class AppErrorView extends StatelessWidget {
  final String title;
  final String message;
  final VoidCallback? onRetry;

  /// Optional technical detail — only rendered in debug builds.
  final String? debugDetail;

  const AppErrorView({
    super.key,
    this.title = 'Something went wrong',
    this.message =
        "We couldn't display this just now. Please try again in a moment.",
    this.onRetry,
    this.debugDetail,
  });

  /// Builds the view used to replace a widget that threw during build.
  factory AppErrorView.forFlutterError(FlutterErrorDetails details) {
    return AppErrorView(
      debugDetail: details.exceptionAsString(),
    );
  }

  @override
  Widget build(BuildContext context) {
    // Wrap in Directionality + transparent Material so the view renders
    // correctly even when it replaces a node sitting above MaterialApp.
    return Directionality(
      textDirection: TextDirection.ltr,
      child: Material(
        type: MaterialType.transparency,
        child: Container(
          color: ArlColors.cream,
          alignment: Alignment.center,
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.error_outline_rounded,
                  color: ArlColors.earth, size: 40),
              const SizedBox(height: 12),
              Text(
                title,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontFamily: 'Inter',
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  color: ArlColors.charcoal,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                message,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontFamily: 'Inter',
                  fontSize: 12,
                  color: ArlColors.muted,
                ),
              ),
              if (kDebugMode && debugDetail != null) ...[
                const SizedBox(height: 12),
                Text(
                  debugDetail!,
                  textAlign: TextAlign.center,
                  maxLines: 6,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontFamily: 'Inter',
                    fontSize: 10,
                    color: ArlColors.earth,
                  ),
                ),
              ],
              if (onRetry != null) ...[
                const SizedBox(height: 16),
                OutlinedButton(
                  onPressed: onRetry,
                  style: OutlinedButton.styleFrom(
                    foregroundColor: ArlColors.primary,
                    side: const BorderSide(color: ArlColors.primary),
                  ),
                  child: const Text('Try again'),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
