import 'dart:async';
import 'dart:io';

import 'package:fllama/fllama.dart';
import 'package:flutter/foundation.dart';

import '../../core/log/app_log.dart';
import '../../data/models/enums.dart';
import 'model_paths.dart';
import 'model_registry.dart';
import 'startup_progress.dart';

/// Minimal bucket descriptor passed from the orchestrator.
class BucketInfo {
  const BucketInfo({
    required this.id,
    required this.name,
    required this.isProject,
    this.examples = const [],
    this.description = '',
    this.keywords = '',
  });

  final String id;
  final String name;
  final bool isProject;

  /// A few recent note summaries already in this bucket — gives the model the
  /// bucket's "flavor" for content-aware routing (not just the name).
  final List<String> examples;

  /// One-line purpose, e.g. "my ML-training app project". Bridges opaque names.
  final String description;

  /// Comma-separated routing hints, e.g. "login, signup, crash, page".
  final String keywords;
}

/// An explicit "to/in `<bucket>`" match found by [Router.explicitTarget],
/// with enough span info for [stripRoutingPreamble] to cut the preamble.
class ExplicitMatch {
  const ExplicitMatch({
    required this.bucketId,
    required this.prepositionTokenIndex,
    required this.matchEndCharIndex,
    required this.matchedOnName,
    required this.leadingTokens,
  });

  final String bucketId;

  /// Token index (0-based, over alphanumeric tokens) of the
  /// to/in/into/onto/for/under preposition.
  final int prepositionTokenIndex;

  /// Char index in the ORIGINAL transcript just past the matched bucket
  /// token(s).
  final int matchEndCharIndex;

  /// True only when the match was against the bucket's NAME or id. A keyword
  /// match still routes (detId) but must never strip the preamble — the words
  /// around a keyword are content ("remind me to call mom").
  final bool matchedOnName;

  /// Lowercased tokens BEFORE the preposition; [stripRoutingPreamble] only
  /// strips when every one of them is routing filler.
  final List<String> leadingTokens;
}

/// Result returned by [Router.route].
class RouteResult {
  const RouteResult({
    required this.summary,
    required this.bucketId,
    required this.type,
    required this.confidence,
  });

  final String summary;
  final String? bucketId;
  final ItemType? type;
  final double confidence;
}

/// Live routing knobs read from Settings at route-time (toggles take effect
/// without an app restart).
class RouterTuning {
  const RouterTuning({
    this.greedy = true,
  });

  final bool greedy;
}

/// A past user correction (note → bucketId), fed back as a few-shot example so
/// routing personalises over time.
class CorrectionExample {
  const CorrectionExample({required this.note, required this.bucketId});
  final String note;
  final String bucketId;
}

/// True for transcripts not worth routing (silence / non-speech / too short).
/// Handled BEFORE loading the LLM; the caller files these straight to Unsorted.
/// Deliberately conservative — only obvious noise, never real bracketed notes
/// like "(call mom)".
bool isGarbageTranscript(String transcript, Duration audioDuration) {
  final t = transcript.trim();
  if (t.isEmpty) return true;
  if (audioDuration < const Duration(milliseconds: 500)) return true;
  // No real word (a run of >=2 letters).
  if (!RegExp(r'[A-Za-z]{2,}').hasMatch(t)) return true;
  // Whole transcript is just a known Whisper non-speech marker.
  // Strip ALL known Whisper non-speech markers; if no real word remains it's
  // garbage. Catches repeated/multiple markers ("[BLANK_AUDIO] [BLANK_AUDIO]",
  // "(buzzing) (silence)") while keeping real bracketed notes like "(call mom)".
  final markerPattern = RegExp(
    r'\[blank_audio\]|\[silence\]|\(silence\)|\(buzzing\)|\(buzz\)|'
    r'\(wind(?: blowing)?\)|\(music(?: playing)?\)|\(noise\)|\(static\)|'
    r'\(beep(?:ing)?\)|\(clicking\)|\(coughing\)|\(breathing\)|\(inaudible\)|'
    r'blank_audio',
    caseSensitive: false,
  );
  final stripped = t.replaceAll(markerPattern, ' ');
  if (!RegExp(r'[A-Za-z]{2,}').hasMatch(stripped)) return true;
  return false;
}

/// Tokens that may precede "to/in `<bucket>`" in a PURE routing preamble
/// ("add to X", "put this in X, …"). If any leading token is NOT in this set
/// the head of the utterance carries content and must not be stripped
/// ("fix the login for webapp …", "buy supplies for shopping trip").
const Set<String> _kRoutingFiller = {
  'add', 'put', 'file', 'save', 'note', 'new', 'this', 'it', 'that',
  'a', 'an', 'the', 'um', 'uh', 'okay', 'ok', 'so', 'please', 'and',
  'also', 'to',
};

/// Type-framing words that may also precede "for/to `<bucket>`" in a pure
/// routing preamble ("bug report for devhub …", "idea for dev hub …"). They
/// carry the TYPE hint, not content — the LLM/typeHeuristic recovers the
/// type, so the head is safe to strip. Content verbs ("fix", "buy") are in
/// neither set, which keeps "fix the login for webapp …" protected.
const Set<String> _kTypeFramingFiller = {
  'bug', 'issue', 'improvement', 'idea', 'report', 'reminder', 'todo',
};

/// Strip "add to `<bucket>` [list]: " style preambles. Strips ONLY when:
///  - the match was on the bucket's NAME/id ([ExplicitMatch.matchedOnName]) —
///    a keyword match routes but never strips ("remind me to call mom" keeps
///    its full content even though 'call' is a todos keyword);
///  - the preposition sits within the first few tokens; and
///  - every token before the preposition is routing filler.
String stripRoutingPreamble(String transcript, ExplicitMatch m) {
  if (!m.matchedOnName) return transcript; // keyword match — never strip
  if (m.prepositionTokenIndex > 3) return transcript; // mid-sentence "to X" — leave it
  if (!m.leadingTokens.every((t) =>
      _kRoutingFiller.contains(t) || _kTypeFramingFiller.contains(t))) {
    return transcript; // head carries content — leave it
  }
  var rest = transcript.substring(m.matchEndCharIndex);
  rest = rest.replaceFirst(
      RegExp(r"^\s*(?:list|project|bucket)?\s*[:,\-–.]?\s*",
          caseSensitive: false),
      '');
  return rest.trim().length >= 4 ? rest.trim() : transcript; // never strip to nothing
}

