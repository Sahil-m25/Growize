import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:arl_app/core/theme/arl_colors.dart';
import 'package:arl_app/features/onboarding/tour_controller.dart';

/// In-app tour overlay — paints a translucent scrim with a cutout around
/// the current step's target widget, a curved arrow pointing at the
/// cutout, and a small label bubble describing what the target does.
///
/// The overlay sits at the top of the [MainScaffold] Stack so it covers
/// every shell route. It reads the step list from [tourController] and
/// re-renders whenever the current step or the route changes.
///
/// Geometry is fully dynamic:
///   * A [Ticker] re-measures the target's [RenderBox] every frame, so
///     scroll, header-collapse, resize, rotate, or any layout reflow
///     immediately updates the cutout and arrow.
///   * [WidgetsBindingObserver.didChangeMetrics] forces a rebuild on
///     viewport changes (window resize on web, device rotate on mobile).
///   * The bubble is measured via a [GlobalKey] on its outer container,
///     then re-positioned on the next frame using the actual rendered
///     size — no "estimated 170px height" drift.
///   * The bubble's side is auto-flipped: preferred first, but if it
///     doesn't fit we pick whichever side has the most clearance. The
///     final rect is always clamped inside the safe area.
///   * Arrow path is a quadratic Bézier with control point perpendicular
///     to the bubble→target line at midpoint, magnitude 0.30 × line length,
///     biased toward the target's centre so the curve always wraps
///     gracefully around the cutout.
///   * If the target widget lives inside a [Scrollable] but is off-screen,
///     [Scrollable.ensureVisible] pulls it into view before measuring.
///     Targets that fail to resolve (not yet built, on a different route
///     that the user just navigated away from) trigger a soft retry on
///     the next post-frame callback; if still unresolved the step renders
///     a centered bubble rather than locking up the tour.
class TourArrowOverlay extends ConsumerStatefulWidget {
  const TourArrowOverlay({super.key});

  @override
  ConsumerState<TourArrowOverlay> createState() => _TourArrowOverlayState();
}

