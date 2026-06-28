package com.dotvoice.slop

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File

/**
 * Streams the model files bundled under assets/models/ into the app's external
 * files dir on first launch, so sherpa-onnx + fllama can read them as real
 * files. Streaming (1 MB buffer) avoids loading the 1.1 GB GGUF into RAM.
 */
class MainActivity : FlutterActivity() {
    private val channelName = "slop/models"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, channelName)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "ensureModels" -> Thread {
                        try {
                            val copied = copyModels()
                            runOnUiThread { result.success(copied) }
                        } catch (e: Exception) {
                            runOnUiThread { result.error("COPY_FAILED", e.message, null) }
                        }
                    }.start()
                    else -> result.notImplemented()
                }
            }
    }

    private fun copyModels(): Int {
        val assetDir = "models"
        val names = assets.list(assetDir) ?: arrayOf()
        val outDir = File(getExternalFilesDir(null), "models").apply { mkdirs() }
        var copied = 0
        for (name in names) {
            val outFile = File(outDir, name)
            // A complete file only exists once its .part was renamed, so a
            // present non-empty file means a prior copy finished — skip it.
            if (outFile.exists() && outFile.length() > 0L) continue
            val part = File(outDir, "$name.part")
            assets.open("$assetDir/$name").use { input ->
                part.outputStream().use { output ->
                    input.copyTo(output, 1 shl 20) // 1 MB buffer
                }
            }
            if (outFile.exists()) outFile.delete()
            if (!part.renameTo(outFile)) {
                part.delete() // clean up stale .part so a retry can start fresh
                throw Exception("renameTo failed for $name")
            }
            copied++
        }
        return copied
    }
}