/// Post-strip a model summary: remove a LEADING bucket id/name and a LEADING
/// type-word ("bug:", "a bug with", "idea for", …). Each pass does
/// (bucket-name strip → type-word strip); two passes handle the compound
/// "webapp bug: …" shape (pass 1 drops "webapp", pass 2 drops "bug:").
/// The bucket-name rule REQUIRES an actual separator OR a following
/// type-word, so a content title like "shopping cart icon misaligned"
/// survives. The type-word rule REQUIRES a separator/connector, so a genuine
/// content title like "improvement of compost mixing" survives ("of" doesn't
/// match). Never strips to junk — returns the original string if the result
/// would be shorter than 3 chars.
String cleanSummary(String s, List<BucketInfo> buckets) {
  var out = s.trim();
  final names =
      buckets.expand((b) => [b.id, b.name]).map(RegExp.escape).join('|');
  for (var pass = 0; pass < 2; pass++) {
    // 1) leading bucket id/name, ONLY when followed by a real separator
    //    ("webapp: …", "webapp - …") or by a type-word ("webapp bug: …" —
    //    the compound shape pass 2 then finishes). A bare bucket word that is
    //    part of the content ("shopping cart …") is kept.
    if (names.isNotEmpty) {
      out = out.replaceFirst(
          RegExp(
              '^(?:$names)\\b\\s*'
              '(?:[:,\\-–.]\\s*|(?=(?:bug|issue|improvement|idea)\\b))',
              caseSensitive: false),
          '');
    }
    // 2) leading type-word with separator or connector:
    //    "bug: x", "bug - x", "a bug with x", "idea for x", "bug report: x".
    out = out.replaceFirst(
        RegExp(
            r'^(?:a\s+|an\s+)?(?:bug|issue|improvement|idea)\s*(?:report)?\s*'
            r'(?::|-|–|\bfor\b|\babout\b|\bwith\b)\s*',
            caseSensitive: false),
        '');
  }
  out = out.trim();
  return out.length >= 3 ? out : s; // never return junk
}

/// Keyword fallback for a project item's type when the model didn't give one.
/// First hit wins, in priority order bug → issue → improvement; null when no
/// keyword matches (the UI renders untyped project items in their own section).
@visibleForTesting
ItemType? typeHeuristic(String text) {
  final bug = RegExp(
      r'\b(bug|bugs|broken|crash|crashes|crashing|fails?|failing|error|errors)\b',
      caseSensitive: false);
  final notWorking = RegExp(r"(doesn'?t|does not|isn'?t|not)\s+work",
      caseSensitive: false);
  if (bug.hasMatch(text) || notWorking.hasMatch(text)) return ItemType.bug;
  if (RegExp(r'\b(issue|problem|blocked|stuck)\b', caseSensitive: false)
      .hasMatch(text)) {
    return ItemType.issue;
  }
  if (RegExp(r'\b(idea|ideas|feature|improve|improvement|add|could|should)\b',
          caseSensitive: false)
      .hasMatch(text)) {
    return ItemType.improvement;
  }
  return null;
}

/// Runs the selected on-device LLM via fllama to summarise a transcript and
/// route it to a bucket in a single combined LLM call.
/// Heavy inference runs on fllama's native thread — no UI-isolate blocking.
class Router {
  Router({LlmFamily family = LlmFamily.qwen3})
      // ignore: prefer_initializing_formals
      : _family = family;

  /// Threads for llama.cpp init + completions. SD 8 Gen 2 = 1×X3 + 2×A715 +
  /// 2×A710 + 3×A510; >5 threads puts work on the A510 little cores, and
  /// llama.cpp's per-op sync makes the slowest core gate every layer — 8 (the
  /// old completion value) was measurably wrong. 4-6 should be swept on-device.
  static const int kLlmThreads = 5;

  double? _contextId;
  Future<void>? _warmFuture;

  /// When set (by the pipeline), raw startup-stage events are reported here
  /// so the provider layer can drive the dashboard's staged progress bar.
  void Function(StartupEvent)? onStartupEvent;

  /// The active model family; controls prompt template and stop tokens.
  LlmFamily _family;

  /// True when a Qwen3 model is active; controls `/no_think` injection and
  /// `<think>…</think>` stripping.
  bool get _isQwen3 => _family == LlmFamily.qwen3;

