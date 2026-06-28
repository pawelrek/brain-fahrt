/// On-demand downloader for non-bundled LLM model files.
///
/// Downloads a GGUF to `<modelsDir>/<model.gguf>.part`, streams data while
/// reporting progress, verifies the SHA-256 (in a background isolate) after the
/// stream completes, then atomically renames `.part` → the final file. Supports
/// resume via HTTP Range. All file writes are async so the UI never blocks.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';

import 'model_paths.dart';
import 'model_registry.dart';

// ── Exception ─────────────────────────────────────────────────────────────────

/// Thrown by [ModelDownloader.download] for every failure condition. [message]
/// is user-presentable (it is shown directly in the Settings model-manager).
class ModelDownloadException implements Exception {
  const ModelDownloadException(
    this.message, {
    this.isMetered = false,
    this.isCancelled = false,
  });

  /// Convenience: the device is on a metered network and [download] was called
  /// with `allowMetered == false`.
  const ModelDownloadException.metered(String message)
      : this(message, isMetered: true);

  final String message;

  /// True when the failure is because the network is metered (Wi-Fi absent) and
  /// the caller did not pass `allowMetered: true`. The UI offers a
  /// "Download on mobile data?" affordance and retries with `allowMetered: true`.
  final bool isMetered;

  /// True when the download was cancelled via a [CancelToken]. The `.part` file
  /// is intentionally left on disk for resumption.
  final bool isCancelled;

  @override
  String toString() => 'ModelDownloadException: $message'
      '${isMetered ? ' (metered)' : ''}'
      '${isCancelled ? ' (cancelled)' : ''}';
}

// ── Downloader ────────────────────────────────────────────────────────────────

/// Stateless service for downloading non-bundled [LlmModel] files.
///
/// Pass an injectable [Dio] for testing; production calls `ModelDownloader()`.
class ModelDownloader {
  ModelDownloader([Dio? dio])
      : _dio = dio ??
            Dio(BaseOptions(
              connectTimeout: const Duration(seconds: 30),
              // Idle timeout BETWEEN received chunks (not the total transfer) —
              // safe for slow links, but catches a stalled stream so the UI
              // can't hang forever on the progress bar.
              receiveTimeout: const Duration(seconds: 60),
              // Let our own logic handle 206 (partial) and 416 (range past EOF)
              // instead of dio throwing; we reject >= 500 ourselves below.
              validateStatus: (s) => s != null && s < 500,
            ));

  final Dio _dio;

  static const int _maxAttempts = 3;

  /// Download [model] to the models directory.
  ///
  /// - [onProgress]: `(bytesReceived, totalBytes)`. May fire often — caller
  ///   throttles UI updates.
  /// - [cancelToken]: cancelling leaves the `.part` intact for resumption and
  ///   throws a [ModelDownloadException] with `isCancelled == true`.
  /// - [allowMetered]: when false (default) and not on Wi-Fi/ethernet, throws
  ///   [ModelDownloadException.metered].
  Future<void> download(
    LlmModel model, {
    void Function(int received, int total)? onProgress,
    CancelToken? cancelToken,
    bool allowMetered = false,
  }) async {
    if (model.bundled || model.downloadUrl == null) {
      throw const ModelDownloadException('not a downloadable model');
    }

    // ── Connectivity ──────────────────────────────────────────────────────────
    final results = await Connectivity().checkConnectivity();
    final hasWifi = results.contains(ConnectivityResult.wifi) ||
        results.contains(ConnectivityResult.ethernet);
    final hasAnyConnection =
        results.isNotEmpty && !results.every((r) => r == ConnectivityResult.none);
    if (!hasAnyConnection) {
      throw const ModelDownloadException('No internet connection');
    }
    if (!hasWifi && !allowMetered) {
      throw const ModelDownloadException.metered(
          'Wi-Fi not available — connect to Wi-Fi or allow mobile data');
    }

    // ── Resolve paths ─────────────────────────────────────────────────────────
    final dir = await ModelPaths.modelsDir();
    await Directory(dir).create(recursive: true);
    final target = '$dir/${model.gguf}';
    final part = '$target.part';

    if (await File(target).exists()) return; // idempotent — already downloaded

    // ── Attempt loop (retry transient network errors, resuming each time) ─────
    for (var attempt = 1; attempt <= _maxAttempts; attempt++) {
      try {
        await _downloadAttempt(
          model: model,
          url: model.downloadUrl!,
          target: target,
          part: part,
          onProgress: onProgress,
          cancelToken: cancelToken,
        );
        return; // success
      } on ModelDownloadException {
        // Our own signals are terminal (connectivity / HTTP / checksum / storage).
        rethrow;
      } on DioException catch (e) {
        if (e.type == DioExceptionType.cancel) {
          throw const ModelDownloadException('download cancelled',
              isCancelled: true);
        }
        final isTransient = e.type == DioExceptionType.connectionTimeout ||
            e.type == DioExceptionType.receiveTimeout ||
            e.type == DioExceptionType.connectionError;
        if (!isTransient || attempt == _maxAttempts) {
          throw const ModelDownloadException(
              'Network error — check your connection');
        }
        // Transient — retry; the .part persists so the next attempt resumes.
      }
    }
  }

