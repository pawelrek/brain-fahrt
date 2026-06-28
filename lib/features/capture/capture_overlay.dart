/// Sheet recording overlay — slides up from the bottom, shows the live
/// waveform while listening, then transitions through processing states to the
/// filed result card, then pops itself once the pipeline returns to Idle.
library;

import 'dart:math' show pi, cos, sin, max;

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/design/colors.dart';
import '../../core/design/dimens.dart';
import '../../core/design/typography.dart';
import '../../core/log/app_log.dart';
import '../../core/widgets/dot_icon.dart';
import '../../core/widgets/type_glyph.dart';
import '../../core/widgets/waveform.dart';
import '../../data/providers.dart';
import '../../pipeline/capture_pipeline.dart' show kMaxRecordDuration;
import 'capture_controller.dart';
import 'capture_state.dart';

// ── Public entry point ────────────────────────────────────────────────────────

/// Push [CaptureOverlay] as a transparent, zero-transition route.
Future<void> showCaptureOverlay(BuildContext context) =>
    Navigator.of(context).push<void>(
      PageRouteBuilder(
        opaque: false,
        barrierColor: const Color(0x00000000),
        transitionDuration: Duration.zero,
        reverseTransitionDuration: Duration.zero,
        pageBuilder: (_, _, _) => const CaptureOverlay(),
      ),
    );

// ── Overlay root ──────────────────────────────────────────────────────────────

/// The recording / processing / result sheet overlay.
class CaptureOverlay extends ConsumerStatefulWidget {
  const CaptureOverlay({super.key});

  @override
  ConsumerState<CaptureOverlay> createState() => _CaptureOverlayState();
}

class _CaptureOverlayState extends ConsumerState<CaptureOverlay>
    with SingleTickerProviderStateMixin {
  // Sheet slide-in controller.
  late final AnimationController _slideCtrl;
  late final Animation<Offset> _slideAnim;

  // State-machine tracking.
  bool _started = false; // true once we've seen any non-Idle state
  bool _popped = false; // guard — pop at most once
  double _dragDy = 0; // swipe-down-to-cancel drag offset

  @override
  void initState() {
    super.initState();

    _slideCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 340),
    );
    _slideAnim = Tween<Offset>(
      begin: const Offset(0, 1),
      end: Offset.zero,
    ).animate(CurvedAnimation(
      parent: _slideCtrl,
      curve: const Cubic(0.2, 0.8, 0.25, 1),
    ));

    // Kick off the pipeline after the first frame.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(captureControllerProvider.notifier).start();
    });
  }

  @override
  void dispose() {
    _slideCtrl.dispose();
    super.dispose();
  }

  void _maybeStartSlide(bool reducedMotion) {
    if (!reducedMotion && _slideCtrl.status == AnimationStatus.dismissed) {
      _slideCtrl.forward();
    }
  }

  @override
  Widget build(BuildContext context) {
    final reducedMotion = MediaQuery.of(context).disableAnimations;
    final state = ref.watch(captureControllerProvider);
    final ctrl = ref.read(captureControllerProvider.notifier);

    // Track started / pop-on-idle.
    ref.listen<CaptureState>(captureControllerProvider, (prev, next) {
      if (next is! CaptureIdle) {
        if (!_started) {
          _started = true;
          _maybeStartSlide(reducedMotion);
        }
      } else if (_started && !_popped) {
        _popped = true;
        // Defer the pop out of the listener/build phase: popping synchronously
        // here mutates the dashboard's masonry mid-layout, which throws
        // viewport.dart '!_doingMountOrUpdate' (the crash seen on-device).
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) Navigator.maybePop(context);
        });
      }
    });

    // Scrim tap — only cancel while actively listening.
    final canTapCancel = state is CaptureListening;

    Widget sheet = _Sheet(
      state: state,
      ctrl: ctrl,
      reducedMotion: reducedMotion,
    );

    if (!reducedMotion) {
      sheet = SlideTransition(position: _slideAnim, child: sheet);
    }

    // Swipe the sheet down to cancel: the sheet follows the finger; releasing
    // past a threshold (or a downward fling) cancels, else it snaps back.
    final canSwipeCancel = state is! CaptureIdle && state is! CaptureResult;
    if (canSwipeCancel) {
      sheet = GestureDetector(
        onVerticalDragUpdate: (d) {
          setState(() =>
              _dragDy = (_dragDy + (d.primaryDelta ?? 0)).clamp(0.0, 400.0));
        },
        onVerticalDragEnd: (d) {
          if (_dragDy > 90 || (d.primaryVelocity ?? 0) > 700) {
            AppLog.instance.log('ui', 'capture cancelled (swipe down)');
            ctrl.cancel();
          } else {
            setState(() => _dragDy = 0);
          }
        },
        child: Transform.translate(offset: Offset(0, _dragDy), child: sheet),
      );
    }

    // Intercept Android back gesture: allow pop only when Idle or Listening;
    // during processing states cancel the pipeline first.
    // Only Idle may pop directly. While Listening/processing, intercept back,
    // cancel the pipeline (stops the mic + LLM), and let the Idle transition pop
    // — otherwise back could leave capture running off-screen.
    final canPop = state is CaptureIdle;

    return PopScope(
      canPop: canPop,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop) {
          AppLog.instance.log('ui', 'capture cancelled (back gesture)');
          ctrl.cancel();
        }
      },
      child: Stack(
        children: [
          // Scrim
          Positioned.fill(
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: canTapCancel
                  ? () {
                      AppLog.instance.log('ui', 'capture cancelled (scrim)');
                      ctrl.cancel();
                    }
                  : null,
              child: ColoredBox(color: DotColors.scrim),
            ),
          ),
          // Sheet
          Align(
            alignment: Alignment.bottomCenter,
            child: sheet,
          ),
        ],
      ),
    );
  }
}