  /// Load the GGUF and store the contextId for later completions.
  /// Pass [family] to select the prompt template for the loaded model.
  Future<void> init(ModelPaths paths, {LlmFamily? family}) async {
    if (family != null) _family = family;
    // Warm-state cache location: next to the GGUF, tagged by model filename
    // (e.g. warm-qwen3-1.7b-q4_k_m-<fp>.state) — see _doWarmUpImpl.
    final slash = paths.qwenGguf.lastIndexOf('/');
    if (slash > 0) {
      _warmStateDir = paths.qwenGguf.substring(0, slash);
      _modelTag = paths.qwenGguf
          .substring(slash + 1)
          .replaceAll(RegExp(r'\.gguf$'), '');
    }
    // Memory mode is family-conditional. The 4B-class model (Gemma, 2.4 GB
    // Q4_K_M) loaded with useMmap:false becomes ANONYMOUS memory: under
    // pressure the kernel can only reclaim it by compressing into zram swap.
    // Field result on the S23+ (v0.1.06): ~2.9 GB swapped, inference thrashed
    // at <10 tok/s (the "60s warm-up"), and lmkd killed the FOREGROUND app on
    // the next capture ("min2x watermark breached even after kill").
    // useMmap:true makes the weights file-backed: reclaimable without swap,
    // re-faulted from flash, LMK-safe. Small models (<1 GB Qwen3) stay
    // resident — they fit comfortably and avoid mmap's first-touch faults.
    // mlock is dropped for the big model: pinning 2.4 GB never succeeds
    // unprivileged and fights the reclaimer.
    final bigModel = _family == LlmFamily.gemma;
    final sw = Stopwatch()..start();
    onStartupEvent?.call(LlmLoadStart(_modelTag ?? 'model'));
    // Native model-load progress: with emitLoadProgress the Kotlin layer emits
    // {'function': 'loadProgress', 'contextId': '', 'result': <int 0-100>} on
    // the broadcast EventChannel. Subscribe ONLY around the initContext await.
    StreamSubscription<Map<Object?, dynamic>>? progressSub;
    final events = Fllama.instance()!.onTokenStream;
    if (events != null) {
      progressSub = events.listen(
        (event) {
          if (event['function'] == 'loadProgress') {
            final p = event['result'];
            if (p is num) onStartupEvent?.call(LlmLoadProgress(p.toInt()));
          }
        },
        onError: (Object _) {}, // channel errors must never crash init
      );
    }
    Map<Object?, dynamic>? result;
    try {
      result = await Fllama.instance()!.initContext(
        paths.qwenGguf,
        nCtx: 2048,
        nBatch: 1024,
        nGpuLayers: 0, // CPU-only build
        nThreads: kLlmThreads,
        useMlock: !bigModel,
        useMmap: bigModel,
        emitLoadProgress: true,
      );
    } finally {
      await progressSub?.cancel();
    }
    sw.stop();
    if (result == null) {
      throw StateError('fllama initContext returned null for ${paths.qwenGguf}');
    }
    _contextId = (result['contextId'] as num).toDouble();
    onStartupEvent?.call(const LlmLoadDone());
    AppLog.instance.log(
      'llm',
      'model loaded in ${sw.elapsedMilliseconds}ms',
    );
  }

  /// Stop any in-flight completion, release the current context, then re-init.
  /// Pass [family] to select the prompt template for the new model.
  Future<void> reinit(ModelPaths paths,
      {LlmFamily family = LlmFamily.qwen3}) async {
    // Abort any in-flight native completion (warm-up or route) FIRST so the
    // serialized chain below drains fast instead of running to completion,
    // then let the chain drain before the context is torn down. Warm-up runs
    // on the same chain as route() (see _doWarmUp), so this await covers
    // both — releasing the context under a live completion is a native
    // use-after-free (the Kotlin layer runs each call on its own coroutine,
    // so release is NOT serialized behind an in-flight completion).
    final ctx = _contextId;
    if (ctx != null) {
      await Fllama.instance()?.stopCompletion(contextId: ctx);
    }
    try {
      await _routeSerial;
    } catch (_) {}
    await _stopAndRelease();
    await init(paths, family: family);
    // New native context: page it back in so the next route is fast.
    _warmFuture = null;
    unawaited(warmUp());
  }

  /// Warm the compute graph with a small completion so the first real route is
  /// instant. The logged timing is also our headless speed check (the emulator
  /// has no mic): on an optimized build this is well under a second.
  /// Page the model into RAM + warm the compute graph with a realistic
  /// (route-sized) prefill so the FIRST real route is fast. The model is mmap'd
  /// and mlock can't pin ~1GB, so the first forward pass faults all weights in
  /// from storage (~10s) — doing it here, behind the startup splash, keeps the
  /// user's sorts ~2s. route() awaits this. Idempotent per context.
  Future<void> warmUp() => _warmFuture ??= _doWarmUp();

  /// When set (by the pipeline), warm-up builds its prompt from the REAL
  /// buckets so the prefilled system-prompt prefix matches the first real
  /// route exactly (same pages, same graph shape). Falls back to dummy lines.
  List<BucketInfo> Function()? warmBucketsProvider;

  static const String _kWarmNote = 'warm up with a note about buying milk';

  /// Warm-up runs through the SAME serialized chain as route(): the native
  /// context only ever executes one completion at a time, and reinit's
  /// `await _routeSerial` therefore covers an in-flight warm-up too.
  Future<void> _doWarmUp() {
    final work = _routeSerial.then((_) => _doWarmUpImpl());
    _routeSerial = work.then<void>((_) {}, onError: (_) {});
    return work;
  }

