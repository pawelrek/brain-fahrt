import 'dart:io';

import 'package:path_provider/path_provider.dart';

import 'stt_registry.dart';

/// Resolved absolute paths to the on-device model files.
class ModelPaths {
  const ModelPaths({
    required this.whisperEncoder,
    required this.whisperDecoder,
    required this.whisperTokens,
    required this.whisperLanguage,
    required this.qwenGguf,
  });

  final String whisperEncoder;
  final String whisperDecoder;
  final String whisperTokens;

  /// Whisper decode language for the selected STT variant ('en' for multilingual,
  /// '' for `.en` models). Passed straight to [Transcriber.init].
  final String whisperLanguage;
  final String qwenGguf;

  /// Resolves paths using the external storage directory.
  /// Models are expected under `<externalStorage>/models/`.
  ///
  /// [qwenGgufName] selects which GGUF to use for the router.
  /// Pass the filename from [LlmModel.gguf] (e.g. `'gemma-3-4b-it-q4_k_m.gguf'`).
  /// The directory holding all on-device model files (`<externalStorage>/models/`).
  /// The native first-launch unpacker (MainActivity.copyModels) and the
  /// downloader both write here; [resolve] reads from here.
  static Future<String> modelsDir() async {
    // External app files dir on Android; fall back to the documents dir if
    // external storage is unavailable (avoids a null-crash that wedges startup).
    final extDir = await getExternalStorageDirectory() ??
        await getApplicationDocumentsDirectory();
    return '${extDir.path}/models';
  }

  /// True iff the GGUF named [gguf] is present on disk in the models dir.
  static Future<bool> modelExists(String gguf) async {
    return File('${await modelsDir()}/$gguf').exists();
  }

  static Future<ModelPaths> resolve({
    required String qwenGgufName,
    SttModel sttModel = SttModel.smallMultilingual,
  }) async {
    final dir = await modelsDir();
    return ModelPaths(
      // STT files come from the selected Whisper variant. The default
      // (multilingual small) is more robust to accented / non-native English
      // than the English-only `small.en`; the language is pinned per-variant.
      whisperEncoder: '$dir/${sttModel.encoder}',
      whisperDecoder: '$dir/${sttModel.decoder}',
      whisperTokens: '$dir/${sttModel.tokens}',
      whisperLanguage: sttModel.language,
      qwenGguf: '$dir/$qwenGgufName',
    );
  }

  /// Returns true iff all four model files exist on disk.
  Future<bool> allExist() async {
    final checks = await Future.wait([
      File(whisperEncoder).exists(),
      File(whisperDecoder).exists(),
      File(whisperTokens).exists(),
      File(qwenGguf).exists(),
    ]);
    return checks.every((exists) => exists);
  }
}
