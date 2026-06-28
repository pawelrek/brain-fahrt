/// Capture controller — Riverpod 3 Notifier that drives the capture pipeline,
/// holds the result, files the item, and exposes the live [CaptureState].
library;

import 'dart:async';

import 'package:drift/drift.dart' show Value;
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/log/app_log.dart';
import '../../core/util/id.dart';
import '../../data/db/database.dart';
import '../../data/providers.dart';
import '../../pipeline/capture_pipeline.dart';
import '../../pipeline/simulated_pipeline.dart';
import 'capture_state.dart';

// ── Providers ─────────────────────────────────────────────────────────────────

/// Provides the active [CapturePipeline]. Override in M2–M4 for a real
/// on-device pipeline; the simulated pipeline backs the prototype.
final capturePipelineProvider = Provider<CapturePipeline>((ref) {
  final pipeline = SimulatedPipeline();
  ref.onDispose(pipeline.dispose);
  return pipeline;
});

/// How long the result card stays visible before the item is filed and the
/// overlay dismisses. Overridable so tests can collapse it to [Duration.zero].
final captureResultHoldProvider = Provider<Duration>(
  (ref) => const Duration(milliseconds: 900),
);

/// How long a PROVISIONAL result (filed right after ASR; routing continues in
/// background) holds before filing — the brief "Saved" beat. Overridable so
/// tests can collapse it to [Duration.zero].
final provisionalHoldProvider = Provider<Duration>(
  (ref) => const Duration(milliseconds: 450),
);

final captureControllerProvider =
    NotifierProvider<CaptureController, CaptureState>(CaptureController.new);

// ── Controller ────────────────────────────────────────────────────────────────

/// Drives the capture pipeline and exposes the live [CaptureState].
///
/// [start] subscribes to the pipeline and mirrors its states. When the pipeline
/// emits a [CaptureResult] the controller holds it for the result-hold duration,
/// then files the item exactly once (guarded) and returns to [CaptureIdle] — the
/// overlay watches for that Idle transition to dismiss.
class CaptureController extends Notifier<CaptureState> {
  StreamSubscription<CaptureState>? _sub;
  Timer? _resultTimer;
  bool _committed = false;
  bool _disposed = false;

  @override
  CaptureState build() {
    ref.onDispose(() {
      _disposed = true;
      _teardown();
    });
    return const CaptureIdle();
  }

  /// Begin a new capture session. No-op if one is already running.
  void start() {
    if (state is! CaptureIdle) return;
    _teardown();
    _committed = false;
    final pipeline = ref.read(capturePipelineProvider);
    // onDone is intentionally ignored: the result hold drives the return to
    // Idle, not stream closure (the pipeline closes right after the result).
    _sub = pipeline.run().listen(_onState, onError: (_) => _reset());
  }

  void _onState(CaptureState s) {
    state = s;
    if (s is CaptureResult) {
      _resultTimer?.cancel();
      // Provisional results (filed right after ASR, routing in background)
      // only hold for the brief "Saved" beat. commitNow() works during either
      // hold — both paths arm _resultTimer.
      final hold = ref.read(
          s.provisional ? provisionalHoldProvider : captureResultHoldProvider);
      _resultTimer = Timer(hold, () => _commitAndFinish(s));
    }
  }

  /// Signal manual stop while listening.
  void stopManual() {
    if (state is CaptureListening) {
      ref.read(capturePipelineProvider).stop();
    }
  }

  /// Commit the held result immediately (tap-to-skip on the result card).
  ///
  /// Only acts when the current state is [CaptureResult] and the hold timer is
  /// still pending; cancels the timer and calls [_commitAndFinish] exactly once
  /// (the existing [_committed] guard remains the single source of idempotence).
  void commitNow() {
    final s = state;
    if (s is! CaptureResult || _resultTimer == null) return;
    _resultTimer!.cancel();
    _resultTimer = null;
    _commitAndFinish(s);
  }

