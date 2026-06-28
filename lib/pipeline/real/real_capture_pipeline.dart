/// Real on-device capture pipeline: mic → Whisper → Qwen2.5 routing.
library;

import 'dart:async';

import '../../core/log/app_log.dart';
import '../../features/capture/capture_state.dart';
import '../capture_pipeline.dart';
import 'mic_source.dart';
import 'model_paths.dart';
import 'model_registry.dart';
import 'router.dart';
import 'startup_progress.dart';
import 'stt_registry.dart';
import 'transcriber.dart';

/// Full on-device pipeline backed by sherpa-onnx Whisper + fllama Qwen2.5.
///
/// Lifecycle:
///   - [run] may be called repeatedly; models are lazy-initialised once.
///   - [stop] signals end-of-recording; kicks off transcription + routing.
///   - [cancel] aborts without producing a result.
///   - [dispose] releases all native resources.
class RealCapturePipeline implements CapturePipeline {
  RealCapturePipeline({
    required this.transcriber,
    required this.router,
    required this.mic,
    required this.bucketsProvider,
    this.tuningProvider,
    this.correctionsProvider,
  }) {
    // S4: warm-up prefills the REAL Categories block (not dummy lines), so the
    // static prompt prefix is the same bytes the first real route will use.
    router.warmBucketsProvider = bucketsProvider;
    // Forward the router's startup-stage events (LLM load/warm) alongside the
    // pipeline's own (Whisper load) to whoever wires [onStartupEvent].
    router.onStartupEvent = (e) => onStartupEvent?.call(e);
  }

  /// Raw startup-stage events (Whisper load, LLM load progress, warm-up).
  /// Set by the provider layer to drive the dashboard's staged progress bar.
  void Function(StartupEvent)? onStartupEvent;

  final Transcriber transcriber;
  final Router router;
  final MicSource mic;

  /// Returns the current bucket list at route-time (called lazily inside stop).
  final List<BucketInfo> Function() bucketsProvider;

  /// Live routing knobs (Settings), read at route-time so toggles apply without
  /// a restart. Null → defaults.
  final RouterTuning Function()? tuningProvider;

  /// Recent user corrections as few-shot examples, fetched at route-time.
  final Future<List<CorrectionExample>> Function()? correctionsProvider;

  // ── lazy-init state ────────────────────────────────────────────────────────
  bool _initialized = false;
  bool _initializing = false;
  bool _transcriberReady = false;
  bool _transcriberInitializing = false;
  bool _routerReady = false;
  bool _routerInitializing = false;
  ModelPaths? _cachedPaths;

  /// The currently active model (tracked so switchModel knows its gguf name).
  LlmModel _activeModel = LlmModel.qwen3_17b;

  /// The currently active STT (Whisper) model (tracked so switchSttModel knows
  /// which files to load and the transcriber init resolves the right paths).
  SttModel _activeSttModel = SttModel.smallMultilingual;

  // ── per-run state ──────────────────────────────────────────────────────────
  StreamController<CaptureState>? _controller;
  Timer? _tickTimer;
  bool _stopped = false;
  bool _cancelled = false;
  bool _running = false;

  /// Background routing result for the most recent provisional run. Null when
  /// there is nothing to patch (reset at every [run] start; the garbage and
  /// error paths never install one).
  Completer<RoutePatch?>? _pending;

  /// Set the active model without triggering a reinit (called at construction
  /// time from the provider to align [_activeModel] with the seeded value).
  void setActiveModel(LlmModel model) => _activeModel = model;

  /// Set the active STT model without triggering a reinit (called at construction
  /// time from the provider to align [_activeSttModel] with the seeded value).
  void setActiveSttModel(SttModel model) => _activeSttModel = model;