class _TourArrowOverlayState extends ConsumerState<TourArrowOverlay>
    with WidgetsBindingObserver, SingleTickerProviderStateMixin {
  /// Drives per-frame re-measure of the target's RenderBox.
  late final Ticker _ticker;

  /// Rect last used for painting. Compared against the live rect each
  /// frame to decide whether to schedule a rebuild.
  Rect? _paintedTargetRect;

  /// Measured intrinsic bubble size. Captured frame-by-frame so the
  /// bubble re-positions accurately when its content changes (next/back
  /// step has different body length).
  Size? _measuredBubbleSize;

  /// Step we last issued navigation for. Stops re-navigating on every
  /// rebuild while still allowing nav when the index actually moves.
  int _lastNavigatedStep = -1;

  /// Step we last attempted to scroll into view. Avoids re-scrolling on
  /// every frame.
  int _lastScrolledStep = -1;

  /// Step index that the retry counter applies to. Reset every time the
  /// active step changes so each step gets a fresh budget.
  int _currentRetryStep = -1;

  /// How many times we've polled the active step's target before giving
  /// up. After [_maxRetriesPerStep] failed polls we treat the target as
  /// "not in the tree" and advance, rather than freezing the tour on a
  /// step that points at empty space.
  int _retriesForCurrentStep = 0;

  /// Number of contiguous steps that have been auto-skipped because
  /// their target wasn't in the tree. If this passes
  /// [_maxConsecutiveSkips] we end the tour gracefully — the user
  /// shouldn't be marched through a no-target spiral.
  int _consecutiveSkippedSteps = 0;

  /// Two post-frame polls is enough for almost every conditionally
  /// rendered target: the first frame mounts the route, the second
  /// frame mounts late-arriving children (e.g. async portfolio data).
  /// If the key still isn't attached we assume the target genuinely
  /// isn't going to appear (e.g. zero-project user on the projects
  /// grid step) and skip.
  static const int _maxRetriesPerStep = 2;

  /// More than this many consecutive skipped steps and we bail out of
  /// the tour rather than walking the user past empty space repeatedly.
  static const int _maxConsecutiveSkips = 3;

  /// Key attached to the bubble's outer container so we can read its
  /// rendered size and re-position the bubble + arrow.
  final GlobalKey _bubbleKey = GlobalKey(debugLabel: 'tour.bubble.measure');

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _ticker = createTicker(_onTick)..start();
    WidgetsBinding.instance.addPostFrameCallback((_) => _settle());
  }

  @override
  void dispose() {
    _ticker.dispose();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  /// Window resize on web, device rotate on mobile — both reach us via
  /// [didChangeMetrics]. Trigger a rebuild so [MediaQuery] + target rect
  /// both refresh in the same frame.
  @override
  void didChangeMetrics() {
    if (mounted) setState(() {});
  }

  /// Per-frame poll. Cheap (≈two RenderBox lookups + a few diffs). Only
  /// calls [setState] when something the painter cares about actually
  /// moved, so the rebuild cost is paid only when geometry changes.
  void _onTick(Duration _) {
    if (!mounted) return;
    final stepIndex = ref.read(tourStepProvider);
    final steps = tourSteps();
    if (stepIndex < 0 || stepIndex >= steps.length) return;

    final step = steps[stepIndex];
    final rect = _targetRect(step);
    final size = _measureBubble();
    final rectMoved = !_rectsClose(_paintedTargetRect, rect);
    final sizeMoved = !_sizesClose(_measuredBubbleSize, size);
    if (rectMoved || sizeMoved) {
      setState(() {
        _measuredBubbleSize = size;
      });
    }
  }

  static bool _rectsClose(Rect? a, Rect? b) {
    if (a == null && b == null) return true;
    if (a == null || b == null) return false;
    return (a.left - b.left).abs() < 0.5 &&
        (a.top - b.top).abs() < 0.5 &&
        (a.right - b.right).abs() < 0.5 &&
        (a.bottom - b.bottom).abs() < 0.5;
  }

  static bool _sizesClose(Size? a, Size? b) {
    if (a == null && b == null) return true;
    if (a == null || b == null) return false;
    return (a.width - b.width).abs() < 0.5 &&
        (a.height - b.height).abs() < 0.5;
  }

  Size? _measureBubble() {
    final ctx = _bubbleKey.currentContext;
    if (ctx == null) return null;
    final ro = ctx.findRenderObject();
    if (ro is! RenderBox || !ro.hasSize) return null;
    return ro.size;
  }

  /// Compute the rect of the step's target key in the overlay's own
  /// local coordinate space. Returns null when the key isn't mounted
  /// yet or when this step has no target (centered bubble).
  ///
  /// Critical: `RenderBox.localToGlobal(Offset.zero)` returns
  /// SCREEN-global coordinates, but our painter draws in its own
  /// local space. If the overlay sits below an AppBar, painting at the
  /// raw global y would land lower than where the target actually
  /// appears — the cutout would point at the wrong row. Passing the
  /// overlay's own RenderBox as `ancestor` translates the rect into
  /// the painter's coord system, so cutout + arrow always line up.
  Rect? _targetRect(TourStep step) {
    final key = step.targetKey;
    if (key == null) return null;
    final ctx = key.currentContext;
    if (ctx == null) return null;
    final ro = ctx.findRenderObject();
    if (ro is! RenderBox || !ro.hasSize) return null;
    // Resolve the overlay's own RenderBox via this State's context so
    // we can convert to overlay-local. If we can't (very first frame
    // before mount), fall back to global — the next frame's tick will
    // correct it.
    final overlayRO = context.findRenderObject();
    if (overlayRO is RenderBox && overlayRO.hasSize && overlayRO.attached) {
      final topLeft = ro.localToGlobal(Offset.zero, ancestor: overlayRO);
      return topLeft & ro.size;
    }
    final topLeft = ro.localToGlobal(Offset.zero);
    return topLeft & ro.size;
  }

  /// Ensure the active route matches the step. If not, navigate. Then
  /// (one frame later) if the target lives in a scrollable, pull it into
  /// view so the overlay points at something the user can actually see.
  ///
  /// Auto-skip semantics: tour steps reference widgets via [GlobalKey].
  /// Several of those widgets are conditionally rendered — e.g. the
  /// projects grid is built only when the investor actually has
  /// projects, the portfolio cluster only renders once the first
  /// portfolio fetch lands. When a step's target isn't in the tree
  /// after [_maxRetriesPerStep] settle passes we advance to the next
  /// step instead of pointing at empty space. If more than
  /// [_maxConsecutiveSkips] steps in a row get skipped (e.g. a brand
  /// new investor with zero data) we jump to the closer step so the
  /// tour ends on a friendly "you're all set" card rather than a
  /// silent run of empty frames.
  Future<void> _settle() async {
    if (!mounted) return;
    final stepIndex = ref.read(tourStepProvider);
    final steps = tourSteps();
    if (stepIndex < 0 || stepIndex >= steps.length) return;

    // Reset the per-step retry budget when the active step changes.
    // This is the only spot that touches _currentRetryStep, so the
    // counter only increments while we're stuck on the same step.
    if (_currentRetryStep != stepIndex) {
      _currentRetryStep = stepIndex;
      _retriesForCurrentStep = 0;
    }

    final step = steps[stepIndex];
    final goState = GoRouterState.of(context);
    final currentLocation = goState.matchedLocation;

    if (currentLocation != step.route && _lastNavigatedStep != stepIndex) {
      _lastNavigatedStep = stepIndex;
      if (step.pushRoute) {
        context.push(step.route);
      } else {
        context.go(step.route);
      }
      // Let the new screen mount, then settle again so the rect resolves
      // before we paint the cutout.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _settle();
      });
      return;
    }

    // We're on the right route — try to scroll the target into view
    // (no-op if it's already visible or isn't inside a Scrollable).
    if (_lastScrolledStep != stepIndex) {
      final key = step.targetKey;
      if (key != null) {
        final ctx = key.currentContext;
        if (ctx != null) {
          _lastScrolledStep = stepIndex;
          try {
            await Scrollable.ensureVisible(
              ctx,
              duration: const Duration(milliseconds: 240),
              alignment: 0.3,
              curve: Curves.easeOutCubic,
            );
          } catch (_) {
            // Target isn't inside a Scrollable — perfectly fine.
          }
        }
      }
    }

    if (!mounted) return;

    // Auto-skip: step expects a target but its GlobalKey isn't attached.
    // Targets backed by async data (portfolio cluster) or by collection
    // size (projects grid is omitted when the user has zero projects)
    // can legitimately be absent. Give the tree a couple of frames to
    // mount before deciding it's missing — then skip rather than freeze.
    if (step.targetKey != null && _targetRect(step) == null) {
      if (_retriesForCurrentStep < _maxRetriesPerStep) {
        _retriesForCurrentStep += 1;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) _settle();
        });
        return;
      }
      debugPrint(
        '[tour] skipped step ${stepIndex + 1} (${step.title}) — target '
        '${step.targetKey} not in tree',
      );
      _consecutiveSkippedSteps += 1;
      if (_consecutiveSkippedSteps > _maxConsecutiveSkips) {
        // Jump to the closer step (always centered, no target) so the
        // tour ends on a "you're all set" card instead of a no-target
        // spiral. Reset the skip counter so a replay starts clean.
        _consecutiveSkippedSteps = 0;
        ref.read(tourStepProvider.notifier).state = steps.length - 1;
      } else {
        await nextTourStep(ref);
      }
      return;
    }

    // Successful resolve (or intentionally targetless step) — clear the
    // consecutive-skip streak so a single missing target doesn't shrink
    // the budget for unrelated future steps.
    _consecutiveSkippedSteps = 0;
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    // Step changed → reset measurement caches and re-settle.
    ref.listen<int>(tourStepProvider, (prev, next) {
      if (prev == next) return;
      _measuredBubbleSize = null;
      _paintedTargetRect = null;
      _lastScrolledStep = -1;
      WidgetsBinding.instance.addPostFrameCallback((_) => _settle());
    });

    final stepIndex = ref.watch(tourStepProvider);
    final steps = tourSteps();
    if (stepIndex < 0 || stepIndex >= steps.length) {
      return const SizedBox.shrink();
    }
    final step = steps[stepIndex];
    final isLast = stepIndex == steps.length - 1;

    return LayoutBuilder(
      builder: (context, constraints) {
        final mq = MediaQuery.of(context);
        // Always trust the LayoutBuilder constraints for the overlay's
        // own painting size. They're the actual paint box and they
        // resize the instant the window resizes / device rotates.
        final paintSize = Size(constraints.maxWidth, constraints.maxHeight);
        // Use MediaQuery.size as the "viewport" for clamping. On web in
        // a narrow Chrome window these match; the safe-area padding
        // ensures iOS notch + Android nav bar stay clear on mobile.
        final screen = mq.size;
        final safe = mq.padding;

        // Fresh measurement inside build so we always paint against
        // current layout — covers route mount, scroll, header-collapse,
        // and the first frame after a step change.
        final liveRect = _targetRect(step);
        _paintedTargetRect = liveRect;

        // If the step has a target but the key isn't attached yet,
        // schedule a retry next frame. The ticker also covers this, but
        // an immediate post-frame nudge keeps the first frame snappy.
        if (step.targetKey != null && liveRect == null) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (!mounted) return;
            if (_targetRect(step) != null) setState(() {});
          });
        }

        final cutout = liveRect == null
            ? null
            : _inflate(liveRect, step.cutoutPadding);

        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () => nextTourStep(ref),
          child: Stack(
            fit: StackFit.expand,
            children: [
              CustomPaint(
                size: paintSize,
                painter: _ScrimPainter(cutout: cutout),
              ),
              if (cutout != null && step.arrowSide != TourArrowSide.center)
                _ArrowAndBubble(
                  step: step,
                  targetRect: cutout,
                  stepIndex: stepIndex,
                  totalSteps: steps.length,
                  isLast: isLast,
                  screen: screen,
                  safeArea: safe,
                  bubbleKey: _bubbleKey,
                  measuredBubbleSize: _measuredBubbleSize,
                )
              else
                _CenteredBubble(
                  step: step,
                  stepIndex: stepIndex,
                  totalSteps: steps.length,
                  isLast: isLast,
                  bubbleKey: cutout == null ? _bubbleKey : null,
                ),
              Positioned(
                bottom: 24 + safe.bottom,
                right: 20,
                child: _SkipLink(onTap: () => dismissTour(ref)),
              ),
            ],
          ),
        );
      },
    );
  }

  static Rect _inflate(Rect r, double pad) => Rect.fromLTRB(
        r.left - pad,
        r.top - pad,
        r.right + pad,
        r.bottom + pad,
      );
}

