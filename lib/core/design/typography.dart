import 'package:flutter/widgets.dart';
import 'package:google_fonts/google_fonts.dart';

import 'colors.dart';

/// Type scale — Hanken Grotesk, from the handover "Typography" table.
///
/// Flutter only renders standard 100-step weights, so the handover's
/// half-weights are mapped to the nearest: 800→w800, 750/700→w700,
/// 650/600→w600, 550/500→w500.
abstract final class DotText {
  /// General-purpose Hanken Grotesk style. Use for any size/weight the named
  /// styles below don't cover (screens pass exact values from the JSX).
  static TextStyle font({
    required double size,
    FontWeight weight = FontWeight.w500,
    Color color = DotColors.ink,
    double? letterSpacing,
    double? height,
  }) =>
      GoogleFonts.hankenGrotesk(
        fontSize: size,
        fontWeight: weight,
        color: color,
        letterSpacing: letterSpacing,
        height: height,
      );

  /// Wordmark "Dot" — 25 / 800 / −0.6.
  static final TextStyle wordmark = font(
      size: 25,
      weight: FontWeight.w800,
      color: DotColors.inkStrong,
      letterSpacing: -0.6);

  /// Bucket-detail H1 — 27 / 800 / −0.6 (color set per-bucket by caller).
  static final TextStyle screenTitle =
      font(size: 27, weight: FontWeight.w800, letterSpacing: -0.6);

  /// Card / bucket name — 16.5 / 750 / −0.2.
  static final TextStyle cardName =
      font(size: 16.5, weight: FontWeight.w700, letterSpacing: -0.2);

  /// Body & item summary — 13.5 / 500 / 1.32.
  static final TextStyle itemSummary =
      font(size: 13.5, weight: FontWeight.w500, height: 1.32);

  /// Detail item summary — 15 / 600 / 1.35.
  static final TextStyle detailSummary =
      font(size: 15, weight: FontWeight.w600, height: 1.35);

  /// Count chip — 11.5 / 750.
  static final TextStyle countChip =
      font(size: 11.5, weight: FontWeight.w700, letterSpacing: 0.1);

  /// Type label (Improvement/Bug/Issue) — 11 / 700 / 0.2.
  static final TextStyle typeLabel =
      font(size: 11, weight: FontWeight.w700, letterSpacing: 0.2);

  /// Detail section label — 12.5 / 750 / 0.4 (uppercase applied by caller).
  static final TextStyle sectionLabel = font(
      size: 12.5,
      weight: FontWeight.w700,
      letterSpacing: 0.4,
      color: DotColors.faint);

  /// Search placeholder — 14.5 / 500 (muted hint on the dark search pill).
  static final TextStyle searchPlaceholder =
      font(size: 14.5, weight: FontWeight.w500, color: DotColors.muted);

  /// Recording timer — 13 / 750 / 0.5, tabular figures.
  static final TextStyle timer = GoogleFonts.hankenGrotesk(
    fontSize: 13,
    fontWeight: FontWeight.w700,
    letterSpacing: 0.5,
    color: DotColors.faint,
    fontFeatures: const [FontFeature.tabularFigures()],
  );

  /// Relative timestamp under detail rows — 12 / 550.
  static final TextStyle timestamp =
      font(size: 12, weight: FontWeight.w500, color: DotColors.faint2);
}
