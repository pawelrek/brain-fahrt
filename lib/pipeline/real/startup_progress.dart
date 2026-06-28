/// Raw startup-progress events reported by the real pipeline. The provider
/// layer maps these onto a single 0..1 bar with stage labels.
sealed class StartupEvent { const StartupEvent(); }
class WhisperLoadStart extends StartupEvent { const WhisperLoadStart(); }
class WhisperLoadDone  extends StartupEvent { const WhisperLoadDone(); }
class LlmLoadStart     extends StartupEvent { const LlmLoadStart(this.modelLabel); final String modelLabel; }
class LlmLoadProgress  extends StartupEvent { const LlmLoadProgress(this.percent); final int percent; } // 0-100 native
class LlmLoadDone      extends StartupEvent { const LlmLoadDone(); }
class WarmRestoreStart extends StartupEvent { const WarmRestoreStart(); }
class WarmPrefillStart extends StartupEvent { const WarmPrefillStart(); }
class WarmDone         extends StartupEvent { const WarmDone(this.tookMs); final int tookMs; }