// ── Sheet container ───────────────────────────────────────────────────────────

class _Sheet extends StatelessWidget {
  const _Sheet({
    required this.state,
    required this.ctrl,
    required this.reducedMotion,
  });

  final CaptureState state;
  final CaptureController ctrl;
  final bool reducedMotion;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      decoration: const BoxDecoration(
        color: DotColors.surface,
        borderRadius: BorderRadius.only(
          topLeft: Radius.circular(DotRadii.sheetTop),
          topRight: Radius.circular(DotRadii.sheetTop),
        ),
        boxShadow: DotShadow.sheet,
      ),
      padding: const EdgeInsets.fromLTRB(22, 14, 22, 30),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Grabber pill
          Container(
            width: 40,
            height: 5,
            margin: const EdgeInsets.only(bottom: 6),
            decoration: BoxDecoration(
              color: DotColors.grabber,
              borderRadius: BorderRadius.circular(5),
            ),
          ),
          _StateBody(
            state: state,
            ctrl: ctrl,
            reducedMotion: reducedMotion,
          ),
        ],
      ),
    );
  }
}

// ── State dispatcher ──────────────────────────────────────────────────────────

class _StateBody extends ConsumerWidget {
  const _StateBody({
    required this.state,
    required this.ctrl,
    required this.reducedMotion,
  });

  final CaptureState state;
  final CaptureController ctrl;
  final bool reducedMotion;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final child = switch (state) {
      CaptureListening(:final partial, :final elapsed) => _ListeningBody(
          key: const ValueKey('listening'),
          partial: partial,
          elapsed: elapsed,
          ctrl: ctrl,
        ),
      // All processing stages share ONE view (constant key) so the rotating
      // arrow never restarts between them — only its label cross-fades.
      CaptureHeard() ||
      CaptureTranscribing() ||
      CaptureLoadingLlm() ||
      CaptureSorting() =>
        _ProcessingView(
          key: const ValueKey('processing'),
          label: _processingLabel(state),
          reducedMotion: reducedMotion,
        ),
      CaptureResult() => GestureDetector(
          key: const ValueKey('result'),
          behavior: HitTestBehavior.opaque,
          onTap: () =>
              ref.read(captureControllerProvider.notifier).commitNow(),
          child: _ResultBody(
            result: state as CaptureResult,
            reducedMotion: reducedMotion,
          ),
        ),
      CaptureIdle() => const SizedBox.shrink(
          key: ValueKey('idle'),
        ),
    };