  // ── Router lifecycle queue ─────────────────────────────────────────────────
  // warmUp / switchModel / background routing all touch the SAME native
  // context + the _routerReady init flags. A background route that has not
  // yet reached _ensureRouterReady() is not covered by the Router's
  // completion chain, so a concurrent switchModel could double-init or
  // release the context under it. Everything router-lifecycle-shaped is
  // therefore serialized FIFO here.
  Future<void> _routerLifecycle = Future.value();

  Future<T> _serializedOnRouter<T>(Future<T> Function() work) {
    final run = _routerLifecycle.then((_) => work());
    _routerLifecycle = run.then<void>((_) {}, onError: (_) {});
    return run;
  }

  /// Eagerly load the models (Whisper + Qwen) in the background so the ~8s Qwen
  /// load happens at app startup instead of blocking the first capture's
  /// post-record step (which otherwise *looks* like slow transcription). Safe to
  /// call repeatedly; errors are swallowed — the lazy path retries on first use.
  Future<void> warmUp() => _serializedOnRouter(() async {
        if (_pipelineDisposed) return; // queued behind a teardown
        try {
          await _ensureInitialized();
          await router.warmUp();
        } catch (e) {
          AppLog.instance.log('llm', 'warmUp failed (will retry lazily): $e',
              level: LogLevel.warn);
        }
      });

  /// Unload the current model from RAM then load [model].
  /// Called by [real_pipeline_provider] when [selectedModelProvider] changes.
  /// Goes through [router.reinit] which calls [_stopAndRelease] (unload) then
  /// [init] (load), so only ONE model is ever resident in RAM.
  /// Serialized on the lifecycle queue: a pending background route fully
  /// finishes (init + route + patch-complete) before the switch proceeds.
  Future<void> switchModel(LlmModel model) =>
      _serializedOnRouter(() => _switchModelImpl(model));

  Future<void> _switchModelImpl(LlmModel model) async {
    if (_pipelineDisposed) return; // queued behind a teardown — never re-init
    if (model == _activeModel && _routerReady) return; // already loaded
    if (_running) cancel();

    // Ensure transcriber is ready (so _cachedPaths is populated).
    await _ensureTranscriberReady();

    final previous = _activeModel;
    final paths = await ModelPaths.resolve(
        qwenGgufName: model.gguf, sttModel: _activeSttModel);

    // Reset router-ready flags so the new init is treated as fresh.
    _routerReady = false;
    _initialized = false;

    try {
      await router.reinit(paths, family: model.family);
      _activeModel = model;
      _cachedPaths = paths;
      _routerReady = true;
      _initialized = _transcriberReady;
      AppLog.instance.log('llm', 'switchModel: loaded ${model.gguf}');
    } catch (e) {
      // The new model failed to load (e.g. an architecture this llama.cpp
      // build doesn't support). reinit already unloaded the old one, so the
      // router has no context — REVERT to the previous model so routing keeps
      // working instead of bricking with "Failed to initialize context".
      AppLog.instance.log(
        'llm',
        'switchModel FAILED for ${model.gguf} ($e) — reverting to ${previous.gguf}',
        level: LogLevel.error,
      );
      final prevPaths = await ModelPaths.resolve(
          qwenGgufName: previous.gguf, sttModel: _activeSttModel);
      await router.reinit(prevPaths, family: previous.family);
      _activeModel = previous;
      _cachedPaths = prevPaths;
      _routerReady = true;
      _initialized = _transcriberReady;
      rethrow; // let the provider surface the failure (UI can revert the pick)
    }
  }

  /// Swap the STT (Whisper) model in place: dispose the current transcriber and
  /// re-init it with [model]'s files. Serialized on the router lifecycle queue
  /// so it cannot race a warm-up / LLM switch / background route that also
  /// touches the transcriber init flags. The router (LLM) is untouched.
  Future<void> switchSttModel(SttModel model) =>
      _serializedOnRouter(() => _switchSttModelImpl(model));

