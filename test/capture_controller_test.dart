import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:slop/data/db/database.dart';
import 'package:slop/data/models/enums.dart';
import 'package:slop/data/providers.dart';
import 'package:slop/features/capture/capture_controller.dart';
import 'package:slop/features/capture/capture_state.dart';
import 'package:slop/pipeline/capture_pipeline.dart';
import 'package:slop/pipeline/simulated_pipeline.dart';

import 'helpers.dart';

ProviderContainer _container(AppDatabase db, {Duration hold = Duration.zero}) =>
    ProviderContainer(overrides: [
      databaseProvider.overrideWithValue(db),
      // Fresh per-instance pipeline (cursor 0 → capture #1 = general/improvement)
      // and instant durations + configurable result-hold for deterministic tests.
      capturePipelineProvider.overrideWithValue(SimulatedPipeline(
        charInterval: Duration.zero,
        heardDelay: Duration.zero,
        transcribingDelay: Duration.zero,
        sortingDelay: Duration.zero,
      )),
      captureResultHoldProvider.overrideWithValue(hold),
    ]);

/// Stream-controller-driven fake pipeline for the provisional/patch path.
class _FakePipeline implements CapturePipeline {
  final StreamController<CaptureState> events = StreamController<CaptureState>();

  /// Mutable so tests can REPLACE it (simulating a second run() installing a
  /// fresh pending completer) while a previously-captured future is awaited.
  Completer<RoutePatch?> patchCompleter = Completer<RoutePatch?>();

  @override
  Future<RoutePatch?> get pendingRoute => patchCompleter.future;

  @override
  Stream<CaptureState> run() => events.stream;

  @override
  void stop() {}

  @override
  void cancel() {}

  @override
  void dispose() {}
}

ProviderContainer _fakeContainer(AppDatabase db, _FakePipeline pipeline) =>
    ProviderContainer(overrides: [
      databaseProvider.overrideWithValue(db),
      capturePipelineProvider.overrideWithValue(pipeline),
      captureResultHoldProvider.overrideWithValue(Duration.zero),
      provisionalHoldProvider.overrideWithValue(Duration.zero),
    ]);