  Future<void> _doWarmUpImpl() async {
    final ctx = _contextId;
    if (ctx == null) return;
    // Warm with a REPRESENTATIVE real prompt (full persona + a few category
    // lines + a dummy note) so the compute graph/buffers + the system-prompt
    // prefix are warmed for the REAL route shape — the first real sort then
    // isn't slow.
    const dummyLines =
        '- shopping [L] Shopping — things to buy · kw: buy, groceries\n'
        '- todos [L] To-dos — tasks and chores · kw: task, chore, remind\n'
        '- devhub [P] devhub — developer tools app · kw: build, deploy, api';
    final wb = warmBucketsProvider?.call();
    final lines = (wb != null && wb.isNotEmpty)
        ? _buildBucketLines(wb, _kWarmNote)
        : dummyLines;
    final built = _promptFor(lines, _kWarmNote);
    final warmPrompt = built.prompt;
    final warmStop = built.stop;

    // Cold-start shortcut: the warm-up's only product is the prefilled KV of
    // the static prefix. That state is saved to disk after a successful
    // warm-up, fingerprinted by (model, exact warm prompt) — so a relaunch
    // RESTORES it in a few hundred ms instead of re-prefilling ~560 tokens
    // for ~12s. Any prompt/bucket/model change → different fingerprint →
    // normal warm-up + fresh save (stale files are cleaned on save).
    final statePath = _warmStatePathFor(warmPrompt);
    if (statePath != null && await _tryRestoreWarmState(ctx, statePath)) {
      return;
    }

    final sw = Stopwatch()..start();
    try {
      onStartupEvent?.call(const WarmPrefillStart());
      final raw = await Fllama.instance()!
          .completion(ctx,
              prompt: warmPrompt,
              temperature: 0.0,
              nThreads: kLlmThreads,
              nPredict: 4,
              stop: warmStop)
          .timeout(const Duration(seconds: 60), onTimeout: () {
        Fllama.instance()?.stopCompletion(contextId: ctx);
        return null;
      });
      sw.stop();
      if (raw == null) {
        // A timeout here is a red flag, not a success: on a healthy device
        // the warm prefill takes seconds. The usual cause is memory pressure
        // swapping the weights (see init's memory-mode comment).
        AppLog.instance.log(
            'llm',
            'warmup TIMED OUT after ${sw.elapsedMilliseconds}ms — '
            'inference is likely memory-thrashed',
            level: LogLevel.warn);
        // Still resolve the bar — the pipeline marks ready regardless.
        onStartupEvent?.call(WarmDone(sw.elapsedMilliseconds));
      } else {
        AppLog.instance.log(
            'llm', 'warmup (model paged) took ${sw.elapsedMilliseconds}ms');
        if (statePath != null) {
          await _saveWarmState(ctx, statePath);
        }
        // After the save, so the bar doesn't finish before the save blink.
        onStartupEvent?.call(WarmDone(sw.elapsedMilliseconds));
      }
    } catch (e) {
      AppLog.instance.log('llm', 'warmup failed: $e', level: LogLevel.warn);
      onStartupEvent?.call(WarmDone(sw.elapsedMilliseconds));
    }
  }

  // ── Warm-state persistence (cold-start shortcut) ───────────────────────────

  /// Directory + model tag for warm-state files; set in [init] from the GGUF
  /// path. Null until the first init (warm-state silently disabled then).
  String? _warmStateDir;
  String? _modelTag;

  /// FNV-1a over the exact warm prompt + model tag: deterministic across
  /// launches (Dart's hashCode is not), cheap, and any byte change in the
  /// persona/Categories/model invalidates the saved state.
  static String _fingerprint(String s) {
    var h = 0x811c9dc5;
    for (final c in s.codeUnits) {
      h ^= c;
      h = (h * 0x01000193) & 0xFFFFFFFF;
    }
    return h.toRadixString(16).padLeft(8, '0');
  }

  String? _warmStatePathFor(String warmPrompt) {
    final dir = _warmStateDir;
    final tag = _modelTag;
    if (dir == null || tag == null) return null;
    return '$dir/warm-$tag-${_fingerprint('$tag|$warmPrompt')}.state';
  }

  /// Restore the prefilled KV from [path]. True = restored (skip the warm-up
  /// completion). Any failure deletes the file and falls back to a normal
  /// warm-up — the state file is a pure cache.
  Future<bool> _tryRestoreWarmState(double ctx, String path) async {
    try {
      if (!await File(path).exists()) return false;
      onStartupEvent?.call(const WarmRestoreStart());
      final sw = Stopwatch()..start();
      final res = await Fllama.instance()!.loadSession(ctx, path: path);
      sw.stop();
      final tokens = res?['tokens_loaded'];
      if (res == null || res['error'] != null || tokens is! num || tokens <= 0) {
        throw StateError('loadSession returned ${res ?? 'null'}');
      }
      AppLog.instance.log(
          'llm',
          'warm state RESTORED ($tokens tokens) in ${sw.elapsedMilliseconds}ms '
          '— cold-start prefill skipped');
      onStartupEvent?.call(WarmDone(sw.elapsedMilliseconds));
      return true;
    } catch (e) {
      AppLog.instance.log(
          'llm', 'warm-state restore failed ($e) — deleting + re-warming',
          level: LogLevel.warn);
      try {
        await File(path).delete();
      } catch (_) {}
      return false;
    }
  }

  /// Save the warmed KV to [path] and prune stale sibling states for this
  /// model (old fingerprints from before a bucket/prompt change).
  Future<void> _saveWarmState(double ctx, String path) async {
    try {
      final sw = Stopwatch()..start();
      final n =
          await Fllama.instance()!.saveSession(ctx, path: path, size: 0);
      sw.stop();
      if (n == null || n <= 0) {
        AppLog.instance.log('llm', 'warm-state save returned $n',
            level: LogLevel.warn);
        return;
      }
      AppLog.instance.log('llm',
          'warm state saved ($n tokens) in ${sw.elapsedMilliseconds}ms');
      final dir = Directory(_warmStateDir!);
      final tag = _modelTag!;
      final keep = path.split('/').last;
      await for (final f in dir.list()) {
        final name = f.path.split('/').last;
        if (f is File && name.startsWith('warm-$tag-') && name != keep) {
          try {
            await f.delete();
          } catch (_) {}
        }
      }
    } catch (e) {
      AppLog.instance.log('llm', 'warm-state save failed: $e',
          level: LogLevel.warn);
    }
  }