// ── Painter ────────────────────────────────────────────────────────────

/// Paints the dark scrim with a rounded-rect cutout for the target.
class _ScrimPainter extends CustomPainter {
  final Rect? cutout;
  static const double _radius = 14;

  _ScrimPainter({required this.cutout});

  @override
  void paint(Canvas canvas, Size size) {
    final scrim = Paint()..color = const Color(0xCC0F1A15); // charcoal/80
    final full = Path()..addRect(Offset.zero & size);
    if (cutout == null) {
      canvas.drawPath(full, scrim);
      return;
    }
    final hole = Path()
      ..addRRect(
          RRect.fromRectAndRadius(cutout!, const Radius.circular(_radius)));
    final combined = Path.combine(PathOperation.difference, full, hole);
    canvas.drawPath(combined, scrim);
    // Soft gold ring around the cutout — draws the eye without being loud.
    final ring = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2
      ..color = ArlColors.gold.withOpacity(0.85);
    canvas.drawRRect(
      RRect.fromRectAndRadius(cutout!, const Radius.circular(_radius)),
      ring,
    );
  }

  @override
  bool shouldRepaint(covariant _ScrimPainter old) => old.cutout != cutout;
}

// ── Arrow + bubble for targeted steps ──────────────────────────────────

class _ArrowAndBubble extends ConsumerWidget {
  final TourStep step;
  final Rect targetRect;
  final int stepIndex;
  final int totalSteps;
  final bool isLast;
  final Size screen;
  final EdgeInsets safeArea;
  final GlobalKey bubbleKey;
  final Size? measuredBubbleSize;

