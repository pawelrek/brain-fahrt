import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:slop/app/app.dart';
import 'package:slop/data/db/database.dart';
import 'package:slop/data/providers.dart';
import 'package:slop/data/seed.dart';
import 'package:slop/features/capture/capture_controller.dart';
import 'package:slop/features/dashboard/capture_fab.dart';
import 'package:slop/pipeline/simulated_pipeline.dart';

/// On-device (slop_flagship) end-to-end smoke: tap the red dot → record →
/// the simulated pipeline files a note → the card lands on the dashboard.
///
/// Uses timed `pump`s (NOT pumpAndSettle): the board pulse / waveform repeat
/// forever, so the tree never "settles".
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('red dot → capture → card lands', (tester) async {
    final db = AppDatabase(NativeDatabase.memory());
    await seedDatabaseIfEmpty(db);

    await tester.pumpWidget(ProviderScope(
      overrides: [
        databaseProvider.overrideWithValue(db),
        capturePipelineProvider.overrideWithValue(
          SimulatedPipeline(
            charInterval: Duration.zero,
            heardDelay: Duration.zero,
            transcribingDelay: Duration.zero,
            sortingDelay: Duration.zero,
          ),
        ),
      ],
      child: const DotApp(),
    ));

    // Let the board stream emit + lay out.
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('Dot'), findsOneWidget);
    expect(find.text('General'), findsOneWidget);

    // Open capture.
    await tester.tap(find.byType(CaptureFab));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));
    expect(find.text('Recording'), findsOneWidget);

    // Stop → processing (instant) → result.
    await tester.tap(find.text('Stop'));
    await tester.pump(const Duration(milliseconds: 200));
    expect(find.text('FILED'), findsOneWidget);

    // Result hold → commit → dismiss.
    await tester.pump(const Duration(milliseconds: 1500));
    await tester.pump(const Duration(milliseconds: 400));

    // New general note (cursor 0) is now on the board.
    expect(
      find.text('Add a dark mode toggle to settings'),
      findsOneWidget,
    );
  });
}