  /// Shared persona/instruction block (v2). Hard NEVER-start rule + few-shots
  /// that are byte-for-byte the observed failure shape ("add to `<bucket>`
  /// list a `<type>` with `<content>`"), ~35% shorter than v1 for free
  /// prefill savings.
  static const String _kPersona =
      'You turn a raw voice transcript into a one-line note.\n'
      '\n'
      'Title rules:\n'
      '- 3 to 8 words describing WHAT the note is about — content only.\n'
      '- NEVER start the title with a category/list name or with the words\n'
      '  bug, issue, improvement, idea, note, report.\n'
      '- Routing phrases carry no content — drop them entirely:\n'
      '  "add to <x>", "put on <x> list", "bug report for <x>", "idea for <x>", "note about <x>".\n'
      '\n'
      'Pick ONE category below by name/description/keywords; if the transcript names one, use it;\n'
      'if none fits, use "unsorted". For a [P] category give a type (improvement, bug or issue);\n'
      'for an [L] category use "-".\n'
      '\n'
      'Reply with ONE line only, exactly:\n'
      'title | type -> category\n'
      '\n'
      'Examples:\n'
      'Input: um add to shopping I need to buy some more bread\n'
      'buy bread | - -> shopping\n'
      'Input: add to webapp list a bug with adding a new user on firefox\n'
      'adding new user fails on firefox | bug -> webapp\n'
      'Input: bug report for dev hub the build keeps failing after a minute\n'
      'the build keeps failing | bug -> devhub\n'
      'Input: put milk and eggs on the shopping list\n'
      'buy milk and eggs | - -> shopping\n'
      'Input: idea for dev hub we could add a dark mode toggle to the dashboard\n'
      'add dark mode toggle | improvement -> devhub\n'
      'Input: webapp the login button is totally broken when you tap it nothing happens\n'
      'login button unresponsive | bug -> webapp';

  /// Builds the family-specific prompt + stop + decode budget for a
  /// bucket-line block + a transcript. Shared by [_classifyOne] and
  /// [_doWarmUp] so the warmup prefills the SAME shape as a real route (warms
  /// the graph + the system-prompt prefix so the first real sort isn't slow).
  ///
  /// Stop tokens are family-aware: Gemma emits a clean one-liner, so '\n' is a
  /// stop (saves 1-3s of wasted decode) — the '\n' stop is Gemma's real cap,
  /// and nPredict stays 32 for BOTH families (24 risked truncating before the
  /// '->' and silently routing to Unsorted). Qwen3 keeps only its turn token —
  /// even with /no_think it may emit an empty `<think>\n\n</think>` block
  /// first, and a '\n' stop would truncate inside it and force the transcript
  /// fallback.
  ({String prompt, List<String> stop, int nPredict}) _promptFor(
      String bucketLines, String transcript) {
    if (_family == LlmFamily.gemma) {
      // Gemma has no system role — persona goes into the user turn. The
      // tokenizer adds <bos> automatically; do NOT prepend it here.
      return (
        prompt: '<start_of_turn>user\n'
            '$_kPersona\n'
            '\n'
            'Categories:\n'
            '$bucketLines\n'
            'Input: $transcript<end_of_turn>\n'
            '<start_of_turn>model\n',
        stop: const ['<end_of_turn>', '\n'],
        nPredict: 32,
      );
    }
    // Qwen3: append /no_think to disable the reasoning chain.
    return (
      prompt: '<|im_start|>system\n'
          '$_kPersona /no_think<|im_end|>\n'
          '<|im_start|>user\n'
          'Categories:\n'
          '$bucketLines\n'
          'Input: $transcript<|im_end|>\n'
          '<|im_start|>assistant\n',
      stop: const ['<|im_end|>'],
      nPredict: 32,
    );
  }

  // ---------------------------------------------------------------------------
  // Public route() — deterministic-first, then one combined LLM call
  // ---------------------------------------------------------------------------

  /// Route [transcript] to a bucket.
  ///
  /// Flow:
  /// 1. Garbage guard (no LLM).
  /// 2. Await warm-up.
  /// 3. [explicitTarget] — high-precision "to/in `<name>`" match on transcript;
  ///    on a head-of-utterance match, [stripRoutingPreamble] removes the
  ///    routing preamble before the LLM sees it.
  /// 4. `_classifyOne` — single LLM call: summary + bucket + type together.
  /// 5. If explicit target found: return with summary + explicit id (overrides LLM bucket).
  /// 6. Else use LLM bucket if found, else [deterministicMatch] rescue.
  /// 7. Else unsorted.
  ///
  /// [tuning]/[corrections] params are kept for API compatibility; corrections
  /// are not used in prompts (the 1.5B model copied example notes verbatim).
  Future<RouteResult> route({
    required String transcript,
    required Duration audioDuration,
    required List<BucketInfo> buckets,
    RouterTuning tuning = const RouterTuning(),
    List<CorrectionExample> corrections = const [],
  }) {
    // Serialize route() calls: with background routing a NEW capture can call
    // route() while the previous background route is still running on the SAME
    // native context (fllama startCompletion is not re-entrant — concurrent
    // calls race on llama->params and the KV cache). Calls chain FIFO; the
    // chain itself swallows failures so one bad route never wedges the next.
    final result = _routeSerial.then((_) => _routeImpl(
          transcript: transcript,
          audioDuration: audioDuration,
          buckets: buckets,
          tuning: tuning,
          corrections: corrections,
        ));
    _routeSerial = result.then<void>((_) {}, onError: (_) {});
    return result;
  }

  /// Tail of the route-serialization chain; see [route].
  Future<void> _routeSerial = Future.value();