  const _ArrowAndBubble({
    required this.step,
    required this.targetRect,
    required this.stepIndex,
    required this.totalSteps,
    required this.isLast,
    required this.screen,
    required this.safeArea,
    required this.bubbleKey,
    required this.measuredBubbleSize,
  });

  /// Gap between the cutout edge and the bubble's nearest edge — also
  /// determines roughly how long the arrow body is.
  static const double _gap = 28;

  /// Generic safe-area pad on top of MediaQuery.padding.
  static const double _edgePad = 16;

  /// Vertical clearance reserved at the bottom for the Skip pill.
  static const double _skipReserve = 68;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Max width: 320 on tablet/web, full minus 32 on phone.
    final maxBubbleW = math.min(320.0, screen.width - 32);
    // Until we've measured a real bubble, fall back to a reasonable
    // estimate. The ticker swaps this for the real size one frame later.
    final estimate = Size(maxBubbleW, 168);
    final bubbleSize = measuredBubbleSize ?? estimate;

    final side = _resolveSide(
      step.arrowSide,
      targetRect,
      bubbleSize,
      screen,
      safeArea,
    );

    final bubbleRect = _positionBubble(
      side: side,
      targetRect: targetRect,
      bubbleSize: bubbleSize,
      screen: screen,
      safe: safeArea,
    );

