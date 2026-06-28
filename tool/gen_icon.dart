import 'dart:io';

import 'package:image/image.dart' as img;

/// Generates `assets/icon/slop_icon.png` — the slop launcher icon: a red field
/// with a white ring + white centre dot, matching the in-app record button
/// (see lib/features/dashboard/capture_fab.dart / lib/core/widgets/red_dot.dart).
/// Red #F23B2F == brandRed (DotReds.defaultRed); red is deliberate per the user's
/// request for the red recording icon (overrides the early plan draft's cream).
///
/// Run with: `dart run tool/gen_icon.dart`
void main() {
  const s = 1024;
  final red = img.ColorRgba8(242, 59, 47, 255); // brandRed #F23B2F
  final white = img.ColorRgba8(255, 255, 255, 255);
  const c = s ~/ 2;

  final im = img.Image(width: s, height: s, numChannels: 4);
  img.fill(im, color: red);
  // White ring as a donut: white outer disc, then punch back to red inside.
  img.fillCircle(im, x: c, y: c, radius: 250, color: white, antialias: true);
  img.fillCircle(im, x: c, y: c, radius: 204, color: red, antialias: true);
  // White centre dot.
  img.fillCircle(im, x: c, y: c, radius: 74, color: white, antialias: true);

  Directory('assets/icon').createSync(recursive: true);
  File('assets/icon/slop_icon.png').writeAsBytesSync(img.encodePng(im));
  stdout.writeln('wrote assets/icon/slop_icon.png (${s}x$s)');
}