  Future<void> _switchSttModelImpl(SttModel model) async {
    if (_pipelineDisposed) return; // queued behind a teardown — never re-init
    if (model == _activeSttModel && _transcriberReady) return; // already loaded
    if (_running) cancel(); // don't swap the recognizer mid-capture

    final previous = _activeSttModel;
    final paths = await ModelPaths.resolve(
        qwenGgufName: _activeModel.gguf, sttModel: model);

    _transcriberReady = false;
    try {
      transcriber.dispose(); // release the old native recognizer first
      await transcriber.init(paths);
      _activeSttModel = model;
      _cachedPaths = paths;
      _transcriberReady = true;
      _initialized = _routerReady;
      AppLog.instance.log('asr', 'switchSttModel: loaded ${model.name}');
    } catch (e) {
      // The new variant failed to load — REVERT to the previous one so the app
      // keeps a working recognizer instead of bricking transcription.
      AppLog.instance.log(
        'asr',
        'switchSttModel FAILED for ${model.name} ($e) — reverting to ${previous.name}',
        level: LogLevel.error,
      );
      final prevPaths = await ModelPaths.resolve(
          qwenGgufName: _activeModel.gguf, sttModel: previous);
      transcriber.dispose();
      await transcriber.init(prevPaths);
      _activeSttModel = previous;
      _cachedPaths = prevPaths;
      _transcriberReady = true;
      _initialized = _routerReady;
      rethrow; // let the provider surface the failure (UI can revert the pick)
    }
  }

  // ── CapturePipeline ────────────────────────────────────────────────────────

  @override
  Future<RoutePatch?> get pendingRoute =>
      _pending?.future ?? Future.value(null);

  @override
  Stream<CaptureState> run() {
    _teardown();

    _pending = null; // deterministic: no patch unless THIS run installs one
    _stopped = false;
    _cancelled = false;
    _running = true;
    AppLog.instance.log('capture', 'capture session started');

    final ctrl = StreamController<CaptureState>();
    _controller = ctrl;

    unawaited(_startListening(ctrl));

    return ctrl.stream;
  }

  @override
  void stop() {
    if (_stopped || _cancelled || !_running) return;
    _stopped = true;
    _tickTimer?.cancel();
    _tickTimer = null;

    final ctrl = _controller;
    if (ctrl == null || ctrl.isClosed) return;

    ctrl.add(const CaptureHeard());
    unawaited(_runPostCapture(ctrl));
  }

  @override
  void cancel() {
    if (_cancelled) return;
    _cancelled = true;
    _running = false;
    mic.cancel();
    _teardown();
  }

  @override
  void dispose() {
    // Flag FIRST: queued lifecycle work (a background route that has not yet
    // entered router.route, a pending switchModel) checks this at entry and
    // bails instead of re-initing a context after teardown (leak) or routing
    // into a released one. The pending patch is resolved to null so a
    // controller awaiting it returns promptly instead of timing out.
    _pipelineDisposed = true;
    final pending = _pending;
    if (pending != null && !pending.isCompleted) pending.complete(null);
    cancel();
    transcriber.dispose();
    router.dispose();
    // mic.dispose() is async; unawaited here to keep dispose() synchronous.
    // The caller (ref.onDispose) cannot await, and a brief async teardown is
    // safe because cancel() already stops all recording before this point.
    unawaited(mic.dispose());
  }

  /// True once [dispose] ran; queued router-lifecycle work must not start.
  bool _pipelineDisposed = false;

  // ── internals ──────────────────────────────────────────────────────────────