    final anchor = _anchorOnSide(side, targetRect);
    final arrowOrigin = _bubbleArrowOrigin(bubbleRect, side, anchor);

    return Stack(
      children: [
        IgnorePointer(
          child: CustomPaint(
            size: screen,
            painter: _ArrowPainter(
              from: arrowOrigin,
              to: anchor,
              targetCenter: targetRect.center,
              side: side,
            ),
          ),
        ),
        Positioned(
          left: bubbleRect.left,
          top: bubbleRect.top,
          child: _BubbleCard(
            measureKey: bubbleKey,
            step: step,
            stepIndex: stepIndex,
            totalSteps: totalSteps,
            isLast: isLast,
            width: maxBubbleW,
            onNext: () => nextTourStep(ref),
            onBack: stepIndex == 0 ? null : () => previousTourStep(ref),
          ),
        ),
      ],
    );
  }

  /// Pick the side with enough room for the bubble. Preferred wins if it
  /// fits; otherwise we pick the side with the most clearance among the
  /// sides that fit; otherwise (cramped target) the side with the most
  /// raw space — the clamp in [_positionBubble] keeps the bubble inside
  /// the viewport regardless.
  TourArrowSide _resolveSide(
    TourArrowSide preferred,
    Rect target,
    Size bubble,
    Size screen,
    EdgeInsets safe,
  ) {
    if (preferred == TourArrowSide.center) return preferred;

    final spaceAbove = target.top - safe.top - _edgePad;
    final spaceBelow =
        screen.height - target.bottom - safe.bottom - _edgePad - _skipReserve;
    final spaceLeft = target.left - safe.left - _edgePad;
    final spaceRight = screen.width - target.right - safe.right - _edgePad;

    bool fits(TourArrowSide s) {
      switch (s) {
        case TourArrowSide.above:
          return spaceAbove >= bubble.height + _gap;
        case TourArrowSide.below:
          return spaceBelow >= bubble.height + _gap;
        case TourArrowSide.left:
          return spaceLeft >= bubble.width + _gap;
        case TourArrowSide.right:
          return spaceRight >= bubble.width + _gap;
        case TourArrowSide.center:
          return true;
      }
    }

    if (fits(preferred)) return preferred;

    final scores = <TourArrowSide, double>{
      TourArrowSide.above: spaceAbove,
      TourArrowSide.below: spaceBelow,
      TourArrowSide.left: spaceLeft,
      TourArrowSide.right: spaceRight,
    };
    MapEntry<TourArrowSide, double>? best;
    for (final e in scores.entries) {
      if (!fits(e.key)) continue;
      if (best == null || e.value > best.value) best = e;
    }
    if (best != null) return best.key;

    // Nothing technically fits — pick the side with the most raw space.
    return scores.entries.reduce((a, b) => a.value > b.value ? a : b).key;
  }

  Offset _anchorOnSide(TourArrowSide side, Rect target) {
    switch (side) {
      case TourArrowSide.above:
        return Offset(target.center.dx, target.top);
      case TourArrowSide.below:
        return Offset(target.center.dx, target.bottom);
      case TourArrowSide.left:
        return Offset(target.left, target.center.dy);
      case TourArrowSide.right:
        return Offset(target.right, target.center.dy);
      case TourArrowSide.center:
        return target.center;
    }
  }

  Rect _positionBubble({
    required TourArrowSide side,
    required Rect targetRect,
    required Size bubbleSize,
    required Size screen,
    required EdgeInsets safe,
  }) {
    final w = bubbleSize.width;
    final h = bubbleSize.height;
    double left;
    double top;

    switch (side) {
      case TourArrowSide.above:
        top = targetRect.top - h - _gap;
        left = targetRect.center.dx - w / 2;
        break;
      case TourArrowSide.below:
        top = targetRect.bottom + _gap;
        left = targetRect.center.dx - w / 2;
        break;
      case TourArrowSide.left:
        left = targetRect.left - w - _gap;
        top = targetRect.center.dy - h / 2;
        break;
      case TourArrowSide.right:
        left = targetRect.right + _gap;
        top = targetRect.center.dy - h / 2;
        break;
      case TourArrowSide.center:
        left = (screen.width - w) / 2;
        top = (screen.height - h) / 2;
        break;
    }

    // Clamp to the safe-area-inset viewport. Reserve _skipReserve at
    // the bottom so the Skip pill never collides with the bubble.
    final minLeft = safe.left + _edgePad;
    final maxLeft =
        math.max(minLeft, screen.width - safe.right - _edgePad - w);
    final minTop = safe.top + _edgePad;
    final maxTop = math.max(
      minTop,
      screen.height - safe.bottom - _edgePad - _skipReserve - h,
    );
    left = left.clamp(minLeft, maxLeft).toDouble();
    top = top.clamp(minTop, maxTop).toDouble();

    return Rect.fromLTWH(left, top, w, h);
  }

  /// The point on the bubble's edge that the arrow leaves from. We pick
  /// the centre of the edge facing the target, but if the bubble has
  /// been shifted by the safe-area clamp we slide the origin along that
  /// edge toward the anchor so the arrow still reads as "from bubble to
  /// target", not "from random corner".
  Offset _bubbleArrowOrigin(Rect bubble, TourArrowSide side, Offset anchor) {
    const inset = 24.0;
    switch (side) {
      case TourArrowSide.above:
        final x = anchor.dx.clamp(bubble.left + inset, bubble.right - inset);
        return Offset(x.toDouble(), bubble.bottom);
      case TourArrowSide.below:
        final x = anchor.dx.clamp(bubble.left + inset, bubble.right - inset);
        return Offset(x.toDouble(), bubble.top);
      case TourArrowSide.left:
        final y = anchor.dy.clamp(bubble.top + inset, bubble.bottom - inset);
        return Offset(bubble.right, y.toDouble());
      case TourArrowSide.right:
        final y = anchor.dy.clamp(bubble.top + inset, bubble.bottom - inset);
        return Offset(bubble.left, y.toDouble());
      case TourArrowSide.center:
        return bubble.center;
    }
  }
}

