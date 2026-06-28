import 'package:flutter/widgets.dart';

/// Corner radii — Keep-dark restyle: cards 14, search is a full pill.
abstract final class DotRadii {
  static const card = 14.0;
  static const search = 28.0;
  static const result = 18.0;
  static const circleBtn = 40.0; // detail back-button circle
  static const fab = 72.0;
  static const chip = 20.0;
  static const sheetTop = 30.0;
}

/// Common paddings (the per-screen variants live in their widgets).
abstract final class DotPad {
  /// Board padding: `4px 14px 120px` (bottom clears the FAB).
  static const board = EdgeInsets.fromLTRB(14, 4, 14, 120);

  /// Header padding: `6px 20px 10px`.
  static const header = EdgeInsets.fromLTRB(20, 6, 20, 10);

  /// Masonry gap (column + row).
  static const cardGap = 12.0;
}

/// Drop shadows — Keep dark is flat: cards and the search pill cast none;
/// only floating layers (sheets, dialogs, the result card) keep a subtle
/// black elevation.
abstract final class DotShadow {
  /// Filled / tinted card: flat on dark.
  static const card = <BoxShadow>[];

  /// Search pill: flat on dark.
  static const search = <BoxShadow>[];

  /// Result card / dialogs: one soft black shadow.
  static const result = <BoxShadow>[
    BoxShadow(
        color: Color(0x59000000),
        offset: Offset(0, 8),
        blurRadius: 24,
        spreadRadius: -8),
  ];

  /// Bottom sheet: subtle black lift above the scrim.
  static const sheet = <BoxShadow>[
    BoxShadow(
        color: Color(0x66000000),
        offset: Offset(0, -8),
        blurRadius: 32,
        spreadRadius: -12),
  ];

  /// Stop button: `0 10px 24px -10px rgba(0,0,0,0.5)`.
  static const stopButton = <BoxShadow>[
    BoxShadow(
        color: Color(0x80000000),
        offset: Offset(0, 10),
        blurRadius: 24,
        spreadRadius: -10),
  ];

  /// FAB: `0 10px 26px -6px {red}99, 0 4px 10px rgba(0,0,0,0.18)`.
  /// (The inset white highlight is approximated by the FAB's radial gradient.)
  static List<BoxShadow> fab(Color red) => [
        BoxShadow(
            color: red.withValues(alpha: 0.6),
            offset: const Offset(0, 10),
            blurRadius: 26,
            spreadRadius: -6),
        const BoxShadow(
            color: Color(0x2E000000), offset: Offset(0, 4), blurRadius: 10),
      ];
}

/// Inset/hairline borders expressed as Flutter [Border]s.
abstract final class DotBorders {
  /// Edged card: `inset 0 0 0 1.5px {accent}59` (accent @ ~35%).
  static Border edged(Color accent) =>
      Border.all(color: accent.withValues(alpha: 0.35), width: 1.5);
}