  /// Phase 1: resolve model paths + init the transcriber (Whisper). Idempotent.
  Future<void> _ensureTranscriberReady() async {
    if (_transcriberReady) return;
    if (_transcriberInitializing) {
      while (_transcriberInitializing) {
        if (_cancelled) throw StateError('Cancelled while waiting for transcriber init');
        await Future<void>.delayed(const Duration(milliseconds: 50));
      }
      if (!_transcriberReady) {
        throw StateError('Transcriber initialization failed.');
      }
      return;
    }
    _transcriberInitializing = true;
    try {
      final paths = await ModelPaths.resolve(
          qwenGgufName: _activeModel.gguf, sttModel: _activeSttModel);
      _cachedPaths = paths;
      // Actual-init path only (the already-ready/waiting paths return above).
      onStartupEvent?.call(const WhisperLoadStart());
      await transcriber.init(paths);
      _transcriberReady = true;
      onStartupEvent?.call(const WhisperLoadDone());
    } finally {
      _transcriberInitializing = false;
    }
  }

  /// Phase 2: init the router (Qwen LLM) + reconcile mode fallback. Idempotent.
  Future<void> _ensureRouterReady() async {
    if (_routerReady) return;
    if (_routerInitializing) {
      while (_routerInitializing) {
        if (_cancelled) throw StateError('Cancelled while waiting for router init');
        await Future<void>.delayed(const Duration(milliseconds: 50));
      }
      if (!_routerReady) {
        throw StateError('Router initialization failed.');
      }
      return;
    }
    final paths = _cachedPaths;
    if (paths == null) {
      throw StateError('_ensureTranscriberReady() must be called first.');
    }
    _routerInitializing = true;
    try {
      await router.init(paths, family: _activeModel.family);
      _routerReady = true;
    } finally {
      _routerInitializing = false;
    }
  }

  /// Ensures both transcriber and router are initialised (concurrent calls
  /// collapse). Used by [warmUp] and [switchModel].
  Future<void> _ensureInitialized() async {
    if (_initialized) return;
    if (_initializing) {
      while (_initializing) {
        if (_cancelled) throw StateError('Cancelled while waiting for init');
        await Future<void>.delayed(const Duration(milliseconds: 50));
      }
      if (!_initialized) {
        throw StateError('Model initialization failed; cannot transcribe/route.');
      }
      return;
    }
    _initializing = true;
    try {
      await _ensureTranscriberReady();
      await _ensureRouterReady();
      _initialized = true;
    } finally {
      _initializing = false;
    }
  }

  /// Requests mic permission, starts streaming, and emits periodic
  /// [CaptureListening] ticks (~200 ms interval).
  Future<void> _startListening(StreamController<CaptureState> ctrl) async {
    try {
      // Check permission.
      final permitted = await mic.hasPermission();
      if (_cancelled || ctrl.isClosed) return;
      if (!permitted) {
        AppLog.instance.log(
          'capture',
          'Microphone permission denied',
          level: LogLevel.warn,
        );
        _emitError(ctrl, 'Microphone permission denied.');
        return;
      }
      AppLog.instance.log('capture', 'mic permission granted');

      // Start the mic stream.
      try {
        await mic.start();
      } catch (e) {
        AppLog.instance.log(
          'capture',
          'Failed to start microphone: $e',
          level: LogLevel.error,
        );
        if (!ctrl.isClosed) _emitError(ctrl, 'Failed to start microphone: $e');
        return;
      }

      if (_cancelled || ctrl.isClosed) {
        mic.cancel();
        return;
      }

      AppLog.instance.log('capture', 'Recording started');

      // Emit initial state then tick every 200 ms.
      ctrl.add(CaptureListening(partial: '', elapsed: mic.elapsed));

      _tickTimer = Timer.periodic(const Duration(milliseconds: 200), (_) {
        if (_cancelled || _stopped || ctrl.isClosed) {
          _tickTimer?.cancel();
          return;
        }
        if (mic.elapsed >= kMaxRecordDuration) {
          AppLog.instance.log(
            'capture',
            'auto-stop: hit ${kMaxRecordDuration.inSeconds}s record cap',
          );
          stop();
          return;
        }
        ctrl.add(CaptureListening(partial: '', elapsed: mic.elapsed));
      });
    } catch (e) {
      // Any unexpected throw (e.g. hasPermission platform-channel error) must
      // terminate the stream, or the overlay wedges in the listening state.
      AppLog.instance.log(
        'capture',
        'Unexpected capture error: $e',
        level: LogLevel.error,
      );
      if (!ctrl.isClosed) _emitError(ctrl, 'Capture error: $e');
    }
  }