  Future<RouteResult> _routeImpl({
    required String transcript,
    required Duration audioDuration,
    required List<BucketInfo> buckets,
    RouterTuning tuning = const RouterTuning(),
    List<CorrectionExample> corrections = const [],
  }) async {
    final contextId = _contextId;
    if (contextId == null) throw StateError('Router.init() has not been called');

    AppLog.instance.log(
      'llm',
      'ROUTE in: transcript="$transcript" dur=${audioDuration.inMilliseconds}ms '
      'buckets=${buckets.length} corrections=${corrections.length} '
      'greedy=${tuning.greedy}',
    );

    // Defence in depth — the pipeline short-circuits garbage before loading the
    // LLM, but never route noise even if route() is called directly.
    if (isGarbageTranscript(transcript, audioDuration)) {
      AppLog.instance.log('llm', 'garbage transcript -> unsorted (no LLM)');
      return RouteResult(
          summary: transcript.trim(), bucketId: null, type: null, confidence: 0.0);
    }

    // Make sure the model is paged in (warmUp) before routing, so the first sort
    // doesn't eat the ~10s mmap page-fault.
    final wf = _warmFuture;
    if (wf != null) {
      try {
        await wf;
      } catch (_) {}
    }

    final match = explicitTarget(transcript, buckets);                     // authoritative
    // Pre-strip the routing preamble so the LLM never sees (and can't echo)
    // the bucket name; its fallback summary is then preamble-free too.
    final llmInput =
        match != null ? stripRoutingPreamble(transcript, match) : transcript;
    final detId = match?.bucketId;
    final sw = Stopwatch()..start();
    final r = await _classifyOne(contextId, llmInput, buckets, tuning);  // single LLM call
    sw.stop();
    AppLog.instance.log('llm', 'classify took ${sw.elapsedMilliseconds}ms');
    final rawSummary = r.summary.isNotEmpty ? r.summary : llmInput.trim();
    final summary = cleanSummary(rawSummary, buckets);
    var bucketId = detId ?? r.bucketId;
    var conf = detId != null ? 0.95 : (r.bucketId != null ? 0.9 : 0.0);
    if (bucketId == null) {
      final rescue = deterministicMatch(transcript, buckets);
      if (rescue != null) { bucketId = rescue; conf = 0.7; }
    }
    if (bucketId == null) {
      AppLog.instance.log('llm', 'routed -> unsorted (no match)');
      return RouteResult(summary: summary, bucketId: null, type: null, confidence: 0.3);
    }
    final b = buckets.firstWhere((x) => x.id == bucketId, orElse: () => const BucketInfo(id: '', name: '', isProject: false));
    // No silent `improvement` default — a mislabeled bug looks intentional,
    // visibly-untyped doesn't. Model type wins; else keyword heuristic; else null.
    // Heuristic runs on the ORIGINAL transcript: the preamble strip removes
    // type-framing words ("bug report for …"), but they are exactly the
    // signal the fallback typing needs when the model omits the type.
    final type = b.isProject ? (r.type ?? typeHeuristic(transcript)) : null;
    AppLog.instance.log('llm', 'routed -> $bucketId conf=${conf.toStringAsFixed(2)} type=${type?.name ?? "null"}');
    return RouteResult(summary: summary, bucketId: bucketId, type: type, confidence: conf);
  }

  // ---------------------------------------------------------------------------
  // Single combined LLM call: classify (summary + bucket + type)
  // ---------------------------------------------------------------------------

  /// Regex that matches a Qwen3 `<think>…</think>` reasoning block (dotAll so
  /// `.` crosses newlines). Stripped from raw output before parsing.
  static final _thinkPattern = RegExp(r'<think>.*?</think>', dotAll: true);

  Future<({String summary, String? bucketId, ItemType? type})> _classifyOne(
    double ctx,
    String transcript,
    List<BucketInfo> buckets,
    RouterTuning tuning,
  ) async {
    final bucketLines = _buildBucketLines(buckets, transcript);
    final built = _promptFor(bucketLines, transcript);
    final prompt = built.prompt;
    final stop = built.stop;

    AppLog.instance.log('llm', 'PROMPT >>>\n$prompt');
    try {
      final raw = await Fllama.instance()!
          .completion(
            ctx,
            prompt: prompt,
            temperature: tuning.greedy ? 0.0 : 0.2,
            nThreads: kLlmThreads,
            nPredict: built.nPredict,
            stop: stop,
          )
          .timeout(
            const Duration(seconds: 30),
            onTimeout: () async {
              await Fllama.instance()?.stopCompletion(contextId: ctx);
              return null;
            },
          );
      var text = (raw?['text'] as String?) ?? '';
      // Strip any Qwen3 <think>…</think> reasoning block before parsing so it
      // never reaches parseClassify and corrupts summary/category/type.
      if (_isQwen3) text = text.replaceAll(_thinkPattern, '').trimLeft();
      AppLog.instance.log('llm', 'RAW out: "$text"');
      // KV-prefix cache effectiveness (S9): evaluated = prompt tokens actually
      // prefilled this call; cached = tokens reused from the previous prompt's
      // KV. With the static persona+Categories prefix warmed (S4), evaluated
      // should collapse to ~the transcript length on full-attention models
      // (Qwen3); SWA models (Gemma 3) full-reprocess by design — see
      // fllama.hpp loadPrompt.
      final evaluated = raw?['tokens_evaluated'];
      final cached = raw?['tokens_cached'];
      if (evaluated != null) {
        AppLog.instance.log('llm', 'prefill_evaluated=$evaluated kv_cached=$cached');
      }
      return parseClassify(text, buckets, transcript);
    } catch (e) {
      AppLog.instance.log('llm', 'classifyOne error: $e', level: LogLevel.warn);
      return (summary: transcript.trim(), bucketId: null, type: null);
    }
  }

