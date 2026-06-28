import 'package:flutter/widgets.dart';

/// Canvas, ink and neutral tokens — Google-Keep-dark restyle.
/// Near-black canvas, slightly-raised dark surfaces, light text.
abstract final class DotColors {
  static const canvas = Color(0xFF131314); // app background (Keep dark)
  static const surface = Color(0xFF1E1F22); // raised cards / sheets / dialogs
  static const searchFill = Color(0xFF28292C); // search pill / input fills
  static const outline = Color(0xFF3A3B3E); // 1px outline on surfaces
  static const ink = Color(0xFFE8EAED); // primary text / headings
  static const inkStrong = Color(0xFFF1F3F4); // wordmark "Dot"
  static const inkTitle = Color(0xFFE8EAED); // card title on surface
  static const inkBody = Color(0xFFDADCE0); // card body text on surface
  static const muted = Color(0xFF9AA0A6); // labels, hints, settings icon
  static const faint = Color(0xFF6E7277); // timestamps, section labels
  static const faint2 = Color(0xFF686C70); // placeholders, search icon, ts
  static const faint3 = Color(0xFF5B5F63); // section counts, empty-italic
  static const captionIdle = Color(0xFF75797E); // "Listening…" placeholder
  static const dotSep = Color(0xFF45474A); // "·" separator in recording row
  static const grabber = Color(0xFF3C3F43); // sheet grabber pill
  static const listBorder = Color(0xFF5A5D61); // unfilled list checkbox border
  static const white = Color(0xFFFFFFFF);
  static const confirmGreen = Color(0xFF3FB069); // success check
  static const hairline = Color(0xFF2C2D30); // subtle row dividers
  static const scrim = Color(0x8A000000); // overlay scrim (black @54%)
}

/// The signature "red dot". Default first, then the two approved options.
abstract final class DotReds {
  static const defaultRed = Color(0xFFF23B2F);
  static const coral = Color(0xFFFF5A4D);
  static const classic = Color(0xFFE0352A);
}

/// The brand red used everywhere unless overridden by a future theme setting.
const Color brandRed = DotReds.defaultRed;

/// A bucket's `{ fill, ink, accent }` triple.
/// `fill` = muted dark card background, `ink` = light text on fill, `accent` =
/// a brighter tint of the fill's hue for chips/dots/borders. `unsorted` is the
/// neutral grey treatment.
@immutable
class BucketColors {
  final Color fill;
  final Color ink;
  final Color accent;
  const BucketColors(this.fill, this.ink, this.accent);
}

/// Keep-dark bucket palette — muted fills, near-white ink, bright accents.
/// Hue-respecting mapping from the old pastel "Blossom" set:
/// devhub (indigo→teal), webapp (orange→dusty rose), general (green→sage),
/// shopping (yellow→ocher), todos (blue→slate blue), ideas (purple→plum).
const Map<String, BucketColors> keepDarkPalette = {
  'devhub': BucketColors(Color(0xFF1F4A47), Color(0xFFE8EAED), Color(0xFF78CBC4)),
  'webapp': BucketColors(Color(0xFF5B3A41), Color(0xFFE8EAED), Color(0xFFE2939E)),
  'general': BucketColors(Color(0xFF3A4A33), Color(0xFFE8EAED), Color(0xFFA3C998)),
  'shopping': BucketColors(Color(0xFF564625), Color(0xFFE8EAED), Color(0xFFE0C26A)),
  'todos': BucketColors(Color(0xFF2D4356), Color(0xFFE8EAED), Color(0xFF84B5E0)),
  'ideas': BucketColors(Color(0xFF46355A), Color(0xFFE8EAED), Color(0xFFC29FE8)),
  'unsorted': BucketColors(Color(0xFF3C3F43), Color(0xFFE8EAED), Color(0xFF9AA0A6)),
};

/// Look up a bucket's colors by its `colorKey`, falling back to the neutral
/// `unsorted` treatment for unknown keys.
BucketColors bucketColorsFor(String colorKey) {
  return keepDarkPalette[colorKey] ?? keepDarkPalette['unsorted']!;
}
