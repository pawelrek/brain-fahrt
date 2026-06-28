/// Capture pipeline contracts — the capture-core produces; the overlay consumes.
library;

import '../data/models/enums.dart';
import '../features/capture/capture_state.dart';

/// Hard cap on a single recording. Whisper transcribes at most 30 s
/// (the encoder's fixed mel window); recording longer than that silently drops
/// the tail. The real pipeline auto-stops at this duration and the overlay
/// shows a countdown for the last few seconds.
const Duration kMaxRecordDuration = Duration(seconds: 28);

/// One scripted capture entry used by [SimulatedPipeline].
class ScriptedCapture {
  final String raw;
  final String summary;
  final String? bucket;
  final ItemType? type;
  final double confidence;

  const ScriptedCapture({
    required this.raw,
    required this.summary,
    required this.bucket,
    required this.type,
    required this.confidence,
  });
}

/// A background routing result to apply onto an already-filed provisional item.
class RoutePatch {
  const RoutePatch({
    required this.summary,
    required this.bucketId,
    required this.type,
  });

  final String summary;
  final String? bucketId;
  final ItemType? type;
}

/// The contract every pipeline implementation must satisfy.
abstract interface class CapturePipeline {
  /// Begin a capture. Returns a broadcast-safe stream of [CaptureState] events
  /// from [CaptureListening] through [CaptureResult]. The stream closes after
  /// [CaptureResult] is emitted (or after [cancel]).
  Stream<CaptureState> run();

  /// Resolves with the background routing result for the MOST RECENT run that
  /// emitted a provisional [CaptureResult], or null when there is nothing to
  /// patch (final result, garbage, error, cancel, or no run yet). Never throws.
  Future<RoutePatch?> get pendingRoute;

  /// Signal "stop" while listening; transitions to [CaptureHeard].
  void stop();

  /// Abort while listening or heard; closes the stream and leaves no item.
  void cancel();

  /// Release resources. Called by the Riverpod `ref.onDispose` hook.
  void dispose();
}