  /// Parse "title | type -> category" output from [_classifyOne].
  /// Parses right-to-left: category follows the LAST '->'; type follows the
  /// LAST '|'; title is everything before the last '|'. A title that
  /// itself contains '|' or '->' (rare) therefore doesn't corrupt the tail.
  @visibleForTesting
  static ({String summary, String? bucketId, ItemType? type}) parseClassify(
    String raw,
    List<BucketInfo> buckets,
    String fallback,
  ) {
    final fallbackSummary = fallback.trim();

    // The model replies with one line "rewrite | type -> category". It may
    // still wrap it in a ```fence or prepend a short preamble, so pick the
    // first line that contains the '->' arrow.
    final line = raw
        .split('\n')
        .map((l) => l.trim())
        .firstWhere((l) => l.contains('->'), orElse: () => '');
    if (line.isEmpty) {
      return (summary: fallbackSummary, bucketId: null, type: null);
    }

    final arrow = line.lastIndexOf('->');
    final categoryRaw = line.substring(arrow + 2).trim();
    final left = line.substring(0, arrow).trim();

    String summaryRaw = left;
    String? typeRaw;
    final bar = left.lastIndexOf('|');
    if (bar != -1) {
      summaryRaw = left.substring(0, bar).trim();
      typeRaw = left.substring(bar + 1).trim();
    }

    // Strip leading/trailing brackets and quotes that the model sometimes adds.
    summaryRaw = summaryRaw.replaceAll(RegExp(r'^[<"`*\s]+|[>"`*\s]+$'), '');

    String? bucketId;
    if (categoryRaw.isNotEmpty && categoryRaw.toLowerCase() != 'unsorted') {
      // Match the id case-insensitively; fall back to the display NAME (the
      // model sometimes returns the name instead of the id). Avoids false
      // Unsorted routes from trivial case/whitespace/name drift.
      final lower = categoryRaw.toLowerCase();
      final byId = buckets.where((b) => b.id.toLowerCase() == lower);
      final byName = buckets.where((b) => b.name.toLowerCase() == lower);
      if (byId.isNotEmpty) {
        bucketId = byId.first.id;
      } else if (byName.isNotEmpty) {
        bucketId = byName.first.id;
      } else {
        // Fuzzy rescue: one misspelled token from the model ("webap",
        // "shoping") shouldn't cost a correct route. First match in bucket
        // order wins.
        final norm = lower.replaceAll(RegExp(r'[^a-z0-9]'), '');
        if (norm.isNotEmpty) {
          for (final b in buckets) {
            final id = b.id.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');
            final name =
                b.name.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');
            if (_fuzzyEq(norm, id) || _fuzzyEq(norm, name)) {
              bucketId = b.id;
              break;
            }
          }
        }
      }
    }

    final type = switch (typeRaw?.toLowerCase()) {
      'improvement' => ItemType.improvement,
      'bug' => ItemType.bug,
      'issue' => ItemType.issue,
      _ => null,
    };

    // Guard against model copying a bucket id/name as the summary.
    var summary = summaryRaw.isNotEmpty ? summaryRaw : fallbackSummary;
    final summaryLower = summary.toLowerCase();
    final isCategoryWord = summaryLower == 'unsorted' ||
        buckets.any((b) =>
            summaryLower == b.id.toLowerCase() ||
            summaryLower == b.name.toLowerCase());
    if (isCategoryWord) summary = fallbackSummary;

    return (summary: summary, bucketId: bucketId, type: type);
  }

  // ---------------------------------------------------------------------------
  // Shared bucket-line builder
  // ---------------------------------------------------------------------------

  // nCtx is fixed at 2048; the route prompt's nPredict is 32 for BOTH
  // families (see _promptFor), so this budget matches reality.
  // System+user framing adds ~300 tokens. Each bucket entry is at most ~40 tokens.
  static const int _nCtx = 2048;
  static const int _nPredictRoute = 32;
  static const int _fixedOverhead = 300; // persona system + framing + transcript est.
  static const int _tokensPerBucket = 40;

  /// Rough token count: 1 token ≈ 4 characters (conservative for English).
  static int _estimateTokens(String s) => (s.length / 4).ceil();

  /// Build compact bucket lines respecting the nCtx budget.
  /// Format: `- <id> [P|L] <name> — <desc> · kw: <keywords>`
  String _buildBucketLines(List<BucketInfo> buckets, String transcript) {
    final transcriptTokens = _estimateTokens(transcript);
    final available =
        _nCtx - _nPredictRoute - _fixedOverhead - transcriptTokens;
    final maxBuckets = buckets.isEmpty
        ? 0
        : (available / _tokensPerBucket).floor().clamp(1, buckets.length);
    final effectiveBuckets =
        buckets.length > maxBuckets ? buckets.sublist(0, maxBuckets) : buckets;
    if (effectiveBuckets.length < buckets.length) {
      AppLog.instance.log(
        'llm',
        'nCtx budget: capped buckets from ${buckets.length} to '
        '${effectiveBuckets.length} (transcript ~$transcriptTokens tok)',
        level: LogLevel.warn,
      );
    }

    return effectiveBuckets.map((b) {
      final kind = b.isProject ? 'P' : 'L';
      final extra = [
        if (b.description.trim().isNotEmpty) _clip(b.description),
        if (b.keywords.trim().isNotEmpty) 'kw: ${_clip(b.keywords)}',
      ].join(' · ');
      return '- ${b.id} [$kind] ${b.name}'
          '${extra.isNotEmpty ? ' — $extra' : ''}';
    }).join('\n');
  }

  /// Truncates a string so it doesn't blow the context budget.
  String _clip(String s) {
    final t = s.replaceAll('\n', ' ').trim();
    return t.length <= 48 ? t : '${t.substring(0, 45)}…';
  }

  // ---------------------------------------------------------------------------
  // Deterministic helpers (unchanged)
  // ---------------------------------------------------------------------------

  /// Deterministic fallback: if the transcript clearly contains a bucket's name
  /// or a distinctive (>=4 char) keyword, return that bucket id. Lets "add to
  /// General" land in General even when the LLM hesitates. Longest match wins.
  @visibleForTesting
  static String? deterministicMatch(String text, List<BucketInfo> buckets) {
    final lower = text.toLowerCase();
    final flat = lower.replaceAll(RegExp(r'[^a-z0-9]'), '');
    final tokens =
        lower.split(RegExp(r'[^a-z0-9]+')).where((s) => s.isNotEmpty).toList();
    // Adjacent-token bigrams catch mishearings that split a name into two
    // words ("web app" -> "webapp").
    final grams = <String>[...tokens];
    for (var i = 0; i + 1 < tokens.length; i++) {
      grams.add(tokens[i] + tokens[i + 1]);
    }
    String? best;
    double bestScore = 0;
    for (final b in buckets) {
      final candidates = <String>[b.name, ...b.keywords.split(RegExp(r'[,\n]'))];
      for (final raw in candidates) {
        final c = raw.trim().toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');
        if (c.length < 4) continue;
        // Exact substring (e.g. the model's normalized summary contains "devhub").
        if (flat.contains(c)) {
          if (1.0 > bestScore) {
            bestScore = 1.0;
            best = b.id;
          }
          continue;
        }
        // Fuzzy: edit-distance vs each token / bigram, for misheard proper
        // nouns ("devhubb"->"devhub", "webbapp"->"webapp").
        for (final g in grams) {
          if ((g.length - c.length).abs() > 2) continue;
          final d = _lev(g, c);
          final maxLen = g.length > c.length ? g.length : c.length;
          final score = 1.0 - d / maxLen;
          if (d <= 2 && score >= 0.75 && score > bestScore) {
            bestScore = score;
            best = b.id;
          }
        }
      }
    }
    return best;
  }

