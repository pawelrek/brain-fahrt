import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:slop/pipeline/real/model_paths.dart';
import 'package:slop/pipeline/real/model_registry.dart';
import 'package:slop/pipeline/real/router.dart';
import 'package:slop/pipeline/real/transcriber.dart';

/// Reads a 16-bit PCM WAV file into Float32 samples in [-1, 1].
(Float32List samples, int sampleRate) _readWavPcm16(String path) {
  final bytes = File(path).readAsBytesSync();
  final bd = ByteData.sublistView(bytes);
  var sampleRate = 16000;
  var i = 12; // skip RIFF header
  var dataOffset = -1;
  var dataSize = 0;
  while (i + 8 <= bytes.length) {
    final id = String.fromCharCodes(bytes.sublist(i, i + 4));
    final size = bd.getUint32(i + 4, Endian.little);
    if (id == 'fmt ') {
      sampleRate = bd.getUint32(i + 12, Endian.little);
    } else if (id == 'data') {
      dataOffset = i + 8;
      dataSize = size;
      break;
    }
    i += 8 + size + (size & 1);
  }
  final n = dataSize ~/ 2;
  final out = Float32List(n);
  for (var s = 0; s < n; s++) {
    out[s] = bd.getInt16(dataOffset + s * 2, Endian.little) / 32768.0;
  }
  return (out, sampleRate);
}

/// On-device proof that the REAL pipeline works end-to-end without the mic:
/// load the pushed models, transcribe a bundled WAV with Whisper, route the
/// text with the router LLM (Gemma 3 4B default). (The emulator has no audio input, so we feed a WAV instead
/// of the live mic — the mic path is the same `transcribe(samples)` call.)
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('Whisper transcribes + router LLM routes, on-device', (tester) async {
    final paths = await ModelPaths.resolve(qwenGgufName: LlmModel.qwen3_17b.gguf);
    expect(await paths.allExist(), isTrue,
        reason: 'models must be pushed to the device first');

    final modelsDir = File(paths.whisperEncoder).parent.path;
    final (samples, sr) = _readWavPcm16('$modelsDir/test.wav');
    expect(samples.length, greaterThan(1000));

    // ── Whisper ──
    final transcriber = Transcriber();
    await transcriber.init(paths);
    final text = await transcriber.transcribe(samples, sampleRate: sr);
    // ignore: avoid_print
    print('=== WHISPER TRANSCRIPT: "$text"');
    expect(text.trim(), isNotEmpty, reason: 'Whisper should produce text');
    transcriber.dispose();

    // ── LLM routing ──
    final router = Router();
    await router.init(paths);
    final result = await router.route(
      transcript: text,
      audioDuration: const Duration(seconds: 5),
      buckets: const [
        BucketInfo(id: 'devhub', name: 'devhub', isProject: true),
        BucketInfo(id: 'webapp', name: 'Webapp', isProject: true),
        BucketInfo(id: 'general', name: 'General', isProject: true),
        BucketInfo(id: 'shopping', name: 'Shopping', isProject: false),
        BucketInfo(id: 'todos', name: 'To-dos', isProject: false),
        BucketInfo(id: 'ideas', name: 'Ideas', isProject: false),
      ],
    );
    // ignore: avoid_print
    print('=== QWEN summary="${result.summary}" '
        'bucket=${result.bucketId} type=${result.type} '
        'conf=${result.confidence}');
    expect(result.summary.trim(), isNotEmpty,
        reason: 'the router LLM should produce a one-line summary');
    router.dispose();
  }, timeout: const Timeout(Duration(minutes: 8)));
}
