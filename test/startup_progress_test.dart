/// Unit tests for [StartupProgressController] — the event→band math behind
/// the dashboard's staged startup progress bar.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:slop/data/providers.dart';
import 'package:slop/pipeline/real/startup_progress.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late ProviderContainer container;
  late StartupProgressController ctrl;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    container = ProviderContainer();
    ctrl = container.read(startupProgressProvider.notifier);
  });

  tearDown(() => container.dispose());

  StartupProgress read() => container.read(startupProgressProvider);

  test('whisper load fills the 0→12% band', () {
    ctrl.handle(const WhisperLoadStart());
    expect(read().label, 'Loading speech model…');
    expect(read().value, 0.0);
    ctrl.handle(const WhisperLoadDone());
    expect(read().value, closeTo(0.12, 1e-9));
    expect(read().done, isFalse);
  });

  test('llm load maps native percent onto the 12→55% band', () {
    ctrl.handle(const WhisperLoadDone());
    ctrl.handle(const LlmLoadStart('qwen3-1.7b-q4_k_m'));
    expect(read().value, closeTo(0.12, 1e-9));
    expect(read().label, contains('qwen3-1.7b-q4_k_m'));
    ctrl.handle(const LlmLoadProgress(50));
    expect(read().value, closeTo(0.12 + 0.43 * 0.5, 1e-9)); // 0.335
    expect(read().label, contains('50%'));
    ctrl.handle(const LlmLoadDone());
    expect(read().value, closeTo(0.55, 1e-9));
  });

  test('warm restore parks at 97% and WarmDone completes the bar', () {
    ctrl.handle(const WarmRestoreStart());
    expect(read().value, closeTo(0.97, 1e-9));
    expect(read().label, 'Restoring warmed-up state…');
    ctrl.handle(const WarmDone(73));
    expect(read().value, 1.0);
    expect(read().done, isTrue);
  });

  test('restore WarmDone does NOT persist the prefill estimate', () async {
    ctrl.handle(const WarmRestoreStart());
    ctrl.handle(const WarmDone(73));
    await Future<void>.delayed(const Duration(milliseconds: 20));
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getInt('last_warm_ms'), isNull);
  });

  test('prefill animates toward 97%; WarmDone completes and persists', () async {
    ctrl.handle(const LlmLoadDone());
    ctrl.handle(const WarmPrefillStart());
    expect(read().label, contains('Warming up'));
    final before = read().value;
    expect(before, closeTo(0.55, 1e-9));
    // Real timer (150ms period): a few ticks must move the bar, but never
    // past the 0.97 warm target.
    await Future<void>.delayed(const Duration(milliseconds: 500));
    expect(read().value, greaterThan(before));
    expect(read().value, lessThan(0.97));
    ctrl.handle(const WarmDone(12000));
    expect(read().value, 1.0);
    expect(read().done, isTrue);
    await Future<void>.delayed(const Duration(milliseconds: 20));
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getInt('last_warm_ms'), 12000);
  });

  test('trivial prefill (<3s) is not persisted', () async {
    ctrl.handle(const WarmPrefillStart());
    ctrl.handle(const WarmDone(800));
    expect(read().done, isTrue);
    await Future<void>.delayed(const Duration(milliseconds: 20));
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getInt('last_warm_ms'), isNull);
  });

  test('LlmLoadStart after done resets the bar (model switch)', () {
    ctrl.handle(const WarmRestoreStart());
    ctrl.handle(const WarmDone(73));
    expect(read().done, isTrue);
    ctrl.handle(const LlmLoadStart('gemma-3-4b-it-q4_k_m'));
    expect(read().done, isFalse);
    expect(read().value, closeTo(0.12, 1e-9));
    expect(read().label, contains('gemma-3-4b-it-q4_k_m'));
  });
}
