import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:slop/data/providers.dart';
import 'package:slop/features/dashboard/capture_fab.dart';
import 'package:slop/features/dashboard/dashboard_screen.dart';

import 'helpers.dart';

/// Notifier override that always reports model as ready (prevents the
/// indeterminate LinearProgressIndicator from blocking pumpAndSettle).
class _AlwaysReadyModelController extends ModelReadyController {
  @override
  bool build() => true;
}

void main() {
  testWidgets('dashboard renders the seeded Keep-style board', (tester) async {
    // Tall surface so all 7 masonry cards lay out (the grid is lazy).
    tester.view.physicalSize = const Size(1200, 3200);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final db = await seededMemoryDb();

    await tester.pumpWidget(testHarness(
      db: db,
      // Simulate real pipeline (no demo banner) with model already ready
      // (no loading bar) so pumpAndSettle can settle without infinite animations.
      extraOverrides: [
        usingRealPipelineProvider.overrideWithValue(true),
        modelReadyProvider.overrideWith(() => _AlwaysReadyModelController()),
      ],
      child: DashboardScreen(onOpenBucket: (_) {}, onCapture: () {}),
    ));
    await tester.pumpAndSettle();

    expect(find.text('brain-fahrt'), findsOneWidget);
    expect(find.text('Search your thoughts'), findsOneWidget);

    // Seed buckets.
    expect(find.text('General'), findsOneWidget);
    expect(find.text('Shopping'), findsOneWidget);
    expect(find.text('Ideas'), findsOneWidget);

    // Counts: General = 3 project notes; shopping/todos/ideas show "N left".
    expect(find.text('3 notes'), findsOneWidget);
    expect(find.text('2 left'), findsWidgets);

    // A seeded summary appears as a preview line.
    expect(
      find.text('Run timer keeps counting after a job is killed'),
      findsOneWidget,
    );

    // Capture FAB present; no Unsorted card (no null-bucket seeds).
    expect(find.byType(CaptureFab), findsOneWidget);
    expect(find.text('Unsorted'), findsNothing);

    // No demo banner when real pipeline is active.
    expect(find.textContaining('Demo mode'), findsNothing);

    // Close DB before ProviderScope disposal to avoid Drift scheduling a
    // stream-close timer that the framework detects as "pending" at teardown.
    await db.close();
    await tester.pumpWidget(const SizedBox());
    await tester.pumpAndSettle();
  });

  testWidgets('demo banner visible when real pipeline is absent', (tester) async {
    tester.view.physicalSize = const Size(1200, 3200);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final db = await seededMemoryDb();

    // Default testHarness does NOT override usingRealPipelineProvider, so it
    // stays false → demo banner is shown, model-load bar is hidden.
    await tester.pumpWidget(testHarness(
      db: db,
      child: DashboardScreen(onOpenBucket: (_) {}, onCapture: () {}),
    ));
    await tester.pumpAndSettle();

    expect(find.textContaining('Demo mode'), findsOneWidget);
    expect(find.textContaining('Loading AI model'), findsNothing);

    await db.close();
    await tester.pumpWidget(const SizedBox());
    await tester.pumpAndSettle();
  });
}