  /// Abort the capture; resets to [CaptureIdle] without filing an item.
  void cancel() {
    // Unconditional: also aborts the pipeline if called mid-processing or from
    // an OS back-gesture, so the mic + native inference always get a stop signal.
    ref.read(capturePipelineProvider).cancel();
    _reset();
  }

  /// File the captured item (exactly once) and return to Idle.
  Future<void> _commitAndFinish(CaptureResult r) async {
    if (r.discarded) {
      // Silence / non-speech — show the brief card but create NO item.
      AppLog.instance.log('capture', 'discarded (silence) — no item filed');
    } else if (!_committed && !_disposed) {
      _committed = true;
      final id = newId();
      var inserted = false;
      try {
        await ref.read(databaseProvider).upsertItem(
              ItemsCompanion.insert(
                id: id,
                summary: r.summary,
                transcript: r.transcript,
                createdAt: DateTime.now().millisecondsSinceEpoch,
                bucketId: Value(r.bucketId),
                type: Value(r.type),
              ),
            );
        inserted = true;
        AppLog.instance.log('capture', 'filed item $id -> ${r.bucketId ?? "unsorted"}');
      } catch (e) {
        // The DB write failed — never wedge the overlay on the result screen;
        // fall through to Idle so it dismisses. Only THIS failure may re-arm
        // the commit guard: the item was not filed.
        AppLog.instance.log('capture', 'commit failed: $e', level: LogLevel.error);
        _committed = false;
      }
      if (inserted) {
        // Highlight is best-effort and must never re-arm the commit guard —
        // the item is already in the DB (a throw here previously reset
        // _committed after a successful insert, enabling a double-file).
        try {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (!_disposed) ref.read(newItemIdProvider.notifier).mark(id);
          });
        } catch (e) {
          AppLog.instance.log('capture', 'highlight skipped: $e', level: LogLevel.warn);
        }
        if (r.provisional && !_disposed) {
          // Background routing continues; patch the filed row when it lands.
          unawaited(_applyPatchWhenReady(id, r.summary, r.bucketId));
        }
      }
    }
    if (!_disposed) state = const CaptureIdle();
  }

  /// Awaits the pipeline's background routing result and patches the
  /// provisionally-filed row (summary/type; bucket only if still Unsorted,
  /// whole patch skipped if the user moved the item — enforced by
  /// [AppDatabase.applyRoutePatch]), then re-fires the landing highlight so
  /// the board shows the move. Never throws.
  Future<void> _applyPatchWhenReady(
      String id, String expectedSummary, String? expectedBucketId) async {
    // Read providers BEFORE the first await: ref must not be used after an
    // async gap (the notifier may be disposed/rebuilt while we wait).
    final db = ref.read(databaseProvider);
    final newItem = ref.read(newItemIdProvider.notifier);
    try {
      final patch = await ref
          .read(capturePipelineProvider)
          .pendingRoute
          .timeout(const Duration(seconds: 60), onTimeout: () => null);
      if (patch == null || _disposed) return;
      final applied = await db.applyRoutePatch(
        id,
        expectedSummary: expectedSummary,
        expectedBucketId: expectedBucketId,
        summary: patch.summary,
        bucketId: patch.bucketId,
        type: patch.type,
      );
      // Direct mark() is safe here: this runs from a future continuation
      // (never during build), unlike the post-frame wrap in _commitAndFinish
      // which exists for a different timing reason.
      if (applied && !_disposed) newItem.mark(id);
    } catch (e) {
      AppLog.instance.log('capture', 'route patch failed: $e',
          level: LogLevel.warn);
    }
  }

  void _reset() {
    _teardown();
    if (!_disposed) state = const CaptureIdle();
  }

  void _teardown() {
    _sub?.cancel();
    _sub = null;
    _resultTimer?.cancel();
    _resultTimer = null;
  }
}
