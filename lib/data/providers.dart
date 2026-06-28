import 'dart:async';
import 'dart:math' as math;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../core/log/app_log.dart';
import '../pipeline/real/model_registry.dart';
import '../pipeline/real/startup_progress.dart';
import '../pipeline/real/stt_registry.dart';
import 'db/database.dart';
import 'models/enums.dart';

/// The app database. Overridden in `main()` with a seeded instance.
final databaseProvider = Provider<AppDatabase>(
  (ref) => throw UnimplementedError('databaseProvider must be overridden'),
);

/// Buckets in board order (reactive).
final bucketsProvider = StreamProvider<List<Bucket>>(
  (ref) => ref.watch(databaseProvider).watchBuckets(),
);

/// All items (reactive). Screens group/sort per card and section.
final itemsProvider = StreamProvider<List<Item>>(
  (ref) => ref.watch(databaseProvider).watchItems(),
);

/// Drives the "new item landed" highlight on the board. Set on commit; clears
/// itself after ~2.6s (the handover's `dotGlow` window).
class NewItemController extends Notifier<String?> {
  Timer? _timer;

  @override
  String? build() {
    ref.onDispose(() => _timer?.cancel());
    return null;
  }

  void mark(String itemId) {
    state = itemId;
    _timer?.cancel();
    _timer = Timer(const Duration(milliseconds: 2600), () {
      if (state == itemId) state = null;
    });
  }
}

final newItemIdProvider = NotifierProvider<NewItemController, String?>(
  NewItemController.new,
);

// ── Font-size persistence ─────────────────────────────────────────────────────

/// Thin wrapper around shared_preferences for the font-size scalar.
class FontSizeStore {
  static const _key = 'font_size';

  static Future<FontSize> read() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key);
    return switch (raw) {
      'small' => FontSize.small,
      'large' => FontSize.large,
      _ => FontSize.medium,
    };
  }

  static Future<void> write(FontSize size) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key, size.name);
  }
}

/// Riverpod controller for the selected font size.
/// Default is [FontSize.medium]; hydrates the persisted value in [build].
class FontSizeController extends Notifier<FontSize> {
  @override
  FontSize build() {
    FontSizeStore.read().then((size) {
      if (size != state) state = size;
    }).catchError((Object e, StackTrace s) {
      AppLog.instance.log('prefs', 'FontSizeStore.read: $e', level: LogLevel.error);
    });
    return FontSize.medium;
  }

  void set(FontSize size) {
    state = size;
    unawaited(FontSizeStore.write(size).catchError((Object e, StackTrace s) {
      AppLog.instance.log('prefs', 'FontSizeStore.write: $e', level: LogLevel.error);
    }));
  }
}

final fontSizeProvider = NotifierProvider<FontSizeController, FontSize>(
  FontSizeController.new,
);

// ── Optimistic-loading persistence ───────────────────────────────────────────

/// Thin wrapper around shared_preferences for the optimistic-loading flag.
class OptimisticLoadingStore {
  static const _key = 'optimistic_loading';

  static Future<bool> read() async {
    final prefs = await SharedPreferences.getInstance();
    // Default: true (eager warmup on by default).
    return prefs.getBool(_key) ?? true;
  }

  static Future<void> write(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_key, value);
  }
}

/// Riverpod controller for the optimistic-loading toggle.
/// Default is [true]; hydrates the persisted value in [build].
class OptimisticLoadingController extends Notifier<bool> {
  @override
  bool build() {
    OptimisticLoadingStore.read().then((value) {
      if (value != state) state = value;
    }).catchError((Object e, StackTrace s) {
      AppLog.instance.log('prefs', 'OptimisticLoadingStore.read: $e', level: LogLevel.error);
    });
    return true;
  }

  void set(bool value) {
    state = value;
    unawaited(OptimisticLoadingStore.write(value).catchError((Object e, StackTrace s) {
      AppLog.instance.log('prefs', 'OptimisticLoadingStore.write: $e', level: LogLevel.error);
    }));
  }
}

final optimisticLoadingProvider = NotifierProvider<OptimisticLoadingController, bool>(
  OptimisticLoadingController.new,
);

// ── Greedy-decoding persistence ───────────────────────────────────────────────

/// Thin wrapper around shared_preferences for the greedy-decoding flag.
class GreedyDecodingStore {
  static const _key = 'greedy_decoding';

  static Future<bool> read() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_key) ?? true;
  }

  static Future<void> write(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_key, value);
  }
}

/// Riverpod controller for the greedy-decoding toggle.
/// Default is [true]; hydrates the persisted value in [build].
class GreedyDecodingController extends Notifier<bool> {
  @override
  bool build() {
    GreedyDecodingStore.read().then((value) {
      if (value != state) state = value;
    }).catchError((Object e, StackTrace s) {
      AppLog.instance.log('prefs', 'GreedyDecodingStore.read: $e', level: LogLevel.error);
    });
    return true;
  }

