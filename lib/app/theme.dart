import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../core/design/colors.dart';

/// App theme: Keep-dark near-black canvas + Hanken Grotesk. The UI is largely
/// custom painted, so this just sets the defaults the screens build on.
ThemeData buildDotTheme() {
  final base = ThemeData(brightness: Brightness.dark, useMaterial3: true);
  return base.copyWith(
    scaffoldBackgroundColor: DotColors.canvas,
    canvasColor: DotColors.canvas,
    textTheme: GoogleFonts.hankenGroteskTextTheme(base.textTheme)
        .apply(bodyColor: DotColors.ink, displayColor: DotColors.ink),
    colorScheme: base.colorScheme.copyWith(
      surface: DotColors.canvas,
      primary: brandRed,
    ),
  );
}
