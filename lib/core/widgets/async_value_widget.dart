import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:arl_app/core/theme/arl_colors.dart';

/// Tiny helper that takes an [AsyncValue] and renders standard
/// loading / error states so screens don't repeat boilerplate.
class AsyncValueWidget<T> extends StatelessWidget {
  final AsyncValue<T> value;
  final Widget Function(T data) data;
  final VoidCallback? onRetry;
  final Widget? loading;

  const AsyncValueWidget({
    super.key,
    required this.value,
    required this.data,
    this.onRetry,
    this.loading,
  });

  @override
  Widget build(BuildContext context) {
    return value.when(
      data: data,
      loading: () =>
          loading ??
          const Center(
            child: Padding(
              padding: EdgeInsets.all(24),
              child: CircularProgressIndicator(
                color: ArlColors.primary,
                strokeWidth: 2,
              ),
            ),
          ),
      // Repos return cached data on failure, so this branch should
      // rarely fire. When it does, show a calm "offline" placeholder
      // instead of dumping the exception string.
      error: (_, __) => _ErrorBox(
        message: 'Tap retry once you\'re back online.',
        onRetry: onRetry,
      ),
    );
  }
}

class _ErrorBox extends StatelessWidget {
  final String message;
  final VoidCallback? onRetry;

  const _ErrorBox({required this.message, this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.cloud_off_outlined,
                color: ArlColors.muted, size: 32),
            const SizedBox(height: 10),
            const Text(
              'Could not load',
              style: TextStyle(
                fontFamily: 'Inter',
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: ArlColors.charcoal,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              message,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontFamily: 'Inter',
                fontSize: 11,
                color: ArlColors.muted,
              ),
            ),
            if (onRetry != null) ...[
              const SizedBox(height: 12),
              OutlinedButton(
                onPressed: onRetry,
                style: OutlinedButton.styleFrom(
                  foregroundColor: ArlColors.primary,
                  side: const BorderSide(color: ArlColors.primary),
                ),
                child: const Text('Retry'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