    return AnimatedSwitcher(
      duration: reducedMotion
          ? Duration.zero
          : const Duration(milliseconds: 280),
      switchInCurve: Curves.easeOutCubic,
      switchOutCurve: Curves.easeIn,
      transitionBuilder: reducedMotion
          ? AnimatedSwitcher.defaultTransitionBuilder
          : (widget, animation) {
              // Outgoing child: fade only (no slide — avoids layout jitter).
              // Incoming child: fade + subtle upward slide.
              final isIncoming = animation.status == AnimationStatus.forward ||
                  animation.status == AnimationStatus.completed;
              if (isIncoming) {
                final slide = Tween<Offset>(
                  begin: const Offset(0, 0.04),
                  end: Offset.zero,
                ).animate(animation);
                return FadeTransition(
                  opacity: animation,
                  child: SlideTransition(position: slide, child: widget),
                );
              }
              return FadeTransition(opacity: animation, child: widget);
            },
      child: child,
    );
  }

  static String _processingLabel(CaptureState s) => switch (s) {
        CaptureHeard() => 'Got it',
        CaptureTranscribing() => 'Transcribing…',
        CaptureLoadingLlm() => 'Warming up the model…',
        CaptureSorting() => 'Finding the right list…',
        _ => '',
      };
}

// ── Listening body ────────────────────────────────────────────────────────────

class _ListeningBody extends StatelessWidget {
  const _ListeningBody({
    super.key,
    required this.partial,
    required this.elapsed,
    required this.ctrl,
  });

  final String partial;
  final Duration elapsed;
  final CaptureController ctrl;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const SizedBox(height: 8),
        // Row: rec dot · "Recording" · separator · timer [ · auto-stop Ns ]
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            _PulsingDot(size: 9, color: brandRed),
            const SizedBox(width: 10),
            Text(
              'Recording',
              style: DotText.font(
                size: 13.5,
                weight: FontWeight.w700,
                color: DotColors.ink,
                letterSpacing: 0.2,
              ),
            ),
            const SizedBox(width: 8),
            Text(
              '·',
              style: DotText.font(
                size: 13.5,
                color: DotColors.dotSep,
              ),
            ),
            const SizedBox(width: 8),
            Text(
              _fmtElapsed(elapsed),
              style: DotText.timer,
            ),
            // Countdown: only show when ≤ 5 s remain before the auto-stop cap.
            Builder(builder: (context) {
              final remaining = kMaxRecordDuration - elapsed;
              if (remaining > const Duration(seconds: 5)) {
                return const SizedBox.shrink();
              }
              final secs = max(0, remaining.inSeconds);
              return Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const SizedBox(width: 8),
                  Text(
                    '·',
                    style: DotText.font(
                      size: 13.5,
                      color: DotColors.dotSep,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    'auto-stop in ${secs}s',
                    style: DotText.timer.copyWith(color: DotColors.muted),
                  ),
                ],
              );
            }),
          ],
        ),
        const SizedBox(height: 14),
        Waveform(color: brandRed, bars: 32, height: 52),
        const SizedBox(height: 14),
        _Caption(partial: partial),
        const SizedBox(height: 14),
        Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _StopButton(onTap: () {
              AppLog.instance.log('ui', 'stop tapped');
              ctrl.stopManual();
            }),
            const SizedBox(height: 14),
            _HintPill(),
          ],
        ),
      ],
    );
  }

  static String _fmtElapsed(Duration d) {
    final s = d.inSeconds;
    return '${s ~/ 60}:${(s % 60).toString().padLeft(2, '0')}';
  }
}

// ── Caption ───────────────────────────────────────────────────────────────────

class _Caption extends StatefulWidget {
  const _Caption({required this.partial});
  final String partial;

  @override
  State<_Caption> createState() => _CaptionState();
}

