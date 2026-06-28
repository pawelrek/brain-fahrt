/// Riverpod state + controller for per-model download lifecycle.
///
/// Tracks whether each [LlmModel] is present, absent, currently downloading,
/// or failed. UI watches [modelManagerProvider] and calls controller methods
/// to start/cancel downloads.
library;

import 'dart:async';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/log/app_log.dart';
import '../pipeline/real/model_downloader.dart';
import '../pipeline/real/model_paths.dart';
import '../pipeline/real/model_registry.dart';

// ── State hierarchy ───────────────────────────────────────────────────────────

sealed class ModelDownloadState {
  const ModelDownloadState();
}

/// The model file is on disk (bundled or previously downloaded).
class ModelPresent extends ModelDownloadState {
  const ModelPresent();
}

/// The model file is not on disk and no download is in progress.
class ModelAbsent extends ModelDownloadState {
  const ModelAbsent();
}

/// A download is actively in progress.
class ModelDownloading extends ModelDownloadState {
  const ModelDownloading(this.received, this.total);

  final int received;
  final int total;

  /// 0.0–1.0 progress fraction; 0.0 when total is unknown.
  double get progress =>
      total > 0 ? (received / total).clamp(0.0, 1.0) : 0.0;
}

/// The last download attempt failed.
class ModelDownloadFailed extends ModelDownloadState {
  const ModelDownloadFailed(this.message, {this.isMetered = false});

  final String message;

  /// True when the failure was a metered-network rejection. The UI should
  /// offer a "Download on mobile data?" affordance.
  final bool isMetered;
}

// ── Controller ────────────────────────────────────────────────────────────────

/// Manages per-model [ModelDownloadState] for every [LlmModel] value.
///
/// Initial state is derived synchronously (bundled → [ModelPresent], others →
/// [ModelAbsent]), then corrected asynchronously by probing the filesystem.
class ModelManagerController
    extends Notifier<Map<LlmModel, ModelDownloadState>> {
  /// Live cancel tokens, one per active download.
  final Map<LlmModel, CancelToken> _tokens = {};

  /// Progress-throttle tracking: last emitted byte count per model.
  final Map<LlmModel, int> _lastEmitted = {};

  /// Emit a progress update at most every ~2 MB or ~0.5% of total.
  static const int _throttleBytes = 2 * 1024 * 1024; // 2 MB
  static const double _throttleFraction = 0.005; // 0.5%

  @override
  Map<LlmModel, ModelDownloadState> build() {
    // Synchronous initial state.
    final initial = <LlmModel, ModelDownloadState>{
      for (final m in LlmModel.values)
        m: m.bundled ? const ModelPresent() : const ModelAbsent(),
    };

    // Asynchronously probe disk for non-bundled models and correct.
    _probeExistingFiles();

    return initial;
  }

  Future<void> _probeExistingFiles() async {
    for (final m in LlmModel.values) {
      if (m.bundled) continue;
      try {
        final exists = await ModelPaths.modelExists(m.gguf);
        if (exists) {
          state = {...state, m: const ModelPresent()};
        }
      } catch (e) {
        AppLog.instance.log(
          'download',
          'probe failed for ${m.gguf}: $e',
          level: LogLevel.warn,
        );
      }
    }
  }

  /// Start downloading [m]. No-op if already [ModelDownloading].
  ///
  /// Pass [allowMetered] to proceed on cellular after the user confirms.
  Future<void> startDownload(LlmModel m, {bool allowMetered = false}) async {
    if (state[m] is ModelDownloading) return;

    // Seed progress from any existing `.part` so a resumed download starts at
    // the right place instead of snapping to 0% and jumping.
    final resumeFrom = await _partSize(m);
    _lastEmitted[m] = resumeFrom;
    state = {...state, m: ModelDownloading(resumeFrom, m.sizeBytes ?? 0)};

    final token = CancelToken();
    _tokens[m] = token;

    AppLog.instance.log('download', 'start ${m.gguf} allowMetered=$allowMetered');

    try {
      await ModelDownloader().download(
        m,
        cancelToken: token,
        allowMetered: allowMetered,
        onProgress: (received, total) {
          final last = _lastEmitted[m] ?? 0;
          final threshold = total > 0
              ? (total * _throttleFraction).round().clamp(_throttleBytes, _throttleBytes * 4)
              : _throttleBytes;
          // `received < last` fires on a restart (server ignored Range) so the
          // bar doesn't freeze at the old offset for the whole re-download.
          if (received < last || received - last >= threshold || received >= total) {
            _lastEmitted[m] = received;
            // Only update if still downloading (not cancelled/completed).
            if (state[m] is ModelDownloading) {
              state = {...state, m: ModelDownloading(received, total)};
            }
          }
        },
      );

      _tokens.remove(m);
      _lastEmitted.remove(m);
      state = {...state, m: const ModelPresent()};
      AppLog.instance.log('download', '${m.gguf} complete');
    } on ModelDownloadException catch (e) {
      _tokens.remove(m);
      _lastEmitted.remove(m);

      if (e.isCancelled) {
        // Check whether a partial file or the full file exists.
        final exists = await ModelPaths.modelExists(m.gguf);
        state = {...state, m: exists ? const ModelPresent() : const ModelAbsent()};
        AppLog.instance.log('download', '${m.gguf} cancelled');
      } else {
        state = {
          ...state,
          m: ModelDownloadFailed(e.message, isMetered: e.isMetered),
        };
        AppLog.instance.log(
          'download',
          '${m.gguf} failed: ${e.message}',
          level: LogLevel.error,
        );
      }
    } catch (e) {
      _tokens.remove(m);
      _lastEmitted.remove(m);
      state = {...state, m: const ModelDownloadFailed('Download failed')};
      AppLog.instance.log(
        'download',
        '${m.gguf} unexpected error: $e',
        level: LogLevel.error,
      );
    }
  }

  /// Size of any partially-downloaded `.part` for [m] (0 if none).
  Future<int> _partSize(LlmModel m) async {
    try {
      final f = File('${await ModelPaths.modelsDir()}/${m.gguf}.part');
      return await f.exists() ? await f.length() : 0;
    } catch (_) {
      return 0;
    }
  }

  /// Cancel an in-progress download for [m]. The `.part` file is preserved
  /// on disk so the next [startDownload] call will resume.
  void cancel(LlmModel m) {
    _tokens[m]?.cancel();
    AppLog.instance.log('download', 'cancel requested for ${m.gguf}');
  }
}

final modelManagerProvider =
    NotifierProvider<ModelManagerController, Map<LlmModel, ModelDownloadState>>(
  ModelManagerController.new,
);