  Future<void> _downloadAttempt({
    required LlmModel model,
    required String url,
    required String target,
    required String part,
    required void Function(int, int)? onProgress,
    required CancelToken? cancelToken,
  }) async {
    final partFile = File(part);
    var offset = partFile.existsSync() ? await partFile.length() : 0;

    final response = await _dio.get<ResponseBody>(
      url,
      options: Options(
        responseType: ResponseType.stream,
        headers: offset > 0 ? {'range': 'bytes=$offset-'} : null,
      ),
      cancelToken: cancelToken,
    );

    final statusCode = response.statusCode ?? 200;

    // 416 Range Not Satisfiable: our Range start is at/after EOF, i.e. the
    // `.part` already holds the whole file (e.g. the process was killed during
    // verification). Drain the empty body and verify the existing file as-is.
    if (statusCode == 416) {
      await response.data!.stream.drain<void>().catchError((_) {});
      await _verifyAndFinalize(model, partFile, target);
      return;
    }
    // Anything that isn't a full (200) or partial (206) body is a hard error.
    if (statusCode != 200 && statusCode != 206) {
      throw ModelDownloadException('Server error (HTTP $statusCode)');
    }
    // 200 means the server ignored our Range header → restart from scratch.
    if (statusCode == 200 && offset > 0) {
      if (partFile.existsSync()) await partFile.delete();
      offset = 0;
    }

    // ── Total size ────────────────────────────────────────────────────────────
    final contentRange = response.headers.value('content-range');
    int total;
    if (contentRange != null) {
      // e.g. "bytes 1234-5678/9999"
      final slash = contentRange.lastIndexOf('/');
      total = slash >= 0
          ? int.tryParse(contentRange.substring(slash + 1)) ??
              (model.sizeBytes ?? 0)
          : (model.sizeBytes ?? 0);
    } else {
      final contentLength =
          int.tryParse(response.headers.value('content-length') ?? '') ?? 0;
      total =
          contentLength > 0 ? offset + contentLength : (model.sizeBytes ?? 0);
    }

    // ── Stream to disk (async writes — never blocks the UI isolate) ───────────
    final raf = await partFile.open(
        mode: offset > 0 ? FileMode.writeOnlyAppend : FileMode.writeOnly);
    var bytesWritten = 0;
    try {
      await for (final chunk in response.data!.stream) {
        if (cancelToken?.isCancelled ?? false) {
          throw const ModelDownloadException('download cancelled',
              isCancelled: true);
        }
        await raf.writeFrom(chunk);
        bytesWritten += chunk.length;
        onProgress?.call(offset + bytesWritten, total);
      }
    } on ModelDownloadException {
      rethrow;
    } on FileSystemException {
      throw const ModelDownloadException('Not enough storage');
    } on DioException catch (e) {
      if (e.type == DioExceptionType.cancel) {
        throw const ModelDownloadException('download cancelled',
            isCancelled: true);
      }
      rethrow;
    } finally {
      await raf.flush();
      await raf.close();
    }

    await _verifyAndFinalize(model, partFile, target);
  }

  /// Verify the `.part` SHA-256 (MANDATORY) then atomically promote it to the
  /// final path. A model with no expected hash is never activated — the
  /// integrity gate is not optional.
  Future<void> _verifyAndFinalize(
      LlmModel model, File partFile, String target) async {
    final expected = model.sha256;
    if (expected == null) {
      if (partFile.existsSync()) await partFile.delete();
      throw const ModelDownloadException("Can't verify this model");
    }
    final computed = await _sha256OfFile(partFile.path);
    if (computed.toLowerCase() != expected.toLowerCase()) {
      if (partFile.existsSync()) await partFile.delete();
      throw const ModelDownloadException('Download corrupted — tap to retry');
    }
    await partFile.rename(target);
  }

  /// SHA-256 of a file, computed in a BACKGROUND ISOLATE so hashing a multi-GB
  /// file never blocks the UI isolate (which would risk an ANR).
  Future<String> _sha256OfFile(String path) =>
      Isolate.run(() => _sha256FileSync(path));
}

/// Synchronous, chunked SHA-256 of [path]. Top-level so it can run under
/// [Isolate.run]. Reads in 1 MB blocks — never loads the whole file into memory.
String _sha256FileSync(String path) {
  final raf = File(path).openSync();
  try {
    Digest? digest;
    final out =
        ChunkedConversionSink<Digest>.withCallback((list) => digest = list.single);
    final input = sha256.startChunkedConversion(out);
    final buf = Uint8List(1 << 20);
    while (true) {
      final n = raf.readIntoSync(buf);
      if (n <= 0) break;
      // The digest consumes bytes synchronously inside add(), so reusing buf
      // (and passing a view of the final short read) is safe.
      input.add(n == buf.length ? buf : Uint8List.sublistView(buf, 0, n));
    }
    input.close();
    return digest!.toString();
  } finally {
    raf.closeSync();
  }
}
