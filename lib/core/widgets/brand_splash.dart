import 'package:flutter/material.dart';

import 'package:arl_app/core/theme/arl_colors.dart';

/// Branded first-load screen.
///
/// Visually identical to the native launch screens (Android
/// launch_background / Android 12 splash, iOS LaunchScreen.storyboard)
/// and the web splash in `web/index.html`: cream background, centred
/// Growize "g" mark, wordmark underneath and a thin gold progress bar.
/// Because every layer shares the same background and mark position,
/// the hand-off native splash -> web splash -> Flutter boot -> first
/// screen reads as one continuous screen instead of a series of
/// flashes (previously white -> green -> cream spinner -> green spinner).
///
/// Used for: the app_config gate check, and the app-lock settings read
/// on cold start. Keep the mark size (72, centred) and the text offset
/// in sync with web/index.html (`#gz-mark`, `#gz-text`).
class BrandSplash extends StatefulWidget {
  const BrandSplash({super.key});

  @override
  State<BrandSplash> createState() => _BrandSplashState();
}

class _BrandSplashState extends State<BrandSplash>
    with SingleTickerProviderStateMixin {
  static const double _markSize = 72;

  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1400),
  )..repeat();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // The mark sits at the exact centre of the screen — the same spot
    // the native launch screens and web splash draw it — so nothing
    // jumps when Flutter takes over. Text + progress hang below it.
    return Directionality(
      textDirection: TextDirection.ltr,
      child: ColoredBox(
        color: ArlColors.cream,
        child: SizedBox.expand(
          child: Stack(
            children: [
              Center(
                child: Semantics(
                  label: 'Growize',
                  child: Image.asset(
                    'assets/images/splash_mark.png',
                    width: _markSize,
                    height: _markSize,
                    filterQuality: FilterQuality.medium,
                    gaplessPlayback: true,
                  ),
                ),
              ),
              Align(
                alignment: Alignment.center,
                child: Padding(
                  // Push the block below the centred mark.
                  padding: const EdgeInsets.only(top: _markSize + 118),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Text(
                        'growize',
                        style: TextStyle(
                          fontFamily: 'Inter',
                          fontSize: 24,
                          fontWeight: FontWeight.w700,
                          letterSpacing: -0.3,
                          color: ArlColors.primary,
                          decoration: TextDecoration.none,
                        ),
                      ),
                      const SizedBox(height: 4),
                      const Text(
                        'INVESTOR PORTAL',
                        style: TextStyle(
                          fontFamily: 'Inter',
                          fontSize: 10.5,
                          fontWeight: FontWeight.w600,
                          letterSpacing: 2.2,
                          color: ArlColors.muted,
                          decoration: TextDecoration.none,
                        ),
                      ),
                      const SizedBox(height: 28),
                      _ProgressBar(animation: _c),
                    ],
                  ),
                ),
              ),
              const Positioned(
                left: 0,
                right: 0,
                bottom: 28,
                child: Text(
                  'by Agri Research Labs',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontFamily: 'Inter',
                    fontSize: 11,
                    fontWeight: FontWeight.w500,
                    color: ArlColors.muted,
                    decoration: TextDecoration.none,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 120 x 3 track with a gold segment sliding across — indeterminate,
/// calm, and cheap to paint.
class _ProgressBar extends StatelessWidget {
  final Animation<double> animation;
  const _ProgressBar({required this.animation});

  static const double _w = 120;
  static const double _seg = 44;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(2),
      child: SizedBox(
        width: _w,
        height: 3,
        child: ColoredBox(
          color: ArlColors.sand,
          child: AnimatedBuilder(
            animation: animation,
            builder: (context, _) {
              final t = Curves.easeInOut.transform(animation.value);
              final left = -_seg + (_w + _seg) * t;
              return Stack(
                children: [
                  Positioned(
                    left: left,
                    top: 0,
                    bottom: 0,
                    width: _seg,
                    child: const DecoratedBox(
                      decoration: BoxDecoration(
                        color: ArlColors.gold,
                        borderRadius: BorderRadius.all(Radius.circular(2)),
                      ),
                    ),
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}
