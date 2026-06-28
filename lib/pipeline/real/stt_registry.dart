/// Registry of on-device speech-to-text (Whisper) models the user can select
/// in Settings. Mirrors [LlmModel] in model_registry.dart, but for the ASR side.
library;

/// Selectable on-device Whisper variants. Resolved to files in the app's models
/// dir by [ModelPaths.resolve]; persisted via [SelectedSttModelStore] /
/// [selectedSttModelProvider]; hot-swapped by [RealCapturePipeline.switchSttModel].
///
/// Both variants below ship in the install-time asset pack, so they are present
/// offline at first launch and switch instantly (no download).
enum SttModel {
  /// Multilingual Whisper small (int8). Default. Trained across 99 languages'
  /// worth of accent variety → more robust to accented / non-native English.
  /// Language is pinned to 'en' so a heavy accent isn't mis-detected as another
  /// language.
  smallMultilingual(
    encoder: 'small-encoder.int8.onnx',
    decoder: 'small-decoder.int8.onnx',
    tokens: 'small-tokens.txt',
    language: 'en',
    label: 'Whisper Small · multilingual',
    sublabel: 'Better for accented / non-native English',
  ),

  /// English-only Whisper small (int8). Tuned toward native English; slightly
  /// sharper on clean native speech, but more brittle on accents. The `.en`
  /// model does its own English forcing, so [language] is left empty.
  smallEn(
    encoder: 'small.en-encoder.int8.onnx',
    decoder: 'small.en-decoder.int8.onnx',
    tokens: 'small.en-tokens.txt',
    language: '',
    label: 'Whisper Small · English-only',
    sublabel: 'Tuned for native English',
  );

  const SttModel({
    required this.encoder,
    required this.decoder,
    required this.tokens,
    required this.language,
    required this.label,
    required this.sublabel,
  });

  /// Encoder/decoder/tokens filenames (relative to the models directory).
  final String encoder;
  final String decoder;
  final String tokens;

  /// Whisper decode language. 'en' pins English on multilingual models; empty
  /// for `.en` models (which force English internally).
  final String language;

  /// Human-readable label + one-line description shown in the Settings selector.
  final String label;
  final String sublabel;

  /// Deserialise from the persisted [name], falling back to the default
  /// (multilingual) when the stored value is missing or unrecognised.
  static SttModel fromName(String? n) => SttModel.values
      .firstWhere((m) => m.name == n, orElse: () => SttModel.smallMultilingual);
}
