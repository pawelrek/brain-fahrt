import 'dart:math' show max;

import 'package:flutter/widgets.dart';

import '../design/colors.dart';

/// The brand mark: a ring with a centre-filled dot ("record / target" red dot).
///
/// [size]       overall bounding box (width == height).
/// [color]      fill colour for both ring and centre dot unless [ringColor] overrides.
/// [ringColor]  stroke colour of the outer ring; defaults to [color].
/// [ringWeight] stroke width of the ring; defaults to max(2, size * 0.11).
class RedDot extends StatelessWidget {
  const RedDot({
    super.key,
    this.size = 28,
    this.color = brandRed,
    this.ringColor,
    this.ringWeight,
  });

  final double size;
  final Color color;
  final Color? ringColor;
  final double? ringWeight;

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      size: Size.square(size),
      painter: _RedDotPainter(
        color: color,
        ringColor: ringColor ?? color,
        ringWeight: ringWeight ?? max(2, size * 0.11),
        dotRadius: size * 0.16,
      ),
    );
  }
}

class _RedDotPainter extends CustomPainter {
  const _RedDotPainter({
    required this.color,
    required this.ringColor,
    required this.ringWeight,
    required this.dotRadius,
  });

  final Color color;
  final Color ringColor;
  final double ringWeight;
  final double dotRadius;

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);

    // Outer ring — stroke only.
    final ringRadius = (size.width - ringWeight) / 2 - 0.5;
    canvas.drawCircle(
      center,
      ringRadius,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = ringWeight
        ..color = ringColor,
    );

    // Centre filled dot.
    canvas.drawCircle(
      center,
      dotRadius,
      Paint()
        ..style = PaintingStyle.fill
        ..color = color,
    );
  }

  @override
  bool shouldRepaint(_RedDotPainter old) =>
      old.color != color ||
      old.ringColor != ringColor ||
      old.ringWeight != ringWeight ||
      old.dotRadius != dotRadius;
}