class _CaptionState extends State<_Caption>
    with SingleTickerProviderStateMixin {
  late final AnimationController _blinkCtrl;

  @override
  void initState() {
    super.initState();
    _blinkCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _blinkCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isEmpty = widget.partial.isEmpty;
    final reducedMotion = MediaQuery.of(context).disableAnimations;

    Widget cursor = const Text(
      '▍',
      style: TextStyle(color: DotColors.ink),
    );
    if (!isEmpty && !reducedMotion) {
      cursor = AnimatedBuilder(
        animation: _blinkCtrl,
        builder: (_, child) => Opacity(
          opacity: 0.5 * _blinkCtrl.value,
          child: child,
        ),
        child: cursor,
      );
    } else if (!isEmpty) {
      cursor = Opacity(opacity: 0.5, child: cursor);
    }

    return ConstrainedBox(
      constraints: const BoxConstraints(minHeight: 64),
      child: Center(
        child: RichText(
          textAlign: TextAlign.center,
          text: TextSpan(
            style: DotText.font(
              size: 16,
              weight: FontWeight.w600,
              height: 1.4,
              color: isEmpty ? DotColors.captionIdle : DotColors.ink,
              letterSpacing: -0.2,
            ),
            children: [
              TextSpan(text: isEmpty ? 'Listening…' : widget.partial),
              if (!isEmpty)
                WidgetSpan(
                  alignment: PlaceholderAlignment.baseline,
                  baseline: TextBaseline.alphabetic,
                  child: cursor,
                ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Stop button ───────────────────────────────────────────────────────────────

class _StopButton extends StatelessWidget {
  const _StopButton({required this.onTap});
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.fromLTRB(16, 13, 24, 13),
        decoration: BoxDecoration(
          color: DotColors.ink,
          borderRadius: BorderRadius.circular(40),
          boxShadow: DotShadow.stopButton,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Red circle with white square stop icon
            Container(
              width: 26,
              height: 26,
              decoration: BoxDecoration(
                color: brandRed,
                borderRadius: BorderRadius.circular(26),
              ),
              alignment: Alignment.center,
              child: Container(
                width: 9,
                height: 9,
                decoration: BoxDecoration(
                  color: DotColors.white,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(width: 10),
            Text(
              'Stop',
              style: DotText.font(
                size: 15.5,
                weight: FontWeight.w700,
                // Dark label on the light (ink-filled) pill.
                color: DotColors.canvas,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Hint pill ─────────────────────────────────────────────────────────────────

class _HintPill extends StatelessWidget {
  const _HintPill();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 13),
      decoration: BoxDecoration(
        color: DotColors.searchFill,
        borderRadius: BorderRadius.circular(30),
        border: Border.all(color: DotColors.outline),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _PulsingDot(size: 6, color: brandRed),
          const SizedBox(width: 7),
          Text(
            'Tap Stop to finish',
            style: DotText.font(
              size: 12.5,
              weight: FontWeight.w600,
              color: DotColors.muted,
            ),
          ),
        ],
      ),
    );
  }
}

// ── Pulsing dot ───────────────────────────────────────────────────────────────

class _PulsingDot extends StatefulWidget {
  const _PulsingDot({required this.size, required this.color});
  final double size;
  final Color color;

  @override
  State<_PulsingDot> createState() => _PulsingDotState();
}

class _PulsingDotState extends State<_PulsingDot>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double> _opacityAnim;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1100),
    )..repeat(reverse: true);
    _opacityAnim = Tween<double>(begin: 0.3, end: 1.0).animate(
      CurvedAnimation(parent: _ctrl, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final reducedMotion = MediaQuery.of(context).disableAnimations;
    if (reducedMotion) {
      return _dot(1.0);
    }
    return AnimatedBuilder(
      animation: _opacityAnim,
      builder: (_, _) => _dot(_opacityAnim.value),
    );
  }

  Widget _dot(double opacity) {
    return Container(
      width: widget.size,
      height: widget.size,
      decoration: BoxDecoration(
        color: widget.color.withValues(alpha: opacity),
        borderRadius: BorderRadius.circular(widget.size),
      ),
    );
  }
}

// ── Processing view ───────────────────────────────────────────────────────────
//
// ONE view for every processing stage (Heard → Transcribing → LoadingLlm →
// Sorting). _StateBody gives it a constant key, so it is reused across stages:
// the arrow keeps rotating without restarting and only [label] cross-fades.

class _ProcessingView extends StatefulWidget {
  const _ProcessingView({
    super.key,
    required this.label,
    required this.reducedMotion,
  });

  final String label;
  final bool reducedMotion;

  @override
  State<_ProcessingView> createState() => _ProcessingViewState();
}

class _ProcessingViewState extends State<_ProcessingView>
    with SingleTickerProviderStateMixin {
  late final AnimationController _spin;

  @override
  void initState() {
    super.initState();
    _spin = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 950),
    );
    if (!widget.reducedMotion) _spin.repeat();
  }

  @override
  void dispose() {
    _spin.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final arrow = widget.reducedMotion
        ? const CustomPaint(
            size: Size(44, 44),
            painter: _RotatingArrowPainter(angle: 0),
          )
        : AnimatedBuilder(
            animation: _spin,
            builder: (_, _) => CustomPaint(
              size: const Size(44, 44),
              painter: _RotatingArrowPainter(angle: _spin.value * 2 * pi),
            ),
          );

    return Padding(
      padding: const EdgeInsets.fromLTRB(0, 16, 0, 8),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          arrow,
          const SizedBox(height: 20),
          // Only the label changes between stages — cross-fade it.
          AnimatedSwitcher(
            duration: widget.reducedMotion
                ? Duration.zero
                : const Duration(milliseconds: 240),
            child: Text(
              widget.label,
              key: ValueKey(widget.label),
              style: DotText.font(
                size: 18,
                weight: FontWeight.w700,
                color: DotColors.ink,
                letterSpacing: -0.3,
              ),
            ),
          ),
          const SizedBox(height: 8),
        ],
      ),
    );
  }
}

// ── Rotating arrow ────────────────────────────────────────────────────────────

class _RotatingArrowPainter extends CustomPainter {
  const _RotatingArrowPainter({required this.angle});
  final double angle;

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2 - 3;

    final stroke = Paint()
      ..color = brandRed
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3
      ..strokeCap = StrokeCap.round;

    // Faint full track.
    canvas.drawCircle(
      center,
      radius,
      Paint()
        ..color = brandRed.withValues(alpha: 0.12)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3,
    );

    canvas.save();
    canvas.translate(center.dx, center.dy);
    canvas.rotate(angle);

    // ~270° arc.
    const start = -pi / 2;
    const sweep = pi * 1.5;
    canvas.drawArc(
      Rect.fromCircle(center: Offset.zero, radius: radius),
      start,
      sweep,
      false,
      stroke,
    );

    // Arrowhead at the leading tip, pointing along the tangent.
    const end = start + sweep;
    final tip = Offset(radius * cos(end), radius * sin(end));
    const tangent = end + pi / 2;
    const head = 7.0;
    final a = tip + Offset(head * cos(tangent - 2.6), head * sin(tangent - 2.6));
    final b = tip + Offset(head * cos(tangent + 2.6), head * sin(tangent + 2.6));
    canvas.drawPath(
      Path()
        ..moveTo(a.dx, a.dy)
        ..lineTo(tip.dx, tip.dy)
        ..lineTo(b.dx, b.dy),
      stroke,
    );

    canvas.restore();
  }

  @override
  bool shouldRepaint(_RotatingArrowPainter old) => old.angle != angle;
}

// ── Result body ───────────────────────────────────────────────────────────────

class _ResultBody extends ConsumerStatefulWidget {
  const _ResultBody({
    required this.result,
    required this.reducedMotion,
  });

  final CaptureResult result;
  final bool reducedMotion;

  @override
  ConsumerState<_ResultBody> createState() => _ResultBodyState();
}

class _ResultBodyState extends ConsumerState<_ResultBody>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double> _fadeAnim;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 360),
    );
    _fadeAnim = Tween<double>(begin: 0.5, end: 1.0).animate(
      CurvedAnimation(
        parent: _ctrl,
        curve: const Cubic(0.2, 0.8, 0.3, 1),
      ),
    );
    if (!widget.reducedMotion) {
      _ctrl.forward();
    } else {
      _ctrl.value = 1.0;
    }
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final r = widget.result;

    // Decorate bucket name + colors.
    final buckets = ref.watch(bucketsProvider).asData?.value ?? [];
    final String bucketName;
    if (r.bucketId == null) {
      bucketName = 'Unsorted';
    } else {
      final match = buckets.where((b) => b.id == r.bucketId);
      bucketName = match.isNotEmpty ? match.first.name : r.bucketId!;
    }
    final c = bucketColorsFor(r.bucketId ?? 'unsorted');

    return AnimatedBuilder(
      animation: _fadeAnim,
      builder: (_, child) => Opacity(opacity: _fadeAnim.value, child: child),
      child: Padding(
        padding: const EdgeInsets.only(top: 14),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Confirm circle
            Container(
              width: 52,
              height: 52,
              decoration: BoxDecoration(
                color: DotColors.confirmGreen,
                borderRadius: BorderRadius.circular(52),
                boxShadow: [
                  BoxShadow(
                    color: DotColors.confirmGreen.withValues(alpha: 0.47),
                    offset: const Offset(0, 8),
                    blurRadius: 20,
                    spreadRadius: -6,
                  ),
                ],
              ),
              alignment: Alignment.center,
              child: const DotIcon(
                DotIconName.check,
                size: 28,
                color: DotColors.white,
                weight: 2.6,
              ),
            ),
            const SizedBox(height: 16),
            // Filed / Needs a home label ('Saved' while routing in background)
            Text(
              r.provisional ? 'Saved' : (r.filed ? 'FILED' : 'NEEDS A HOME'),
              style: DotText.font(
                size: 13,
                weight: FontWeight.w700,
                color: DotColors.faint,
                letterSpacing: 0.3,
              ),
            ),
            const SizedBox(height: 16),
            // Result card
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 320),
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(
                  vertical: 15,
                  horizontal: 17,
                ),
                decoration: BoxDecoration(
                  color: DotColors.surface,
                  borderRadius: BorderRadius.circular(DotRadii.result),
                  border: Border.all(color: DotColors.outline),
                  boxShadow: DotShadow.result,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Bucket chip + type chip row
                    Row(
                      children: [
                        _BucketChip(name: bucketName, colors: c),
                        if (r.filed && r.type != null) ...[
                          const SizedBox(width: 8),
                          TypeChip(
                            type: r.type!,
                            ink: DotColors.muted,
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 10),
                    // Summary
                    Text(
                      r.summary,
                      style: DotText.font(
                        size: 15.5,
                        weight: FontWeight.w600,
                        color: DotColors.ink,
                        height: 1.32,
                      ),
                    ),
                    // Low-confidence note ('sorting in background…' while the
                    // routing patch is still pending for an Unsorted row)
                    if (!r.filed)
                      Padding(
                        padding: const EdgeInsets.only(top: 8),
                        child: Text(
                          r.provisional
                              ? 'sorting in background…'
                              : 'Low confidence — sent to Unsorted instead of guessing.',
                          style: DotText.font(
                            size: 12.5,
                            weight: FontWeight.w500,
                            color: DotColors.faint2,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 4),
          ],
        ),
      ),
    );
  }
}

class _BucketChip extends StatelessWidget {
  const _BucketChip({required this.name, required this.colors});

  final String name;
  final BucketColors colors;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 11),
      decoration: BoxDecoration(
        color: colors.fill,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(
              color: colors.accent,
              borderRadius: BorderRadius.circular(8),
            ),
          ),
          const SizedBox(width: 6),
          Text(
            name,
            style: DotText.font(
              size: 12.5,
              weight: FontWeight.w700,
              color: colors.ink,
            ),
          ),
        ],
      ),
    );
  }
}