  /// Runs after [stop]: stop mic → transcribe → route → emit result.
  Future<void> _runPostCapture(StreamController<CaptureState> ctrl) async {
    try {
      // Drain the mic.
      final samples = await mic.stop();
      AppLog.instance.log(
        'capture',
        'Recording stopped — duration ${mic.elapsed.inMilliseconds}ms, '
            '${samples.length} samples',
      );

      if (_cancelled || ctrl.isClosed) return;

      ctrl.add(const CaptureTranscribing());
      AppLog.instance.log('capture', 'Transcribe start');

      // Phase 1: ensure Whisper is ready (no-op on warm path).
      await _ensureTranscriberReady();

      if (_cancelled || ctrl.isClosed) return;

      final swAsr = Stopwatch()..start();
      final transcript = await transcriber.transcribe(samples);
      swAsr.stop();
      AppLog.instance.log(
        'asr',
        'asr_ms=${swAsr.elapsedMilliseconds} audio_ms=${mic.elapsed.inMilliseconds}',
      );

      if (_cancelled || ctrl.isClosed) return;

      // #12 — short-circuit garbage (silence / non-speech / too short) to
      // Unsorted BEFORE loading the LLM, so Qwen is never spun up for noise.
      if (isGarbageTranscript(transcript, mic.elapsed)) {
        AppLog.instance.log(
          'llm',
          'garbage transcript -> unsorted (skipped LLM): "${transcript.trim()}"',
        );
        ctrl
          ..add(
            CaptureResult(
              summary: transcript.trim().isEmpty
                  ? '(no speech detected)'
                  : transcript.trim(),
              transcript: transcript,
              bucketId: null,
              type: null,
              filed: false,
              discarded: true, // silence/non-speech -> no item is created
            ),
          )
          ..close();
        return;
      }

      // S8 optimistic filing: file NOW with a deterministic provisional
      // summary (explicit-target bucket or Unsorted) and run the LLM route in
      // the background — perceived stop→card latency becomes ≈ ASR time.
      final buckets = bucketsProvider();
      final match = Router.explicitTarget(transcript, buckets);
      final stripped = match != null
          ? stripRoutingPreamble(transcript, match)
          : transcript.trim();
      final provisionalSummary = cleanSummary(stripped, buckets);

      // Install a fresh pending completer BEFORE closing the stream (the
      // controller reads pendingRoute right after filing).
      final pending = Completer<RoutePatch?>();
      _pending = pending;
      final audioDuration = mic.elapsed;

      AppLog.instance.log(
        'capture',
        'provisional file -> bucket=${match?.bucketId ?? "unsorted"} '
            '(routing continues in background)',
      );

      ctrl
        ..add(
          CaptureResult(
            provisional: true,
            summary: provisionalSummary,
            transcript: transcript,
            // type stays null even for project buckets — the UNTYPED section
            // renders it until the patch arrives.
            bucketId: match?.bucketId,
            type: null,
            filed: match != null,
          ),
        )
        ..close();

      unawaited(_routeInBackground(
        pending,
        transcript,
        buckets,
        audioDuration,
      ));
    } catch (e) {
      AppLog.instance.log(
        'capture',
        'Processing error: $e',
        level: LogLevel.error,
      );
      if (!ctrl.isClosed) {
        _emitError(ctrl, 'Processing error: $e');
      }
    } finally {
      // Run-local guard: a stale post-capture (cancelled run still draining
      // ASR) must not clear _running for a NEWER run that started meanwhile —
      // that would make the new run ignore manual/auto stop and wedge in
      // Listening. ctrl is run-local; _controller is the current run's.
      if (identical(_controller, ctrl)) _running = false;
    }
  }

