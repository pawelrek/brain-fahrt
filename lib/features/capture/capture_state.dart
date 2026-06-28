/// Capture state machine states — semantic only.
///
/// The overlay decorates bucket names/colors from `bucketsProvider` +
/// `bucketColorsFor(bucketId ?? 'unsorted')`.
library;

import '../../data/models/enums.dart';

sealed class CaptureState {
  const CaptureState();
}

/// Mic is idle; no recording in progress.
class CaptureIdle extends CaptureState {
  const CaptureIdle();
}

/// Mic is open; [partial] streams in as the user speaks.
class CaptureListening extends CaptureState {
  const CaptureListening({required this.partial, required this.elapsed});

  final String partial;
  final Duration elapsed;
}

/// User (or auto-stop) signalled end; waiting for audio to flush.
class CaptureHeard extends CaptureState {
  const CaptureHeard();
}

/// Audio received; running on-device ASR.
class CaptureTranscribing extends CaptureState {
  const CaptureTranscribing();
}

/// Transcript done; waiting for the LLM router to finish loading (lazy path only).
class CaptureLoadingLlm extends CaptureState {
  const CaptureLoadingLlm();
}

/// Transcript ready; running on-device triage/summary.
class CaptureSorting extends CaptureState {
  const CaptureSorting();
}

/// Pipeline finished; [filed] == true means a bucket was chosen with confidence.
class CaptureResult extends CaptureState {
  const CaptureResult({
    required this.summary,
    required this.transcript,
    required this.bucketId,
    required this.type,
    required this.filed,
    this.discarded = false,
    this.provisional = false,
  });

  final String summary;
  final String transcript;
  final String? bucketId;
  final ItemType? type;
  final bool filed;

  /// Silence / non-speech — show brief feedback but create NO item.
  final bool discarded;

  /// true = filed immediately after ASR; routing continues in background and
  /// may patch the item.
  final bool provisional;
}
