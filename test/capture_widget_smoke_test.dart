import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:slop/data/providers.dart';
import 'package:slop/features/capture/capture_controller.dart';
import 'package:slop/features/capture/capture_overlay.dart';
import 'package:slop/features/dashboard/capture_fab.dart';
import 'package:slop/features/dashboard/dashboard_screen.dart';
import 'package:slop/pipeline/simulated_pipeline.dart';

import 'helpers.dart';

/// Host-side end-to-end smoke (the plan's acceptance): tap the red dot → record
/// → the simulated pipeline files a note → the card lands on the board, bold.
void main() {
  testWidgets('tap red dot → capture → General card shows the bold new note',
      (tester) async {
    tester.view.physicalSize = const Size(1200, 3200);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final db = await seededMemoryDb();

    await tester.pumpWidget(testHarness(
      db: db,
      extraOverrides: [
        capturePipelineProvider.overrideWithValue(SimulatedPipeline(
          charInterval: Duration.zero,
          heardDelay: Duration.zero,
          transcribingDelay: Duration.zero,
          sortingDelay: Duration.zero,
        )),
        captureResultHoldProvider.overrideWithValue(Duration.zero),
      ],
      child: Builder(
        builder: (context) => DashboardScreen(
          onOpenBucket: (_) {},
          onCapture: () => showCaptureOverlay(context),
        ),
      ),
    ));
    await tester.pumpAndSettle();

    const newSummary = 'Add a dark mode toggle to settings';
    expect(find.text(newSummary), findsNothing);

    // Open capture.
    await tester.tap(find.byType(CaptureFab));
    await tester.pump();
    await tester.pump();
    expect(find.text('Recording'), findsOneWidget);

    // Stop → instant processing + zero result-hold → commit → dismiss.
    await tester.tap(find.text('Stop'));
    await tester.pump(const Duration(milliseconds: 30));
    await tester.pump();
    await tester.pumpAndSettle();

    // The new note landed in General and is highlighted (bold w700).
    expect(find.text(newSummary), findsOneWidget);
    expect(
      tester.widget<Text>(find.text(newSummary)).style?.fontWeight,
      FontWeight.w700,
    );
    final container = ProviderScope.containerOf(
      tester.element(find.byType(DashboardScreen)),
    );
    expect(container.read(newItemIdProvider), isNotNull);

    // Let the ~2.6s highlight timer fire so no Timer is pending at teardown.
    await tester.pump(const Duration(seconds: 3));

    // Close DB before ProviderScope disposal to avoid Drift scheduling a
    // stream-close timer that the framework detects as "pending" at teardown.
    await db.close();
    await tester.pumpWidget(const SizedBox());
    await tester.pumpAndSettle();
  });
}
