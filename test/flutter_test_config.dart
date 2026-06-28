import 'dart:async';

import 'package:google_fonts/google_fonts.dart';

/// Auto-loaded by flutter_test before any test in this directory.
///
/// Disables GoogleFonts runtime HTTP fetching — in the test sandbox the fetch
/// fails/awaits and leaves pending work that makes `pumpAndSettle` hang. With
/// fetching off, GoogleFonts falls back to the bundled/system font synchronously.
Future<void> testExecutable(FutureOr<void> Function() testMain) async {
  GoogleFonts.config.allowRuntimeFetching = false;
  await testMain();
}