class _ArrowPainter extends CustomPainter {
  final Offset from;
  final Offset to;
  final Offset targetCenter;
  final TourArrowSide side;

  _ArrowPainter({
    required this.from,
    required this.to,
    required this.targetCenter,
    required this.side,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (side == TourArrowSide.center) return; // no arrow on centered cards

    final paint = Paint()
      ..color = ArlColors.gold
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.5
      ..strokeCap = StrokeCap.round;

    final dx = to.dx - from.dx;
    final dy = to.dy - from.dy;
    final dist = math.sqrt(dx * dx + dy * dy);
    if (dist < 1) return;
    // Perpendicular to (from → to), unit length.
    final px = -dy / dist;
    final py = dx / dist;
    // Midpoint of the line.
    final midX = (from.dx + to.dx) / 2;
    final midY = (from.dy + to.dy) / 2;
    // Choose which way the curve bows: toward the target's centre — that
    // wraps the arc gracefully around the cutout regardless of side.
    final dot =
        px * (targetCenter.dx - midX) + py * (targetCenter.dy - midY);
    final sign = dot >= 0 ? 1.0 : -1.0;
    // Bow magnitude scales with line length so short arrows don't look
    // stiff and long arrows don't look like a hairpin.
    final mag = dist * 0.30;
    final cx = midX + px * mag * sign;
    final cy = midY + py * mag * sign;

    final path = Path()
      ..moveTo(from.dx, from.dy)
      ..quadraticBezierTo(cx, cy, to.dx, to.dy);
    canvas.drawPath(path, paint);

    // Filled-triangle arrowhead — tip at `to`, base perpendicular to the
    // Bézier tangent at t=1 (parallel to (to - control)).
    final tdx = to.dx - cx;
    final tdy = to.dy - cy;
    final tlen = math.sqrt(tdx * tdx + tdy * tdy);
    if (tlen < 0.1) return;
    final ux = tdx / tlen;
    final uy = tdy / tlen;
    final hpx = -uy;
    final hpy = ux;
    const headSize = 11.0;
    final tip = to;
    final base = Offset(to.dx - ux * headSize, to.dy - uy * headSize);
    final left = Offset(
      base.dx + hpx * (headSize * 0.55),
      base.dy + hpy * (headSize * 0.55),
    );
    final right = Offset(
      base.dx - hpx * (headSize * 0.55),
      base.dy - hpy * (headSize * 0.55),
    );
    final head = Path()
      ..moveTo(tip.dx, tip.dy)
      ..lineTo(left.dx, left.dy)
      ..lineTo(right.dx, right.dy)
      ..close();
    canvas.drawPath(head, Paint()..color = ArlColors.gold);
  }

  @override
  bool shouldRepaint(covariant _ArrowPainter old) =>
      old.from != from ||
      old.to != to ||
      old.targetCenter != targetCenter ||
      old.side != side;
}

// ── Bubble cards ──────────────────────────────────────────────────────

class _BubbleCard extends StatelessWidget {
  final TourStep step;
  final int stepIndex;
  final int totalSteps;
  final bool isLast;
  final double width;
  final VoidCallback onNext;
  final VoidCallback? onBack;