void main() {
  test('capture files exactly one item', () async {
    final db = await seededMemoryDb();
    addTearDown(db.close);
    final before = (await db.watchItems().first).length;

    final container = _container(db);
    addTearDown(container.dispose);

    final controller = container.read(captureControllerProvider.notifier);
    controller.start();

    // Let the listening stream spin up, then stop manually (skips auto-stop).
    await Future<void>.delayed(const Duration(milliseconds: 60));
    expect(container.read(captureControllerProvider), isA<CaptureListening>());
    controller.stopManual();

    // Instant processing + zero hold → committed shortly after.
    await Future<void>.delayed(const Duration(milliseconds: 200));

    final items = await db.watchItems().first;
    expect(items.length, before + 1);

    // First scripted capture (cursor 0) routes to General / improvement.
    final allItems = await db.watchItems().first;
    final filed = allItems.firstWhere(
      (i) => i.summary == 'Add a dark mode toggle to settings',
    );
    expect(filed.bucketId, 'general');

    expect(container.read(captureControllerProvider), isA<CaptureIdle>());
  });

  test('cancel during listening files nothing', () async {
    final db = await seededMemoryDb();
    addTearDown(db.close);
    final before = (await db.watchItems().first).length;

    final container = _container(db);
    addTearDown(container.dispose);

    final controller = container.read(captureControllerProvider.notifier);
    controller.start();
    await Future<void>.delayed(const Duration(milliseconds: 60));
    controller.cancel();
    await Future<void>.delayed(const Duration(milliseconds: 100));

    expect(container.read(captureControllerProvider), isA<CaptureIdle>());
    expect((await db.watchItems().first).length, before);
  });

  test('commitNow() skips the hold timer and files exactly once', () async {
    final db = await seededMemoryDb();
    addTearDown(db.close);
    final before = (await db.watchItems().first).length;

    // Use a non-zero hold (200 ms) so we can call commitNow() while the
    // timer is still pending — proving the skip behaviour.
    final container = _container(db, hold: const Duration(milliseconds: 200));
    addTearDown(container.dispose);

    final controller = container.read(captureControllerProvider.notifier);
    controller.start();

    await Future<void>.delayed(const Duration(milliseconds: 60));
    expect(container.read(captureControllerProvider), isA<CaptureListening>());
    controller.stopManual();

    // Wait for the result state to arrive (instant processing delays).
    await Future<void>.delayed(const Duration(milliseconds: 60));
    expect(container.read(captureControllerProvider), isA<CaptureResult>());

    // Skip the remaining 200 ms hold immediately.
    controller.commitNow();

    // Give the async filing a moment to complete.
    await Future<void>.delayed(const Duration(milliseconds: 200));

    // State is Idle and exactly one item was filed.
    expect(container.read(captureControllerProvider), isA<CaptureIdle>());
    final items = await db.watchItems().first;
    expect(items.length, before + 1);

    // Calling commitNow() again after commit is a no-op (idempotence guard).
    controller.commitNow();
    await Future<void>.delayed(const Duration(milliseconds: 50));
    expect((await db.watchItems().first).length, before + 1);
  });

  test('provisional result files immediately; patch updates summary + type '
      'and re-marks the highlight', () async {
    final db = await seededMemoryDb();
    addTearDown(db.close);
    final before = (await db.watchItems().first).length;

    final pipeline = _FakePipeline();
    final container = _fakeContainer(db, pipeline);
    addTearDown(container.dispose);

    final controller = container.read(captureControllerProvider.notifier);
    controller.start();

    pipeline.events.add(const CaptureResult(
      provisional: true,
      summary: 'the build keeps failing',
      transcript: 'bug report for dev hub the build keeps failing',
      bucketId: null,
      type: null,
      filed: false,
    ));
    await pipeline.events.close();

    // Zero provisional hold → filed + back to Idle almost immediately.
    await Future<void>.delayed(const Duration(milliseconds: 100));
    expect(container.read(captureControllerProvider), isA<CaptureIdle>());

    var items = await db.watchItems().first;
    expect(items.length, before + 1);
    var row = items.firstWhere((i) => i.summary == 'the build keeps failing');
    expect(row.bucketId, isNull);
    expect(row.type, isNull);
    final id = row.id;

    // Background route lands → row patched (summary + bucket + type) and the
    // board highlight re-fires on the same id.
    pipeline.patchCompleter.complete(const RoutePatch(
      summary: 'the build keeps failing intermittently',
      bucketId: 'devhub',
      type: ItemType.bug,
    ));
    await Future<void>.delayed(const Duration(milliseconds: 100));

    items = await db.watchItems().first;
    row = items.firstWhere((i) => i.id == id);
    expect(row.summary, 'the build keeps failing intermittently');
    expect(row.bucketId, 'devhub');
    expect(row.type, ItemType.bug);
    expect(container.read(newItemIdProvider), id);
  });

  test('patch never moves an explicitly-filed provisional item '
      '(bucket only if null) but still updates summary + type', () async {
    final db = await seededMemoryDb();
    addTearDown(db.close);

    final pipeline = _FakePipeline();
    final container = _fakeContainer(db, pipeline);
    addTearDown(container.dispose);

    final controller = container.read(captureControllerProvider.notifier);
    controller.start();

    pipeline.events.add(const CaptureResult(
      provisional: true,
      summary: 'login button unresponsive',
      transcript: 'add to webapp the login button is unresponsive',
      bucketId: 'webapp', // explicit "to webapp" match
      type: null,
      filed: true,
    ));
    await pipeline.events.close();
    await Future<void>.delayed(const Duration(milliseconds: 100));

    var items = await db.watchItems().first;
    var row = items.firstWhere((i) => i.summary == 'login button unresponsive');
    expect(row.bucketId, 'webapp');
    final id = row.id;

    // The LLM disagrees on the bucket — that must NOT move the item.
    pipeline.patchCompleter.complete(const RoutePatch(
      summary: 'login button does nothing on tap',
      bucketId: 'general',
      type: ItemType.bug,
    ));
    await Future<void>.delayed(const Duration(milliseconds: 100));

    items = await db.watchItems().first;
    row = items.firstWhere((i) => i.id == id);
    expect(row.bucketId, 'webapp'); // explicit filing preserved
    expect(row.summary, 'login button does nothing on tap');
    expect(row.type, ItemType.bug);
  });

  test('patch future captured at commit time still patches its own row after '
      'a newer run replaced the pipeline pending completer', () async {
    final db = await seededMemoryDb();
    addTearDown(db.close);

    final pipeline = _FakePipeline();
    final container = _fakeContainer(db, pipeline);
    addTearDown(container.dispose);

    final controller = container.read(captureControllerProvider.notifier);
    controller.start();

    // Capture A files provisionally; the controller grabs pendingRoute (the
    // future of completer A) at commit time.
    pipeline.events.add(const CaptureResult(
      provisional: true,
      summary: 'capture a provisional',
      transcript: 'capture a transcript',
      bucketId: null,
      type: null,
      filed: false,
    ));
    await pipeline.events.close();
    await Future<void>.delayed(const Duration(milliseconds: 100));

    final id = (await db.watchItems().first)
        .firstWhere((i) => i.summary == 'capture a provisional')
        .id;

    // A second run starts before A's background route lands: the pipeline
    // installs a FRESH pending completer (run-local; replaces _pending).
    final completerA = pipeline.patchCompleter;
    pipeline.patchCompleter = Completer<RoutePatch?>();

    // A's route lands late — it must still resolve A's awaited future and
    // patch A's row (the old generation gate dropped exactly this patch).
    completerA.complete(const RoutePatch(
      summary: 'capture a routed',
      bucketId: 'devhub',
      type: ItemType.improvement,
    ));
    await Future<void>.delayed(const Duration(milliseconds: 100));

    final row = (await db.watchItems().first).firstWhere((i) => i.id == id);
    expect(row.summary, 'capture a routed');
    expect(row.bucketId, 'devhub');
    expect(row.type, ItemType.improvement);
  });

  test('null patch leaves the provisional row unchanged', () async {
    final db = await seededMemoryDb();
    addTearDown(db.close);

    final pipeline = _FakePipeline();
    final container = _fakeContainer(db, pipeline);
    addTearDown(container.dispose);

    final controller = container.read(captureControllerProvider.notifier);
    controller.start();

    pipeline.events.add(const CaptureResult(
      provisional: true,
      summary: 'some half heard thought',
      transcript: 'some half heard thought',
      bucketId: null,
      type: null,
      filed: false,
    ));
    await pipeline.events.close();
    await Future<void>.delayed(const Duration(milliseconds: 100));

    var items = await db.watchItems().first;
    var row = items.firstWhere((i) => i.summary == 'some half heard thought');
    final id = row.id;

    // Background routing failed/cancelled → null patch → no write.
    pipeline.patchCompleter.complete(null);
    await Future<void>.delayed(const Duration(milliseconds: 100));

    items = await db.watchItems().first;
    row = items.firstWhere((i) => i.id == id);
    expect(row.summary, 'some half heard thought');
    expect(row.bucketId, isNull);
    expect(row.type, isNull);
  });
}
