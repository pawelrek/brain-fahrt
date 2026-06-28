/// Offline demo pipeline — streams the 6 scripted captures in round-robin order
/// so the low-confidence Unsorted path (capture #6) is exercised in normal use.
library;

import 'dart:async';
import 'dart:math' show Random;

import '../data/models/enums.dart';
import '../features/capture/capture_state.dart';
import 'capture_pipeline.dart';

// ── Scripted captures (transcribed verbatim from dot-data.jsx) ───────────────

const List<ScriptedCapture> _kCaptures = [
  ScriptedCapture(
    raw:
        "okay, new idea for the general project — we should add a dark mode toggle to the settings screen",
    summary: 'Add a dark mode toggle to settings',
    bucket: 'general',
    type: ItemType.improvement,
    confidence: 0.94,
  ),
  ScriptedCapture(
    raw:
        "we're paging twice every time a webhook retries, it's duplicating the incident",
    summary: 'Duplicate incidents when webhooks retry',
    bucket: 'general',
    type: ItemType.bug,
    confidence: 0.91,
  ),
  ScriptedCapture(
    raw: "remember to grab oat milk, coffee filters and a birthday card for Sam",
    summary: 'Oat milk, coffee filters, and a birthday card for Sam',
    bucket: 'shopping',
    type: null,
    confidence: 0.88,
  ),
  ScriptedCapture(
    raw: "idea — a weekly digest that summarizes everything I captured that week",
    summary: "Weekly digest summarizing the week's captures",
    bucket: 'ideas',
    type: null,
    confidence: 0.86,
  ),
  ScriptedCapture(
    raw: "book the dentist and renew my passport before July",
    summary: 'Book the dentist and renew passport before July',
    bucket: 'todos',
    type: null,
    confidence: 0.90,
  ),
  ScriptedCapture(
    raw:
        "the sort thing keeps picking the wrong project whenever I mumble the name a little",
    summary: 'Routing picks the wrong project when the name is mumbled',
    bucket: null,
    type: null,
    confidence: 0.34, // low → Unsorted
  ),
];

/// Simulates the full recording → transcription → sorting pipeline with
/// injectable durations (pass [Duration.zero] in tests for instant execution).
class SimulatedPipeline implements CapturePipeline {
  SimulatedPipeline({
    this.charInterval = const Duration(milliseconds: 42),
    this.heardDelay = const Duration(milliseconds: 620),
    this.transcribingDelay = const Duration(milliseconds: 1000),
    this.sortingDelay = const Duration(milliseconds: 1150),
  });

  final Duration charInterval;
  final Duration heardDelay;
  final Duration transcribingDelay;
  final Duration sortingDelay;

  StreamController<CaptureState>? _controller;
  Timer? _charTimer;
  Timer? _autoStopTimer;
  Timer? _phaseTimer;
  bool _stopped = false;
  bool _cancelled = false;
  // Per-instance cursor so successive run() calls cycle through all 6 captures
  // (and each injected test pipeline starts independently at 0).
  int _cursor = 0;
  late ScriptedCapture _capture;

  /// Simulated results are always final — there is never a background route.
  @override
  Future<RoutePatch?> get pendingRoute => Future.value(null);

  @override
  Stream<CaptureState> run() {
    _teardown();

    _capture = _kCaptures[_cursor];
    _cursor = (_cursor + 1) % _kCaptures.length;

    _stopped = false;
    _cancelled = false;

    final ctrl = StreamController<CaptureState>();
    _controller = ctrl;

    final startTime = DateTime.now();
    final raw = _capture.raw;
    int charIndex = 0;
    final rng = Random();

    Duration elapsed() => DateTime.now().difference(startTime);

    ctrl.add(CaptureListening(partial: '', elapsed: elapsed()));

    _charTimer = Timer.periodic(charInterval, (t) {
      if (_cancelled || _stopped || ctrl.isClosed) {
        t.cancel();
        return;
      }

      // Advance 1 or 2 chars (30% chance of +2, matching prototype).
      charIndex += rng.nextDouble() < 0.3 ? 2 : 1;

      if (charIndex >= raw.length) {
        charIndex = raw.length;
        ctrl.add(CaptureListening(partial: raw, elapsed: elapsed()));
        t.cancel();

        // Auto-stop ~700ms after the partial completes if not already stopped.
        _autoStopTimer = Timer(const Duration(milliseconds: 700), () {
          if (!_stopped && !_cancelled) stop();
        });
      } else {
        ctrl.add(
          CaptureListening(
            partial: raw.substring(0, charIndex),
            elapsed: elapsed(),
          ),
        );
      }
    });

    return ctrl.stream;
  }

  @override
  void stop() {
    if (_stopped || _cancelled) return;
    _stopped = true;
    _charTimer?.cancel();
    _autoStopTimer?.cancel();

    final ctrl = _controller;
    if (ctrl == null || ctrl.isClosed) return;

    ctrl.add(const CaptureHeard());

    _phaseTimer = Timer(heardDelay, () {
      if (_cancelled || ctrl.isClosed) return;
      ctrl.add(const CaptureTranscribing());

      _phaseTimer = Timer(transcribingDelay, () {
        if (_cancelled || ctrl.isClosed) return;
        ctrl.add(const CaptureSorting());

        _phaseTimer = Timer(sortingDelay, () {
          if (_cancelled || ctrl.isClosed) return;
          _emitResult(ctrl);
        });
      });
    });
  }

  @override
  void cancel() {
    if (_cancelled) return;
    _cancelled = true;
    _teardown();
  }

  @override
  void dispose() => _teardown();

  // ── internals ──────────────────────────────────────────────────────────────

  void _emitResult(StreamController<CaptureState> ctrl) {
    final String? bucketId =
        _capture.confidence < 0.6 ? null : _capture.bucket;
    final ItemType? type = bucketId != null ? _capture.type : null;

    ctrl
      ..add(
        CaptureResult(
          summary: _capture.summary,
          transcript: _capture.raw,
          bucketId: bucketId,
          type: type,
          filed: bucketId != null,
        ),
      )
      ..close();
  }

  void _teardown() {
    _charTimer?.cancel();
    _autoStopTimer?.cancel();
    _phaseTimer?.cancel();
    _charTimer = null;
    _autoStopTimer = null;
    _phaseTimer = null;
    final ctrl = _controller;
    _controller = null;
    if (ctrl != null && !ctrl.isClosed) ctrl.close();
  }
}
