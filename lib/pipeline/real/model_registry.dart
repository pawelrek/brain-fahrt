/// Registry of bundled on-device LLMs the user can select in Settings.
library;

/// Model family: controls prompt template and stop tokens.
enum LlmFamily { qwen3, gemma }

/// Base URL for downloadable (non-bundled) model files. PLACEHOLDER — set this
/// to your host before shipping: a Hugging Face repo
/// (`https://huggingface.co/<user>/<repo>/resolve/main`) or a Cloudflare R2
/// bucket. The downloader fetches `<base>/<gguf>` and verifies its SHA-256, so
/// the file uploaded there must be byte-identical to the one [LlmModel.sha256]
/// was computed from.
const String kModelDownloadBaseUrl =
    'https://huggingface.co/CHANGE_ME/slop-models/resolve/main';

/// On-device LLMs the user can select in Settings. Resolved to files in the
/// app's external models dir by [ModelPaths.resolve] → [Router.init/reinit].
/// Used by [SelectedModelStore] / [selectedModelProvider].
//
// DELIVERY (v0.1.15): to fit Google Play's 200 MB base cap, models no longer
// ride in the base APK. The default 0.6B + Whisper ship in an INSTALL-TIME
// Play asset pack (android/model_pack) — present at first launch, read via the
// standard AssetManager and copied to app storage like before. Larger models
// (1.7B, Gemma 4B) are fetched on demand by the downloader into the same dir.
// Selecting a model whose file is absent fails the switch gracefully and
// reverts to the previous model.
enum LlmModel {
  // Downloadable upgrade (not bundled). Field bake-off on the S23+: ~1.0 GB
  // resident, 2 s load, ~13 s warm-up, 1.2-1.8 s routes, good titles — vs
  // Gemma 4B's 44-50 s mmap page-in and 5-14 s routes under RAM pressure.
  qwen3_17b('qwen3-1.7b-q4_k_m.gguf', 'Qwen3 1.7B (balanced)', LlmFamily.qwen3,
      sizeBytes: 1107409472,
      sha256: 'b139949c5bd74937ad8ed8c8cf3d9ffb1e99c866c823204dc42c0d91fa181897'),
  // Downloadable (2.3 GB). Largest/smartest; heaviest on RAM and load time.
  gemma3_4b('gemma-3-4b-it-q4_k_m.gguf', 'Gemma 3 4B (smart)', LlmFamily.gemma,
      sizeBytes: 2489894016,
      sha256: '04a43a22e8d2003deda5acc262f68ec1005fa76c735a9962a8c77042a74a7d19'),
  // The install-time-bundled DEFAULT (v0.1.15): present offline at first launch.
  qwen3_06b('qwen3-0.6b-q4_k_m.gguf', 'Qwen3 0.6B (fast)', LlmFamily.qwen3,
      bundled: true);

  const LlmModel(
    this.gguf,
    this.label,
    this.family, {
    this.bundled = false,
    this.sizeBytes,
    this.sha256,
  });

  /// Filename of the GGUF (relative to the models directory).
  final String gguf;

  /// Human-readable label shown in the Settings model selector.
  final String label;

  /// The model family: controls prompt template and stop tokens.
  final LlmFamily family;

  /// True if shipped in the install-time asset pack (present offline at first
  /// launch). Bundled models are never downloaded.
  final bool bundled;

  /// Download size in bytes (for progress + pre-flight). Null for bundled.
  final int? sizeBytes;

  /// Expected SHA-256 of the downloaded GGUF, verified before the file is
  /// activated. Null for bundled. Must match the exact file at [downloadUrl].
  final String? sha256;

  /// URL to fetch a non-bundled model from; null for bundled models.
  String? get downloadUrl => bundled ? null : '$kModelDownloadBaseUrl/$gguf';

  /// Convenience: true for Qwen3 family models (appends `/no_think` and strips
  /// `<think>…</think>` blocks from raw output).
  bool get isQwen3 => family == LlmFamily.qwen3;

  /// Deserialise from the persisted [name] string, falling back to the default
  /// model when the stored value is missing or unrecognised.
  static LlmModel fromName(String? n) =>
      LlmModel.values.firstWhere((m) => m.name == n,
          orElse: () => LlmModel.qwen3_06b);
}
