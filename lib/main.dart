import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart';

import 'app/app.dart';
import 'core/design/colors.dart';
import 'core/log/app_log.dart';
import 'data/db/database.dart';
import 'data/models/enums.dart';
import 'data/providers.dart';
import 'data/seed.dart';
import 'pipeline/real/model_installer.dart';
import 'pipeline/real/model_paths.dart';
import 'pipeline/real/model_registry.dart';
import 'pipeline/real/real_pipeline_provider.dart';
import 'pipeline/real/stt_registry.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Keep-dark chrome: light status/navigation icons over the near-black canvas.
  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
    statusBarColor: Color(0x00000000),
    statusBarIconBrightness: Brightness.light,
    statusBarBrightness: Brightness.dark,
    systemNavigationBarColor: DotColors.canvas,
    systemNavigationBarIconBrightness: Brightness.light,
  ));

  final priorOnError = FlutterError.onError;
  FlutterError.onError = (details) {
    AppLog.instance.log('flutter', details.exceptionAsString(), level: LogLevel.error);
    (priorOnError ?? FlutterError.presentError)(details);
  };

  PlatformDispatcher.instance.onError = (error, stack) {
    AppLog.instance.log('zone', '$error\n$stack', level: LogLevel.error);
    return false;
  };

  // First launch only: show a splash while the native side streams the bundled
  // on-device models (~0.7 GB: 0.6B + Whisper) from the install-time asset pack
  // into app storage.
  runApp(const _UnpackSplash());

  final db = AppDatabase();
  await seedDatabaseIfEmpty(db);
  await ModelInstaller.ensureInstalled();

  // Preload persisted settings SYNCHRONOUSLY before constructing the Router.
  // All reads are wrapped in try/catch so a SharedPreferences failure cannot
  // abort launch — we fall back to safe defaults and log the error.
  FontSize persistedFontSize = FontSize.medium;
  bool persistedOptimisticLoading = true;
  bool persistedGreedyDecoding = true;
  LlmModel persistedModel = LlmModel.qwen3_06b;
  SttModel persistedSttModel = SttModel.smallMultilingual;
  try {
    persistedFontSize = await FontSizeStore.read();
    persistedOptimisticLoading = await OptimisticLoadingStore.read();
    persistedGreedyDecoding = await GreedyDecodingStore.read();
    persistedModel = LlmModel.fromName(await SelectedModelStore.read());
    persistedSttModel = SttModel.fromName(await SelectedSttModelStore.read());
  } catch (e, st) {
    AppLog.instance.log(
      'main',
      'SharedPreferences read failed — using defaults. $e\n$st',
      level: LogLevel.error,
    );
  }

  // Use the real on-device pipeline when the models are present; otherwise fall
  // back to the simulated one (so the app still runs without models).
  final paths = await ModelPaths.resolve(
      qwenGgufName: persistedModel.gguf, sttModel: persistedSttModel);
  final modelsReady = await paths.allExist();

  final overrides = <Override>[
    databaseProvider.overrideWithValue(db),
    fontSizeProvider.overrideWith(() => _SeededFontSizeController(persistedFontSize)),
    optimisticLoadingProvider.overrideWith(
      () => _SeededOptimisticLoadingController(persistedOptimisticLoading),
    ),
    greedyDecodingProvider.overrideWith(
      () => _SeededGreedyDecodingController(persistedGreedyDecoding),
    ),
    selectedModelProvider.overrideWith(
      () => _SeededSelectedModelController(persistedModel),
    ),
    selectedSttModelProvider.overrideWith(
      () => _SeededSelectedSttModelController(persistedSttModel),
    ),
    usingRealPipelineProvider.overrideWithValue(modelsReady),
    if (modelsReady)
      realPipelineOverride(db, initialModel: persistedModel),
  ];

  runApp(
    ProviderScope(
      overrides: overrides,
      child: const DotApp(),
    ),
  );
}

/// A seeded variant of [FontSizeController] that returns [_seed] from [build],
/// eliminating the async-hydration flash on startup.
class _SeededFontSizeController extends FontSizeController {
  _SeededFontSizeController(this._seed);
  final FontSize _seed;

  @override
  FontSize build() => _seed;
}

/// A seeded variant of [OptimisticLoadingController] that returns [_seed] from
/// [build], eliminating the async-hydration flash on startup.
class _SeededOptimisticLoadingController extends OptimisticLoadingController {
  _SeededOptimisticLoadingController(this._seed);
  final bool _seed;

  @override
  bool build() => _seed;
}

/// A seeded variant of [GreedyDecodingController] that returns [_seed] from
/// [build], eliminating the async-hydration flash on startup.
class _SeededGreedyDecodingController extends GreedyDecodingController {
  _SeededGreedyDecodingController(this._seed);
  final bool _seed;

  @override
  bool build() => _seed;
}

/// A seeded variant of [SelectedModelController] that returns [_seed] from
/// [build], eliminating the async-hydration gap on startup so the Router is
/// constructed with the correct model from frame 1.
class _SeededSelectedModelController extends SelectedModelController {
  _SeededSelectedModelController(this._seed);
  final LlmModel _seed;

  @override
  LlmModel build() => _seed;
}

/// Seeded variant of [SelectedSttModelController] — returns [_seed] from
/// [build] so the transcriber loads the persisted Whisper variant from frame 1.
class _SeededSelectedSttModelController extends SelectedSttModelController {
  _SeededSelectedSttModelController(this._seed);
  final SttModel _seed;

  @override
  SttModel build() => _seed;
}

/// Shown on first launch while the bundled models are unpacked.
class _UnpackSplash extends StatelessWidget {
  const _UnpackSplash();

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      home: Scaffold(
        backgroundColor: DotColors.canvas,
        body: const Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(
                width: 38,
                height: 38,
                child: CircularProgressIndicator(
                  color: brandRed,
                  strokeWidth: 3,
                ),
              ),
              SizedBox(height: 22),
              Padding(
                padding: EdgeInsets.symmetric(horizontal: 48),
                child: Text(
                  'Setting up brain-fahrt…\nUnpacking the on-device AI\n(first launch only)',
                  textAlign: TextAlign.center,
                  // The splash MaterialApp has no theme — set light text
                  // explicitly so it reads on the dark canvas.
                  style: TextStyle(color: DotColors.muted),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
