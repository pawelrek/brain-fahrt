/// Factory helper: builds a [capturePipelineProvider] override wired to the
/// real on-device ML pipeline.
library;

import 'dart:async';

import 'package:flutter_riverpod/misc.dart';

import '../../core/log/app_log.dart';
import '../../data/db/database.dart';
import '../../data/models/enums.dart';
import '../../data/providers.dart';
import '../../features/capture/capture_controller.dart';
import 'mic_source.dart';
import 'model_registry.dart';
import 'real_capture_pipeline.dart';
import 'router.dart';
import 'stt_registry.dart';
import 'transcriber.dart';

/// Max example notes per bucket fed to the router for content-aware routing.
const int _examplesPerBucket = 3;

/// Returns a provider override that wires [RealCapturePipeline] into
/// [capturePipelineProvider], reading the live bucket list + their recent notes
/// at route-time.
///
/// [initialModel] is the persisted LLM model preloaded in main() before runApp.
/// The Router is seeded ONCE via ref.read (NOT ref.watch — watching would rebuild
/// the pipeline and leak the native context on every flip). Model switches go
/// through [RealCapturePipeline.switchModel] via a ref.listen on
/// [selectedModelProvider].
///
/// Usage in main():
///   overrides: [
///     databaseProvider.overrideWithValue(db),
///     realPipelineOverride(db, initialModel: persistedModel),
///   ]
Override realPipelineOverride(AppDatabase db,
    {LlmModel initialModel = LlmModel.qwen3_17b}) {
  return capturePipelineProvider.overrideWith((ref) {
    // Live caches kept in sync with the DB so the synchronous bucketsProvider()
    // callback can build content-aware BucketInfos at route-time.
    // Instance-local (not module-level) so multiple provider containers or
    // widget-test runs cannot share/contaminate each other's cache.
    List<Bucket> cachedBuckets = [];
    List<Item> cachedItems = [];

    // Builds the router's [BucketInfo] list from the live caches, attaching
    // each bucket's most-recent note summaries as routing examples.
    List<BucketInfo> buildBucketInfos() {
      return cachedBuckets.map((b) {
        final mine = cachedItems.where((i) => i.bucketId == b.id).toList()
          ..sort((a, x) => x.createdAt.compareTo(a.createdAt));
        final examples = [
          for (final i in mine.take(_examplesPerBucket)) i.summary,
        ];
        return BucketInfo(
          id: b.id,
          name: b.name,
          isProject: b.shape == BucketShape.project,
          examples: examples,
          description: b.description,
          keywords: b.keywords,
        );
      }).toList();
    }

    // Seed Router ONCE with the persisted model (ref.read, not ref.watch).
    // Prefer the preloaded initialModel over a potential async race in
    // SelectedModelController.build.
    final effectiveModel =
        initialModel != LlmModel.qwen3_17b ? initialModel : ref.read(selectedModelProvider);
    final pipeline = RealCapturePipeline(
      transcriber: Transcriber(),
      router: Router(family: effectiveModel.family),
      mic: MicSource(),
      // Synchronous: returns the last-known buckets + their recent notes.
      // Drift streams keep the caches warm; by the time the user finishes
      // speaking they reflect the current board.
      bucketsProvider: buildBucketInfos,
      // Live routing knobs read at route-time (ref.read inside the closure, so
      // Settings toggles take effect without rebuilding the pipeline).
      tuningProvider: () => RouterTuning(
        greedy: ref.read(greedyDecodingProvider),
      ),
      // Recent user corrections → few-shot examples, fetched at route-time.
      correctionsProvider: () async {
        final rows = await db.recentCorrections(8);
        return [
          for (final c in rows)
            CorrectionExample(note: c.note, bucketId: c.bucketId),
        ];
      },
    );
    // Set the pipeline's active model to match the seeded value.
    pipeline.setActiveModel(effectiveModel);
    // Align the active STT (Whisper) variant with the seeded selection. The
    // provider is seeded synchronously via override in main(), so this read is
    // deterministic (no async race).
    pipeline.setActiveSttModel(ref.read(selectedSttModelProvider));

    // Local disposed flag: the unawaited warm-up/switch continuations below
    // must not ref.read after this provider is disposed (hot restart /
    // container teardown) — that throws and the error would be swallowed
    // into an unhandled-async log instead of a clean no-op.
    var providerDisposed = false;

    // Forward raw startup-stage events to the progress controller (drives the
    // dashboard's staged 0→100% bar). Wired BEFORE warm-up so no event is lost.
    pipeline.onStartupEvent = (e) {
      if (!providerDisposed) {
        ref.read(startupProgressProvider.notifier).handle(e);
      }
    };

    // Attach the Drift caches FIRST, then warm up after the first bucket
    // snapshot: warm-up builds the REAL Categories block (S4) from
    // cachedBuckets — firing it before the first snapshot would fall back to
    // dummy lines and forfeit the warmed-prefix win for the first real route.
    final subBuckets =
        db.watchBuckets().listen((rows) => cachedBuckets = rows);
    final subItems = db.watchItems().listen((rows) => cachedItems = rows);

    // Eager warmup: load Whisper + Qwen now (at app startup) so the ~8s Qwen
    // load is done by the time the user records, instead of stalling the first
    // capture's post-record step. Fire-and-forget; the lazy path is the fallback.
    // Gated by optimisticLoadingProvider: when Off, the user sees a "Loading AI"
    // step in the capture overlay instead of warming up at startup.
    if (ref.read(optimisticLoadingProvider)) {
      unawaited(db.watchBuckets().first.then((rows) {
        cachedBuckets = rows; // guarantee the snapshot is in before warm-up
        return pipeline.warmUp();
      }).whenComplete(() {
        if (providerDisposed) return; // ref is dead — clean no-op
        ref.read(modelReadyProvider.notifier).markReady();
      }));
    } else {
      // No startup warmup — the in-capture "Loading AI" step covers loading.
      ref.read(modelReadyProvider.notifier).markReady();
    }

    // Listen for model-selection changes from Settings and drive switchModel.
    // Uses ref.listen (not ref.watch) so the pipeline is NOT rebuilt; the model
    // is swapped in-place via switchModel → reinit (unload + load).
    ref.listen<LlmModel>(selectedModelProvider, (prev, next) {
      if (prev == next) return;
      AppLog.instance.log('llm', 'model switch: ${prev?.name} -> ${next.name}');
      // Reset the load indicator so the dashboard shows "Loading AI…" during switch.
      ref.read(modelReadyProvider.notifier).reset();
      unawaited(
        pipeline.switchModel(next).then((_) {
          if (providerDisposed) return;
          ref.read(modelReadyProvider.notifier).markReady();
        }).catchError((Object e, StackTrace s) {
          AppLog.instance.log('llm', 'switchModel failed: $e', level: LogLevel.error);
          if (providerDisposed) return;
          // The pipeline reverted to the previous model (revert-on-failure) —
          // reflect that in the selection + persistence too, or the UI and
          // the next launch would disagree with the actually-loaded model.
          if (prev != null) {
            ref.read(selectedModelProvider.notifier).set(prev);
          }
          // Mark ready anyway to unblock the UI.
          ref.read(modelReadyProvider.notifier).markReady();
        }),
      );
    });

    // Listen for STT-model changes from Settings and drive switchSttModel. Like
    // the LLM listener: ref.listen (not watch) so the pipeline is swapped
    // in-place, not rebuilt. The Whisper reload is quick (~1-2s); modelReady is
    // reset so the dashboard shows "Loading AI…" until the new recognizer is up.
    ref.listen<SttModel>(selectedSttModelProvider, (prev, next) {
      if (prev == next) return;
      AppLog.instance.log('asr', 'stt switch: ${prev?.name} -> ${next.name}');
      ref.read(modelReadyProvider.notifier).reset();
      unawaited(
        pipeline.switchSttModel(next).then((_) {
          if (providerDisposed) return;
          ref.read(modelReadyProvider.notifier).markReady();
        }).catchError((Object e, StackTrace s) {
          AppLog.instance.log('asr', 'switchSttModel failed: $e', level: LogLevel.error);
          if (providerDisposed) return;
          // The pipeline reverted to the previous STT model — reflect that in
          // the selection + persistence so UI and next launch agree.
          if (prev != null) {
            ref.read(selectedSttModelProvider.notifier).set(prev);
          }
          ref.read(modelReadyProvider.notifier).markReady();
        }),
      );
    });

    ref.onDispose(() {
      providerDisposed = true;
      subBuckets.cancel();
      subItems.cancel();
      pipeline.dispose();
    });

    return pipeline;
  });
}
