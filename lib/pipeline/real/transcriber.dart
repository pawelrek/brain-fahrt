import 'dart:typed_data';

import 'package:sherpa_onnx/sherpa_onnx.dart' as sherpa;

import '../../core/log/app_log.dart';
import 'model_paths.dart';

/// Whisper-based offline speech recognizer wrapping sherpa-onnx.
///
/// Lifecycle:
///   1. Call [init] once with valid [ModelPaths].
///   2. Call [transcribe] for each audio clip.
///   3. Call [dispose] when done.
class Transcriber {
  sherpa.OfflineRecognizer? _recognizer;

  /// Build an [sherpa.OfflineRecognizer] backed by Whisper int8 ONNX models.
  ///
  /// Initializes the sherpa-onnx native bindings if not already done.
  /// Throws if the native recognizer cannot be created.
  Future<void> init(ModelPaths paths) async {
    // Initialize native bindings exactly once (no-op if already done).
    sherpa.initBindings();

    final whisperConfig = sherpa.OfflineWhisperModelConfig(
      encoder: paths.whisperEncoder,
      decoder: paths.whisperDecoder,
      // Per-variant language ('en' for multilingual → pins English so a heavy
      // accent isn't mis-detected as the speaker's L1; '' for `.en` models,
      // which force English internally). 'transcribe' (never 'translate').
      language: paths.whisperLanguage,
      task: 'transcribe',
    );

    final modelConfig = sherpa.OfflineModelConfig(
      whisper: whisperConfig,
      tokens: paths.whisperTokens,
      numThreads: 4,
      modelType: 'whisper',
      debug: false,
    );

    final config = sherpa.OfflineRecognizerConfig(model: modelConfig);

    final sw = Stopwatch()..start();
    _recognizer = sherpa.OfflineRecognizer(config);
    sw.stop();
    AppLog.instance.log('asr', 'Whisper loaded in ${sw.elapsedMilliseconds}ms');
  }

  /// Transcribe [samples] (mono Float32, normalised to [-1, 1]).
  ///
  /// Returns the recognised text, or an empty string for silent / garbage input
  /// or if [init] has not been called.
  Future<String> transcribe(Float32List samples, {int sampleRate = 16000}) async {
    final recognizer = _recognizer;
    if (recognizer == null) {
      AppLog.instance.log('asr', 'transcript (0 chars): [recognizer not initialized]',
          level: LogLevel.warn);
      return '';
    }

    // Guard against trivially empty audio to avoid native crashes.
    if (samples.isEmpty) {
      AppLog.instance.log('asr', 'transcript (0 chars): [empty audio]');
      return '';
    }

    // Whisper has a hard 30-second (480,000 sample @ 16 kHz) limit.
    // Feeding longer audio causes silent truncation or garbage output from
    // sherpa-onnx OfflineRecognizer. Clamp here so the transcript is always
    // from a valid window rather than silently corrupted.
    const int maxSamples = 30 * 16000; // 480 000
    final Float32List clampedSamples;
    if (samples.length > maxSamples) {
      AppLog.instance.log(
        'asr',
        'audio clamped from ${samples.length} to $maxSamples samples '
        '(${(samples.length / sampleRate).toStringAsFixed(1)}s > 30s limit)',
        level: LogLevel.warn,
      );
      clampedSamples = Float32List.sublistView(samples, 0, maxSamples);
    } else {
      clampedSamples = samples;
    }

    try {
      final stream = recognizer.createStream();
      try {
        stream.acceptWaveform(samples: clampedSamples, sampleRate: sampleRate);
        recognizer.decode(stream);
        final result = recognizer.getResult(stream);
        final text = result.text.trim();
        AppLog.instance.log('asr', 'transcript (${text.length} chars): $text');
        return text;
      } finally {
        stream.free();
      }
    } catch (e) {
      // Swallow decode errors (e.g. garbage audio, model edge cases) and
      // return empty so the caller can handle gracefully.
      AppLog.instance.log('asr', 'transcribe failed: $e', level: LogLevel.warn);
      return '';
    }
  }

  /// Release the underlying native recognizer.
  void dispose() {
    _recognizer?.free();
    _recognizer = null;
  }
}
