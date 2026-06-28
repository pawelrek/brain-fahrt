import 'dart:math' as math show sin, pi;

import 'package:flutter/widgets.dart';

import '../design/colors.dart';

/// An animated waveform of vertical bars that responds to audio amplitude.
///
/// [color]  bar colour (default [brandRed]).
/// [bars]   number of bars (default 34).
/// [height] total widget height in logical pixels (default 44).
/// [amp]    overall amplitude multiplier, 0.0–1.0 (default 1).
/// [idle]   when true, bars are static and dim — no motion (default false).
///
/// Reduced motion ([MediaQuery.disableAnimations]) → one static frame at
/// phase 0, no [AnimationController] created.
class Waveform extends StatefulWidget {
  const Waveform({
    super.key,
    this.color = brandRed,
    this.bars = 32,
    this.height = 44,
    this.amp = 1.0,
    this.idle = false,
  });

  final Color color;
  final int bars;
  final double height;
  final double amp;
  final bool idle;

  @override
  State<Waveform> createState() => _WaveformState();
}

class _WaveformState extends State<Waveform>
    with SingleTickerProviderStateMixin {
  AnimationController? _controller;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final reducedMotion = MediaQuery.of(context).disableAnimations;
    if (reducedMotion) {
      _controller?.dispose();
      _controller = null;
    } else {
      _controller ??= AnimationController(
        vsync: this,
        duration: const Duration(seconds: 1),
      )..repeat();
    }
  }

  @override
  void didUpdateWidget(Waveform old) {
    super.didUpdateWidget(old);
    if (widget.idle != old.idle) {
      if (widget.idle) {
        _controller?.stop();
      } else {
        _controller?.repeat();
      }
    }
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final barCount = widget.bars;
    final totalWidth = barCount * 3.5 + (barCount - 1) * 3.0;

    if (_controller == null) {
      // Reduced motion — single static frame.
      return SizedBox(
        width: totalWidth,
        height: widget.height,
        child: CustomPaint(
          painter: _WaveformPainter(
            color: widget.color,
            bars: barCount,
            height: widget.height,
            amp: widget.amp,
            idle: widget.idle,
            phase: 0.0,
          ),
        ),
      );
    }

    return AnimatedBuilder(
      animation: _controller!,
      builder: (context, _) {
        return SizedBox(
          width: totalWidth,
          height: widget.height,
          child: CustomPaint(
            painter: _WaveformPainter(
              color: widget.color,
              bars: barCount,
              height: widget.height,
              amp: widget.amp,
              idle: widget.idle,
              phase: _controller!.value,
            ),
          ),
        );
      },
    );
  }
}

class _WaveformPainter extends CustomPainter {
  const _WaveformPainter({
    required this.color,
    required this.bars,
    required this.height,
    required this.amp,
    required this.idle,
    required this.phase,
  });

  final Color color;
  final int bars;
  final double height;
  final double amp;
  final bool idle;
  final double phase; // normalized 0→1 (controller.value)

  @override
  void paint(Canvas canvas, Size size) {
    const barW = 3.5;
    const gap = 3.0;
    const radius = Radius.circular(3);

    for (int i = 0; i < bars; i++) {
      final seed = 0.5 + math.sin(i * 12.9898) * 0.5;
      double barH;
      double opacity;

      if (idle) {
        barH = (0.1 + ((seed * 1.7) % 1) * 0.12) * height;
        opacity = 0.32;
      } else {
        final f1 = math.sin(phase * 2 * math.pi * 6 + i * 0.55);
        final f2 = math.sin(phase * 2 * math.pi * 3 + i * 0.9 + seed * 6);
        barH = (0.18 + (f1 * 0.6 + f2 * 0.34).abs() * 0.82) * height * amp;
        barH = barH.clamp(3.0, height);
        opacity = 0.55 + (barH / height) * 0.45;
      }

      final x = i * (barW + gap);
      final top = (height - barH) / 2;
      final rect = RRect.fromLTRBR(
        x,
        top,
        x + barW,
        top + barH,
        radius,
      );

      canvas.drawRRect(
        rect,
        Paint()..color = color.withValues(alpha: opacity),
      );
    }
  }

  @override
  bool shouldRepaint(_WaveformPainter old) =>
      old.color != color ||
      old.bars != bars ||
      old.height != height ||
      old.amp != amp ||
      old.idle != idle ||
      old.phase != phase;
}
