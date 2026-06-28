import 'package:flutter/widgets.dart';

import '../design/colors.dart';

/// All icon names supported by [DotIcon].
enum DotIconName { search, close, check, mic, settings, grid, inbox }

/// A single-color line icon drawn with [CustomPainter].
///
/// All paths are defined in a 24×24 viewBox and scaled uniformly to [size].
class DotIcon extends StatelessWidget {
  const DotIcon(
    this.name, {
    super.key,
    this.size = 22,
    this.color = DotColors.ink,
    this.weight = 1.8,
  });

  final DotIconName name;
  final double size;
  final Color color;

  /// Stroke width in the 24×24 viewBox (scaled with [size]).
  final double weight;

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      size: Size(size, size),
      painter: _IconPainter(name: name, color: color, weight: weight),
    );
  }
}

// ---------------------------------------------------------------------------
// Painter
// ---------------------------------------------------------------------------

class _IconPainter extends CustomPainter {
  const _IconPainter({
    required this.name,
    required this.color,
    required this.weight,
  });

  final DotIconName name;
  final Color color;
  final double weight;

  @override
  void paint(Canvas canvas, Size size) {
    // Scale from the 24×24 design viewBox to the actual render size.
    final scale = size.width / 24.0;
    canvas.scale(scale, scale);

    final stroke = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = weight
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    switch (name) {
      case DotIconName.search:
        _drawSearch(canvas, stroke);
      case DotIconName.close:
        _drawClose(canvas, stroke);
      case DotIconName.check:
        _drawCheck(canvas, stroke);
      case DotIconName.mic:
        _drawMic(canvas, stroke);
      case DotIconName.settings:
        _drawSettings(canvas, stroke);
      case DotIconName.grid:
        _drawGrid(canvas, stroke);
      case DotIconName.inbox:
        _drawInbox(canvas, stroke);
    }
  }

  // search: circle(11,11)r7 ; M20 20 l-3.6 -3.6
  void _drawSearch(Canvas canvas, Paint p) {
    canvas.drawCircle(const Offset(11, 11), 7, p);
    final path = Path()
      ..moveTo(20, 20)
      ..lineTo(16.4, 16.4);
    canvas.drawPath(path, p);
  }

  // close: M6 6 l12 12 ; M18 6 L6 18
  void _drawClose(Canvas canvas, Paint p) {
    final path = Path()
      ..moveTo(6, 6)
      ..lineTo(18, 18)
      ..moveTo(18, 6)
      ..lineTo(6, 18);
    canvas.drawPath(path, p);
  }

  // check: M5 12.5 l4.5 4.5 L19 7
  void _drawCheck(Canvas canvas, Paint p) {
    final path = Path()
      ..moveTo(5, 12.5)
      ..lineTo(9.5, 17)
      ..lineTo(19, 7);
    canvas.drawPath(path, p);
  }

  // mic: rrect x9 y3 w6 h11 rx3 ; arc ; M12 17.5V21 ; M8.5 21h7
  void _drawMic(Canvas canvas, Paint p) {
    // Body rounded rect
    final rrect = RRect.fromLTRBR(9, 3, 15, 14, const Radius.circular(3));
    canvas.drawRRect(rrect, p);

    // Arc: d="M5.5 11 a6.5 6.5 0 0 0 13 0"
    // arc from (5.5,11) sweeping 180° (large=0, sweep=0 means counter-clockwise
    // in SVG coords but we approximate as a semicircle centered at (12,11) r6.5)
    final arcPath = Path()
      ..moveTo(5.5, 11)
      ..arcToPoint(
        const Offset(18.5, 11),
        radius: const Radius.circular(6.5),
        clockwise: false,
      );
    canvas.drawPath(arcPath, p);

    // Stem and base
    final rest = Path()
      ..moveTo(12, 17.5)
      ..lineTo(12, 21)
      ..moveTo(8.5, 21)
      ..lineTo(15.5, 21);
    canvas.drawPath(rest, p);
  }

  // settings: circle(12,12)r3 ; spokes
  void _drawSettings(Canvas canvas, Paint p) {
    canvas.drawCircle(const Offset(12, 12), 3, p);
    final path = Path()
      ..moveTo(12, 2.5)
      ..lineTo(12, 5.5)
      ..moveTo(12, 18.5)
      ..lineTo(12, 21.5)
      ..moveTo(2.5, 12)
      ..lineTo(5.5, 12)
      ..moveTo(18.5, 12)
      ..lineTo(21.5, 12)
      ..moveTo(5, 5)
      ..lineTo(7.1, 7.1)
      ..moveTo(16.9, 16.9)
      ..lineTo(19, 19)
      ..moveTo(19, 5)
      ..lineTo(16.9, 7.1)
      ..moveTo(7.1, 16.9)
      ..lineTo(5, 19);
    canvas.drawPath(path, p);
  }

  // grid: four rrects rx2 w7 h7
  void _drawGrid(Canvas canvas, Paint p) {
    const r = Radius.circular(2);
    for (final rect in const [
      Rect.fromLTWH(3.5, 3.5, 7, 7),
      Rect.fromLTWH(13.5, 3.5, 7, 7),
      Rect.fromLTWH(3.5, 13.5, 7, 7),
      Rect.fromLTWH(13.5, 13.5, 7, 7),
    ]) {
      canvas.drawRRect(RRect.fromRectAndRadius(rect, r), p);
    }
  }

  // inbox: top trapezoid + box + tray shelf
  void _drawInbox(Canvas canvas, Paint p) {
    // Top trapezoid: M4 13 l2.5-7 h11 L20 13
    final top = Path()
      ..moveTo(4, 13)
      ..lineTo(6.5, 6)
      ..lineTo(17.5, 6)
      ..lineTo(20, 13);
    canvas.drawPath(top, p);

    // Box outline: M4 13 v5 a1 1 0 0 0 1 1 h14 a1 1 0 0 0 1 -1 v-5
    final box = Path()
      ..moveTo(4, 13)
      ..lineTo(4, 18)
      ..arcToPoint(const Offset(5, 19), radius: const Radius.circular(1))
      ..lineTo(19, 19)
      ..arcToPoint(const Offset(20, 18), radius: const Radius.circular(1))
      ..lineTo(20, 13);
    canvas.drawPath(box, p);

    // Tray shelf: M4 13 h4 l1.5 2.5 h5 L16 13 h4
    final shelf = Path()
      ..moveTo(4, 13)
      ..lineTo(8, 13)
      ..lineTo(9.5, 15.5)
      ..lineTo(14.5, 15.5)
      ..lineTo(16, 13)
      ..lineTo(20, 13);
    canvas.drawPath(shelf, p);
  }

  @override
  bool shouldRepaint(_IconPainter old) =>
      old.name != name || old.color != color || old.weight != weight;
}
