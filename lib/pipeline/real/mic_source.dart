import 'dart:async';
import 'dart:typed_data';

import 'package:record/record.dart';

/// Captures raw microphone audio and converts it to Float32 samples.
///
/// Usage:
///   final mic = MicSource();
///   if (!await mic.hasPermission()) return;
///   await mic.start();
///   // ... wait for user to stop ...
///   final samples = await mic.stop();
class MicSource {
  final AudioRecorder _recorder = AudioRecorder();

  final BytesBuilder _buffer = BytesBuilder(copy: false);
  StreamSubscription<Uint8List>? _subscription;
  final Stopwatch _stopwatch = Stopwatch();

  /// In-flight cancellation future; awaited by [start] to prevent races.
  Future<void>? _cancelFuture;

  /// Returns true iff microphone permission has been granted (or can be granted).
  Future<bool> hasPermission() => _recorder.hasPermission();

  /// Starts streaming 16 kHz mono PCM-16 audio from the microphone.
  ///
  /// Throws if called while already recording.
  Future<void> start() async {
    // Wait for any in-flight cancel() to fully settle before re-starting.
    await _cancelFuture;
    _cancelFuture = null;

    _buffer.clear();
    _stopwatch
      ..reset()
      ..start();

    final stream = await _recorder.startStream(
      const RecordConfig(
        encoder: AudioEncoder.pcm16bits,
        sampleRate: 16000,
        numChannels: 1,
        // Auto-gain lifts soft/quiet speech toward a consistent level, which
        // helps the recognizer on under-driven input. noiseSuppress is left off:
        // Whisper is trained on noisy audio and aggressive suppression can hurt
        // accuracy — flip it on only if an A/B on real speech shows a win.
        autoGain: true,
      ),
    );

    _subscription = stream.listen(
      (chunk) => _buffer.add(chunk),
      cancelOnError: false,
    );
  }

  /// Stops recording and returns the accumulated audio as a Float32List in [-1, 1].
  ///
  /// Each sample is produced by interpreting the raw bytes as little-endian
  /// signed 16-bit integers and dividing by 32768.0.
  Future<Float32List> stop() async {
    _stopwatch.stop();

    await _subscription?.cancel();
    _subscription = null;

    await _recorder.stop();

    final bytes = _buffer.takeBytes(); // resets the builder
    return _pcm16BytesToFloat32(bytes);
  }

  /// Cancels the current recording without returning audio.
  ///
  /// The public signature stays void (fire-and-forget for callers), but the
  /// async teardown is tracked internally so that a subsequent [start] call
  /// will await completion before re-opening the recorder.
  void cancel() {
    _stopwatch.stop();
    _buffer.clear();
    final sub = _subscription;
    _subscription = null;
    // Serialize teardown: capture the combined future so start() can await it.
    _cancelFuture = Future.wait<void>([
      if (sub != null) sub.cancel(),
      _recorder.cancel(),
    ]);
  }

  /// How long recording has been (or was) active.
  Duration get elapsed => _stopwatch.elapsed;

  /// Releases the recorder's native audio-session resources.
  Future<void> dispose() async {
    await _subscription?.cancel();
    _subscription = null;
    await _recorder.dispose();
  }

  /// Converts raw little-endian PCM-16 bytes to a Float32List in [-1.0, 1.0].
  static Float32List _pcm16BytesToFloat32(Uint8List bytes) {
    // Each sample is 2 bytes; ignore a trailing odd byte if present.
    final sampleCount = bytes.length ~/ 2;
    final byteData = ByteData.sublistView(bytes);
    final out = Float32List(sampleCount);
    for (var i = 0; i < sampleCount; i++) {
      final s16 = byteData.getInt16(i * 2, Endian.little);
      out[i] = s16 / 32768.0;
    }
    return out;
  }
}