  /// Background continuation of [_runPostCapture]: lazily load the router
  /// (invisible — the overlay is already gone), run the LLM route, and
  /// complete [pending] with the patch. On ANY error/timeout it completes
  /// with null — [pendingRoute] never throws.
  ///
  /// [pending] is run-local and is ALWAYS completed here — no generation or
  /// shared-cancel gating: an older capture's controller awaits exactly this
  /// completer, so suppressing its completion would only starve that await
  /// into its 60s timeout. A late/cancelled patch is already guarded
  /// downstream (applyRoutePatch row guards + controller _disposed).
  /// Serialized on the router lifecycle queue (see [_serializedOnRouter]) so
  /// a concurrent [switchModel] can never init/release the context under the
  /// in-flight init+route of this background task.
  Future<void> _routeInBackground(
    Completer<RoutePatch?> pending,
    String transcript,
    List<BucketInfo> buckets,
    Duration audioDuration,
  ) =>
      _serializedOnRouter(() =>
          _routeInBackgroundImpl(pending, transcript, buckets, audioDuration));

  Future<void> _routeInBackgroundImpl(
    Completer<RoutePatch?> pending,
    String transcript,
    List<BucketInfo> buckets,
    Duration audioDuration,
  ) async {
    void completeOnce(RoutePatch? patch) {
      if (!pending.isCompleted) pending.complete(patch);
    }

    // Queued behind a teardown? Never touch the router again.
    if (_pipelineDisposed) {
      completeOnce(null);
      return;
    }

    try {
      // Lazy model load now happens here, invisible to the user.
      await _ensureRouterReady();

      // Read live Settings + recent corrections at route-time (not frozen at
      // construction) so toggles + learning apply without a restart.
      final tuning = tuningProvider?.call() ?? const RouterTuning();
      final corrections =
          (await correctionsProvider?.call()) ?? const <CorrectionExample>[];

      final swRoute = Stopwatch()..start();
      // Pass the ORIGINAL transcript: route() re-runs explicitTarget + strip
      // on its input, so its own deterministic layers stay authoritative —
      // passing pre-stripped text would risk double-stripping content.
      final result = await router.route(
        transcript: transcript.isNotEmpty ? transcript : '(no speech detected)',
        audioDuration: audioDuration,
        buckets: buckets,
        tuning: tuning,
        corrections: corrections,
      );
      swRoute.stop();
      AppLog.instance.log('llm', 'route_ms=${swRoute.elapsedMilliseconds}');

      AppLog.instance.log(
        'llm',
        'routed (background) -> bucket=${result.bucketId ?? "unsorted"} '
            'conf=${result.confidence} type=${result.type}',
      );
      completeOnce(RoutePatch(
        summary: result.summary,
        bucketId: result.bucketId,
        type: result.type,
      ));
    } catch (e) {
      AppLog.instance.log(
        'llm',
        'background route failed: $e',
        level: LogLevel.warn,
      );
      completeOnce(null);
    }
  }

  /// Emits a [CaptureResult] routed to Unsorted (safe error fallback).
  /// [discarded] is true so the controller shows the brief error card but does
  /// NOT file a todo item (e.g. "Microphone permission denied." stays ephemeral).
  void _emitError(StreamController<CaptureState> ctrl, String message) {
    if (ctrl.isClosed) return;
    ctrl
      ..add(
        CaptureResult(
          summary: message,
          transcript: '',
          bucketId: null,
          type: null,
          filed: false,
          discarded: true,
        ),
      )
      ..close();
    _running = false;
  }

  void _teardown() {
    _tickTimer?.cancel();
    _tickTimer = null;
    final ctrl = _controller;
    _controller = null;
    if (ctrl != null && !ctrl.isClosed) ctrl.close();
  }
}
