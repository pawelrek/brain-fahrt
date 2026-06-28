import 'package:flutter/widgets.dart';

import '../design/colors.dart';
import '../design/typography.dart';
import '../../data/models/enums.dart';

/// A monochrome icon glyph for an [ItemType], painted in a 16×16 viewBox
/// scaled to [size]. Stroke [color] defaults to [DotColors.ink].
class TypeGlyph extends StatelessWidget {
  const TypeGlyph({
    super.key,
    required this.type,
    this.size = 12,
    this.color = DotColors.ink,
  });

  final ItemType type;
  final double size;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      size: Size(size, size),
      painter: _TypeGlyphPainter(type: type, color: color),
    );
  }
}

class _TypeGlyphPainter extends CustomPainter {
  _TypeGlyphPainter({required this.type, required this.color});

  final ItemType type;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    // Scale from 16×16 viewBox to actual size.
    final scale = size.width / 16.0;
    canvas.scale(scale, scale);

    switch (type) {
      case ItemType.improvement:
        _paintImprovement(canvas);
      case ItemType.bug:
        _paintBug(canvas);
      case ItemType.issue:
        _paintIssue(canvas);
    }
  }

  /// Arrow up: M8 13V4 ; M8 4 L4.5 7.5 ; M8 4 l3.5 3.5
  void _paintImprovement(Canvas canvas) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 1.7
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..style = PaintingStyle.stroke;

    // Vertical shaft
    canvas.drawLine(const Offset(8, 13), const Offset(8, 4), paint);
    // Left arrow head
    canvas.drawLine(const Offset(8, 4), const Offset(4.5, 7.5), paint);
    // Right arrow head
    canvas.drawLine(const Offset(8, 4), const Offset(11.5, 7.5), paint);
  }

  /// Bug: rect body + antennae/legs
  void _paintBug(Canvas canvas) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 1.5
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..style = PaintingStyle.stroke;

    // Body rect x5 y5.5 w6 h7 rx3
    final bodyRect = RRect.fromRectAndRadius(
      const Rect.fromLTWH(5, 5.5, 6, 7),
      const Radius.circular(3),
    );
    canvas.drawRRect(bodyRect, paint);

    // M8 2.6v2.9
    canvas.drawLine(const Offset(8, 2.6), const Offset(8, 5.5), paint);
    // M3.2 7H5
    canvas.drawLine(const Offset(3.2, 7), const Offset(5, 7), paint);
    // M11 7h1.8
    canvas.drawLine(const Offset(11, 7), const Offset(12.8, 7), paint);
    // M3.4 10.6H5
    canvas.drawLine(const Offset(3.4, 10.6), const Offset(5, 10.6), paint);
    // M11 10.6h1.6
    canvas.drawLine(const Offset(11, 10.6), const Offset(12.6, 10.6), paint);
    // M5 3.6l1.3 1.4
    canvas.drawLine(const Offset(5, 3.6), const Offset(6.3, 5), paint);
    // M11 3.6L9.7 5
    canvas.drawLine(const Offset(11, 3.6), const Offset(9.7, 5), paint);
  }

  /// Issue — alert triangle with exclamation mark and filled dot.
  void _paintIssue(Canvas canvas) {
    final strokePaint = Paint()
      ..color = color
      ..strokeWidth = 1.7
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..style = PaintingStyle.stroke;

    // Triangle M8 2.5 L14 13 H2 Z
    final triangle = Path()
      ..moveTo(8, 2.5)
      ..lineTo(14, 13)
      ..lineTo(2, 13)
      ..close();
    canvas.drawPath(triangle, strokePaint);

    // Exclamation shaft M8 6.6v3.1
    canvas.drawLine(const Offset(8, 6.6), const Offset(8, 9.7), strokePaint);

    // Filled dot at (8, 11.4) r0.5
    final dotPaint = Paint()
      ..color = color
      ..style = PaintingStyle.fill;
    canvas.drawCircle(const Offset(8, 11.4), 0.5, dotPaint);
  }

  @override
  bool shouldRepaint(_TypeGlyphPainter old) =>
      old.type != type || old.color != color;
}

/// Inline label combining a [TypeGlyph] and the type's human label.
/// Opacity 0.78 per design.
class TypeChip extends StatelessWidget {
  const TypeChip({super.key, required this.type, required this.ink});

  final ItemType type;
  final Color ink;

  @override
  Widget build(BuildContext context) {
    return Opacity(
      opacity: 0.78,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          TypeGlyph(type: type, size: 12, color: ink),
          const SizedBox(width: 4),
          Text(
            type.label,
            style: DotText.typeLabel.copyWith(color: ink),
          ),
        ],
      ),
    );
  }
}
