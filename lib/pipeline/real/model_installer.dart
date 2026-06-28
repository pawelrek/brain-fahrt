import 'package:flutter/services.dart';

/// Bridges to the native first-launch model unpacker (see MainActivity.kt):
/// it streams the model files bundled in the APK into the app's files dir so
/// sherpa-onnx + fllama can read them as real files.
class ModelInstaller {
  static const MethodChannel _channel = MethodChannel('slop/models');

  /// Unpacks the bundled model assets if they're not already on disk. Returns
  /// the number of files copied (0 after the first launch, or if there's no
  /// native side / no bundled models). Best-effort — never throws; the app
  /// falls back to the simulated pipeline if models end up missing.
  static Future<int> ensureInstalled() async {
    try {
      final copied = await _channel.invokeMethod<int>('ensureModels');
      return copied ?? 0;
    } catch (_) {
      return 0;
    }
  }
}
