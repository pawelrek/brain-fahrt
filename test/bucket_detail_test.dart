import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:slop/features/bucket_detail/bucket_detail_screen.dart';

import 'helpers.dart';

void _noop() {}

void main() {
  testWidgets('project bucket shows Improvement/Bug/Issue sections', (tester) async {
    tester.view.physicalSize = const Size(1200, 3200);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final db = await seededMemoryDb();

    await tester.pumpWidget(testHarness(
      db: db,
      child: const BucketDetailScreen(bucketId: 'general', onBack: _noop),
    ));
    await tester.pumpAndSettle();

    expect(find.text('General'), findsOneWidget);
    expect(find.text('IMPROVEMENTS'), findsOneWidget);
    expect(find.text('BUGS'), findsOneWidget);
    expect(find.text('ISSUES'), findsOneWidget);
    expect(
      find.text('Run timer keeps counting after a job is killed'),
      findsOneWidget,
    );
    // UNTYPED section should not appear when all items have types.
    expect(find.text('UNTYPED'), findsNothing);

    // Close DB first so Drift's stream subscriptions cancel cleanly without
    // scheduling timers during ProviderScope disposal.
    await db.close();
    await tester.pumpWidget(const SizedBox());
    await tester.pumpAndSettle();
  });

  testWidgets('list bucket shows checkable items + "left" subtitle', (tester) async {
    tester.view.physicalSize = const Size(1200, 3200);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final db = await seededMemoryDb();

    await tester.pumpWidget(testHarness(
      db: db,
      child: const BucketDetailScreen(bucketId: 'shopping', onBack: _noop),
    ));
    await tester.pumpAndSettle();

    expect(find.text('Shopping'), findsOneWidget);
    expect(find.textContaining('left'), findsWidgets); // "2 of 3 left"
    expect(find.text('Olive oil and sea salt'), findsOneWidget);

    await db.close();
    await tester.pumpWidget(const SizedBox());
    await tester.pumpAndSettle();
  });

  testWidgets('unsorted bucket shows the "waiting to be filed" subtitle', (tester) async {
    final db = await seededMemoryDb();

    await tester.pumpWidget(testHarness(
      db: db,
      child: const BucketDetailScreen(bucketId: 'unsorted', onBack: _noop),
    ));
    await tester.pumpAndSettle();

    expect(find.text('Unsorted'), findsOneWidget);
    // No null-bucket seeds, so 0 waiting.
    expect(find.textContaining('waiting to be filed'), findsOneWidget);

    await db.close();
    await tester.pumpWidget(const SizedBox());
    await tester.pumpAndSettle();
  });
}
