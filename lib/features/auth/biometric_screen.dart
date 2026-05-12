import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/auth/biometric_guard.dart';
import '../../core/navigation/route_names.dart';
import '../../core/theme/arl_colors.dart';

/// Biometric verification gate. Two entry modes:
/// - Pushed from another screen (e.g. SecurityScreen enrolling the
///   biometric toggle) → pops with `true` on success, `false` on cancel.
/// - Reached directly without a stack → routes to home on success
///   (legacy startup gate path).
class BiometricScreen extends StatefulWidget {
  const BiometricScreen({super.key});

  @override
  State<BiometricScreen> createState() => _BiometricScreenState();
}

class _BiometricScreenState extends State<BiometricScreen> {
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    _attempt();
  }

  void _exit({required bool success}) {
    if (!mounted) return;
    if (context.canPop()) {
      context.pop(success);
    } else if (success) {
      context.go(RouteNames.home);
    } else {
      context.go(RouteNames.auth);
    }
  }

  Future<void> _attempt() async {
    setState(() => _loading = true);
    final ok = await BiometricGuard.authenticate();
    if (!mounted) return;
    if (ok) {
      _exit(success: true);
      return;
    }
    setState(() => _loading = false);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: ArlColors.primary,
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.fingerprint, size: 80, color: Colors.white70),
            const SizedBox(height: 24),
            const Text(
              'Verify to continue',
              style: TextStyle(
                color: Colors.white,
                fontSize: 18,
                fontWeight: FontWeight.w600,
                fontFamily: 'Inter',
              ),
            ),
            const SizedBox(height: 32),
            if (!_loading)
              TextButton(
                onPressed: _attempt,
                child: const Text('Try again',
                    style: TextStyle(color: ArlColors.gold)),
              ),
            if (_loading)
              const CircularProgressIndicator(color: ArlColors.gold),
            const SizedBox(height: 16),
            if (!_loading)
              TextButton(
                onPressed: () => _exit(success: false),
                child: const Text('Cancel',
                    style: TextStyle(color: Colors.white70)),
              ),
          ],
        ),
      ),
    );
  }
}