  /// Returns an [ExplicitMatch] when the note explicitly routes to a bucket via
  /// a preposition ("add it to NAME", "in NAME"). High precision: only a token
  /// (or the next two joined) right after to/in/into/onto/for/under that
  /// fuzzily equals a bucket name/id/keyword. The match span lets
  /// [stripRoutingPreamble] cut the preamble before the LLM sees it.
  /// Tokenized over the ORIGINAL text (offsets valid by construction); each
  /// token is lowercased for comparison — never toLowerCase() the whole string
  /// first, which can change its length (İ/ß) and shift offsets.
  static ExplicitMatch? explicitTarget(String text, List<BucketInfo> buckets) {
    final tokens = RegExp(r'[a-zA-Z0-9]+').allMatches(text).toList();
    const preps = {'to', 'in', 'into', 'onto', 'for', 'under'};
    for (var i = 0; i + 1 < tokens.length; i++) {
      if (!preps.contains(tokens[i].group(0)!.toLowerCase())) continue;
      final cand1 = tokens[i + 1].group(0)!.toLowerCase();
      final cand2 = i + 2 < tokens.length
          ? cand1 + tokens[i + 2].group(0)!.toLowerCase()
          : null;
      for (final b in buckets) {
        // Name/id matches may strip the preamble (matchedOnName: true);
        // keyword matches still route but never strip.
        final candidateSets = [
          (raws: <String>[b.name, b.id], matchedOnName: true),
          (
            raws: b.keywords.split(RegExp(r'[,\n]')),
            matchedOnName: false,
          ),
        ];
        for (final set in candidateSets) {
          for (final raw in set.raws) {
            final c =
                raw.trim().toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');
            if (c.length < 3) continue;
            int? end;
            if (_fuzzyEq(cand1, c)) {
              end = tokens[i + 1].end;
            } else if (cand2 != null && _fuzzyEq(cand2, c)) {
              end = tokens[i + 2].end;
            }
            if (end != null) {
              return ExplicitMatch(
                bucketId: b.id,
                prepositionTokenIndex: i,
                matchEndCharIndex: end,
                matchedOnName: set.matchedOnName,
                leadingTokens: [
                  for (var j = 0; j < i; j++)
                    tokens[j].group(0)!.toLowerCase(),
                ],
              );
            }
          }
        }
      }
    }
    return null;
  }

  static bool _fuzzyEq(String a, String b) {
    if (a == b) return true;
    if ((a.length - b.length).abs() > 2) return false;
    final d = _lev(a, b);
    final maxLen = a.length > b.length ? a.length : b.length;
    return d <= 2 && (1.0 - d / maxLen) >= 0.7;
  }

  /// Levenshtein edit distance (small strings only).
  static int _lev(String a, String b) {
    final m = a.length, n = b.length;
    if (m == 0) return n;
    if (n == 0) return m;
    var prev = List<int>.generate(n + 1, (i) => i);
    var cur = List<int>.filled(n + 1, 0);
    for (var i = 1; i <= m; i++) {
      cur[0] = i;
      for (var j = 1; j <= n; j++) {
        final cost = a[i - 1] == b[j - 1] ? 0 : 1;
        final del = cur[j - 1] + 1;
        final ins = prev[j] + 1;
        final sub = prev[j - 1] + cost;
        var min = del < ins ? del : ins;
        if (sub < min) min = sub;
        cur[j] = min;
      }
      final tmp = prev;
      prev = cur;
      cur = tmp;
    }
    return prev[n];
  }

  /// Fire-and-forget teardown. [_stopAndRelease] first stops any in-flight
  /// completion before freeing the native context, so even unawaited the
  /// sequence is safe — the native thread cannot proceed past stopCompletion
  /// before releaseContext executes. A reinit always awaits _stopAndRelease
  /// directly, so there is no cross-init race.
  void dispose() {
    unawaited(_disposeAsync());
  }

  /// Same teardown discipline as [reinit]: abort the in-flight completion,
  /// drain the serialized chain, THEN release — releasing under a live
  /// completion is a native use-after-free.
  Future<void> _disposeAsync() async {
    final ctx = _contextId;
    if (ctx != null) {
      await Fllama.instance()?.stopCompletion(contextId: ctx);
    }
    try {
      await _routeSerial;
    } catch (_) {}
    await _stopAndRelease();
  }

  // ── Private helpers ────────────────────────────────────────────────────────

  /// Stop in-flight completion + release native context. Async so reinit()
  /// can await it, preventing the new context from racing the old context's
  /// native teardown (use-after-free if stop/release overlap with init).
  /// Safe to call on an already-disposed router.
  Future<void> _stopAndRelease() async {
    final id = _contextId;
    if (id != null) {
      // Stop any in-flight completion BEFORE freeing the context, else the
      // native llama.cpp thread touches freed memory (use-after-free).
      await Fllama.instance()?.stopCompletion(contextId: id);
      await Fllama.instance()?.releaseContext(id);
      _contextId = null;
    }
  }
}