  void set(bool value) {
    state = value;
    unawaited(GreedyDecodingStore.write(value).catchError((Object e, StackTrace s) {
      AppLog.instance.log('prefs', 'GreedyDecodingStore.write: $e', level: LogLevel.error);
    }));
  }
}

final greedyDecodingProvider = NotifierProvider<GreedyDecodingController, bool>(
  GreedyDecodingController.new,
);

// ── Real-pipeline flag ────────────────────────────────────────────────────────

/// True when the REAL on-device pipeline is wired (models present). False →
/// the app is running the simulated demo pipeline and the board shows fake data.
final usingRealPipelineProvider = Provider<bool>((_) => false);

// ── Model-ready (drives the dashboard model-load progress bar) ───────────────

/// False until the on-device LLM is loaded + warmed; true thereafter.
class ModelReadyController extends Notifier<bool> {
  @override
  bool build() => false;
  void markReady() {
    if (!state) state = true;
  }

  /// Reset back to loading state (e.g. during a model switch).
  void reset() {
    if (state) state = false;
  }
}

final modelReadyProvider =
    NotifierProvider<ModelReadyController, bool>(ModelReadyController.new);

// ── Startup progress (staged 0→100% bar on the dashboard) ────────────────────

/// Snapshot of the staged startup progress: a 0..1 [value] for the bar, a
/// per-stage [label], and [done] once the warm-up resolved.
class StartupProgress {
  const StartupProgress({required this.label, required this.value, required this.done});
  final String label;
  final double value;
  final bool done;
}

/// Thin wrapper around shared_preferences for the last REAL warm-prefill
/// duration — paces the animated warm-up segment of the startup bar.
class WarmEstimateStore {
  static const _key = 'last_warm_ms';

  /// First-ever-run fallback (no persisted duration yet).
  static const int defaultMs = 15000;

  static Future<int> read() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getInt(_key) ?? defaultMs;
  }

  static Future<void> write(int ms) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_key, ms);
  }
}

/// Maps raw [StartupEvent]s from the real pipeline onto one 0..1 bar.
///
/// Band map:
///   Whisper load   0.00 → 0.12
///   LLM load       0.12 → 0.55   (native 0-100 load progress)
///   Warm prefill   0.55 → 0.97   (ease-out animation paced by [WarmEstimateStore])
///   Warm restore          0.97   (sub-second loadSession)
///   WarmDone               1.00   (done)
class StartupProgressController extends Notifier<StartupProgress> {
  static const double _kWhisperDone = 0.12;
  static const double _kLlmDone = 0.55;
  static const double _kWarmTarget = 0.97;
  static const int _kTickMs = 150;

  Timer? _warmTimer;
  String _modelLabel = 'model';
  bool _prefillRunning = false;
  int _estimateMs = WarmEstimateStore.defaultMs;

  @override
  StartupProgress build() {
    ref.onDispose(_cancelTimer);
    WarmEstimateStore.read().then((ms) {
      _estimateMs = ms;
    }).catchError((Object e, StackTrace s) {
      AppLog.instance.log('prefs', 'WarmEstimateStore.read: $e', level: LogLevel.error);
    });
    return const StartupProgress(label: '', value: 0.0, done: false);
  }

  void handle(StartupEvent e) {
    switch (e) {
      case WhisperLoadStart():
        state = const StartupProgress(
            label: 'Loading speech model…', value: 0.0, done: false);
      case WhisperLoadDone():
        state = StartupProgress(
            label: state.label, value: _kWhisperDone, done: false);
      case LlmLoadStart(:final modelLabel):
        // A model switch arrives while done — reset the bar (Whisper is
        // already loaded, so it restarts at the LLM band).
        _cancelTimer();
        _prefillRunning = false;
        _modelLabel = modelLabel;
        state = StartupProgress(
            label: 'Loading $modelLabel…', value: _kWhisperDone, done: false);
      case LlmLoadProgress(:final percent):
        final v = _kWhisperDone + (_kLlmDone - _kWhisperDone) * (percent / 100);
        state = StartupProgress(
            label: 'Loading $_modelLabel… $percent%', value: v, done: false);
      case LlmLoadDone():
        state = StartupProgress(
            label: 'Loading $_modelLabel… 100%', value: _kLlmDone, done: false);
      case WarmRestoreStart():
        _cancelTimer();
        _prefillRunning = false;
        state = const StartupProgress(
            label: 'Restoring warmed-up state…', value: _kWarmTarget, done: false);
      case WarmPrefillStart():
        _prefillRunning = true;
        state = StartupProgress(
            label: 'Warming up the AI — first run after a change…',
            value: state.value < _kLlmDone ? _kLlmDone : state.value,
            done: false);
        _startWarmAnimation();
      case WarmDone(:final tookMs):
        _cancelTimer();
        final wasPrefill = _prefillRunning;
        _prefillRunning = false;
        state = StartupProgress(label: state.label, value: 1.0, done: true);
        // Persist only REAL prefill durations: a 73ms restore (or a trivial
        // warm) must not poison the next cold-start's prefill estimate.
        if (wasPrefill && tookMs > 3000) {
          _estimateMs = tookMs;
          unawaited(WarmEstimateStore.write(tookMs).catchError((Object e, StackTrace s) {
            AppLog.instance.log('prefs', 'WarmEstimateStore.write: $e', level: LogLevel.error);
          }));
        }
    }
  }