  /// Key on the outer (non-animated) wrapper so the parent can measure
  /// the bubble's rendered size. Kept *outside* AnimatedSwitcher so the
  /// switcher's child-key churn never invalidates this measurement key.
  final Key? measureKey;

  const _BubbleCard({
    required this.step,
    required this.stepIndex,
    required this.totalSteps,
    required this.isLast,
    required this.width,
    required this.onNext,
    this.onBack,
    this.measureKey,
  });

  @override
  Widget build(BuildContext context) {
    // Stop the parent's tap-to-advance from firing when the user is
    // interacting with the bubble's controls.
    return KeyedSubtree(
      key: measureKey,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () {}, // absorb taps on the card area itself
        child: AnimatedSwitcher(
          duration: const Duration(milliseconds: 220),
          switchInCurve: Curves.easeOutCubic,
          switchOutCurve: Curves.easeInCubic,
          transitionBuilder: (child, anim) => FadeTransition(
            opacity: anim,
            child: SlideTransition(
              position: Tween<Offset>(
                begin: const Offset(0, 0.05),
                end: Offset.zero,
              ).animate(anim),
              child: child,
            ),
          ),
          child: Container(
            key: ValueKey<int>(stepIndex),
            width: width,
            padding: const EdgeInsets.fromLTRB(18, 16, 18, 14),
            decoration: BoxDecoration(
              color: ArlColors.cream,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: ArlColors.primary, width: 1.5),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.18),
                  blurRadius: 22,
                  offset: const Offset(0, 8),
                ),
              ],
            ),
            child: IntrinsicHeight(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Gold accent rail on the left edge.
                  Container(
                    width: 3,
                    margin: const EdgeInsets.only(right: 12),
                    decoration: BoxDecoration(
                      color: ArlColors.gold,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        // Step counter pill at the top.
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(
                            color: ArlColors.primary.withOpacity(0.08),
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Text(
                            'STEP ${stepIndex + 1} OF $totalSteps',
                            style: const TextStyle(
                              color: ArlColors.primary,
                              fontSize: 10,
                              fontWeight: FontWeight.w700,
                              letterSpacing: 1.0,
                            ),
                          ),
                        ),
                        const SizedBox(height: 10),
                        Text(
                          step.title,
                          style: const TextStyle(
                            color: ArlColors.charcoal,
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                            height: 1.2,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          step.body,
                          style: const TextStyle(
                            color: ArlColors.charcoal,
                            fontSize: 12.5,
                            height: 1.45,
                          ),
                        ),
                        const SizedBox(height: 14),
                        Row(
                          children: [
                            if (onBack != null)
                              _GhostButton(label: 'Back', onTap: onBack!),
                            const Spacer(),
                            _PrimaryButton(
                              label: isLast ? 'Done' : 'Next',
                              onTap: onNext,
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Used for steps without a target — opener, closer, and the few
/// commentary beats that aren't tied to a specific widget.
class _CenteredBubble extends ConsumerWidget {
  final TourStep step;
  final int stepIndex;
  final int totalSteps;
  final bool isLast;
  final Key? bubbleKey;

  const _CenteredBubble({
    required this.step,
    required this.stepIndex,
    required this.totalSteps,
    required this.isLast,
    this.bubbleKey,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final width = math.min(360.0, MediaQuery.of(context).size.width - 40);
    return Center(
      child: _BubbleCard(
        measureKey: bubbleKey,
        step: step,
        stepIndex: stepIndex,
        totalSteps: totalSteps,
        isLast: isLast,
        width: width,
        onNext: () => nextTourStep(ref),
        onBack: stepIndex == 0 ? null : () => previousTourStep(ref),
      ),
    );
  }
}

// ── Buttons ────────────────────────────────────────────────────────────

class _PrimaryButton extends StatelessWidget {
  final String label;
  final VoidCallback onTap;
  const _PrimaryButton({required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: ArlColors.primary,
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
          child: Text(
            label,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 13,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.3,
            ),
          ),
        ),
      ),
    );
  }
}

class _GhostButton extends StatelessWidget {
  final String label;
  final VoidCallback onTap;
  const _GhostButton({required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Material(
      type: MaterialType.transparency,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          child: Text(
            label,
            style: const TextStyle(
              color: ArlColors.muted,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ),
    );
  }
}

class _SkipLink extends StatelessWidget {
  final VoidCallback onTap;
  const _SkipLink({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          decoration: BoxDecoration(
            color: Colors.black.withOpacity(0.35),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: Colors.white.withOpacity(0.25),
            ),
          ),
          child: const Text(
            'Skip tour',
            style: TextStyle(
              color: Colors.white,
              fontSize: 11,
              fontWeight: FontWeight.w600,
              letterSpacing: 0.4,
            ),
          ),
        ),
      ),
    );
  }
}