  /// Ease-out fill toward 0.97, paced so ~95% of the band is covered after
  /// [_estimateMs] (the persisted last prefill duration; 15s default).
  void _startWarmAnimation() {
    _cancelTimer();
    final est = _estimateMs < _kTickMs ? _kTickMs : _estimateMs;
    // (1-k)^(est/tick) = 0.05  →  k = 1 - 0.05^(tick/est)
    final k = 1 - math.pow(0.05, _kTickMs / est).toDouble();
    _warmTimer = Timer.periodic(const Duration(milliseconds: _kTickMs), (_) {
      final v = state.value + (_kWarmTarget - state.value) * k;
      state = StartupProgress(label: state.label, value: v, done: false);
    });
  }

  void _cancelTimer() {
    _warmTimer?.cancel();
    _warmTimer = null;
  }
}

final startupProgressProvider =
    NotifierProvider<StartupProgressController, StartupProgress>(
  StartupProgressController.new,
);

// ── Selected-model persistence ────────────────────────────────────────────────

/// Thin wrapper around shared_preferences for the selected LLM model.
class SelectedModelStore {
  static const _key = 'selected_model';

  static Future<String?> read() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_key);
  }

  static Future<void> write(LlmModel model) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key, model.name);
  }
}

/// Riverpod controller for the selected on-device LLM.
/// Default is [LlmModel.qwen3_06b]; hydrates the persisted value in [build].
/// Seeded with the pre-loaded value from [main] via ProviderScope override to
/// ensure deterministic startup ordering (the Router is constructed with the
/// right model before the first frame).
class SelectedModelController extends Notifier<LlmModel> {
  @override
  LlmModel build() {
    SelectedModelStore.read().then((name) {
      final m = LlmModel.fromName(name);
      if (m != state) state = m;
    }).catchError((Object e, StackTrace s) {
      AppLog.instance.log('prefs', 'SelectedModelStore.read: $e', level: LogLevel.error);
    });
    return LlmModel.qwen3_06b;
  }

  void set(LlmModel model) {
    state = model;
    unawaited(SelectedModelStore.write(model).catchError((Object e, StackTrace s) {
      AppLog.instance.log('prefs', 'SelectedModelStore.write: $e', level: LogLevel.error);
    }));
  }
}

final selectedModelProvider =
    NotifierProvider<SelectedModelController, LlmModel>(
  SelectedModelController.new,
);

// ── Selected-STT-model persistence ────────────────────────────────────────────

/// Thin wrapper around shared_preferences for the selected Whisper (STT) model.
class SelectedSttModelStore {
  static const _key = 'selected_stt_model';

  static Future<String?> read() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_key);
  }

  static Future<void> write(SttModel model) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key, model.name);
  }
}

/// Riverpod controller for the selected on-device Whisper model.
/// Default is [SttModel.smallMultilingual]; hydrates the persisted value in
/// [build]. Seeded with the pre-loaded value from [main] via ProviderScope
/// override so the pipeline is constructed with the right STT variant before
/// the first frame.
class SelectedSttModelController extends Notifier<SttModel> {
  @override
  SttModel build() {
    SelectedSttModelStore.read().then((name) {
      final m = SttModel.fromName(name);
      if (m != state) state = m;
    }).catchError((Object e, StackTrace s) {
      AppLog.instance.log('prefs', 'SelectedSttModelStore.read: $e', level: LogLevel.error);
    });
    return SttModel.smallMultilingual;
  }

  void set(SttModel model) {
    state = model;
    unawaited(SelectedSttModelStore.write(model).catchError((Object e, StackTrace s) {
      AppLog.instance.log('prefs', 'SelectedSttModelStore.write: $e', level: LogLevel.error);
    }));
  }
}

final selectedSttModelProvider =
    NotifierProvider<SelectedSttModelController, SttModel>(
  SelectedSttModelController.new,
);

