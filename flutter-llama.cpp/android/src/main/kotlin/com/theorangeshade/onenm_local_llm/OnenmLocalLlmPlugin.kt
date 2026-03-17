// Copyright 2026 1nm. All rights reserved.
// Use of this source code is governed by a MIT license that can be
// found in the LICENSE file.

package com.theorangeshade.onenm_local_llm

import android.content.Context
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.MethodChannel.MethodCallHandler
import io.flutter.plugin.common.MethodChannel.Result
import kotlinx.coroutines.*
import java.io.File
import java.io.FileOutputStream
import java.util.zip.ZipFile

/**
 * Flutter plugin for on-device LLM inference using llama.cpp.
 *
 * This plugin acts as the bridge between the Dart layer and [OneNmNative],
 * routing method-channel calls to the C++ backend via JNI.
 *
 * ## Supported methods
 *
 * | Method         | Arguments                               | Returns   |
 * |----------------|----------------------------------------|-----------|
 * | `pingNative`   | —                                      | `"pong"` |
 * | `loadModel`    | `modelPath: String`                    | `Boolean` |
 * | `generate`     | `prompt, temperature, topK, topP, ...` | `String`  |
 * | `releaseModel` | —                                      | `null`    |
 */
class OnenmLocalLlmPlugin: FlutterPlugin, MethodCallHandler {
  private lateinit var channel: MethodChannel

  /** Lazily initialised JNI bridge — deferred to avoid UnsatisfiedLinkError on registration. */
  private var native: OneNmNative? = null

  /** Coroutine scope for running model operations off the main thread. */
  private val scope = CoroutineScope(Dispatchers.IO + SupervisorJob())

  /** Application context for accessing the APK and data directories. */
  private var appContext: Context? = null

  /** Absolute path to the app's native library directory (contains .so files). */
  private var nativeLibDir: String? = null

  /** Returns the shared [OneNmNative] instance, creating it on first access. */
  private fun getNative(): OneNmNative {
    if (native == null) {
      native = OneNmNative()
    }
    return native!!
  }

  /**
   * Returns a directory containing the ggml backend .so files on disk.
   *
   * On some Android versions/configurations, native libs are loaded directly
   * from the APK without extraction (extractNativeLibs=false). In that case,
   * [nativeLibDir] is empty and ggml cannot discover backends via directory
   * scanning. This method detects that situation and extracts the required
   * .so files from the APK to a writable cache directory.
   */
  private fun getEffectiveLibDir(): String {
    val origDir = nativeLibDir ?: ""
    val ctx = appContext ?: return origDir

    // Check if the .so files are actually on disk in the original directory.
    val testFile = File(origDir, "libggml-cpu-android_armv8.2_1.so")
    if (testFile.exists()) {
      return origDir
    }

    // Files are not extracted — extract from APK to a cache directory.
    val extractDir = File(ctx.cacheDir, "onenm_native_libs")
    val markerFile = File(extractDir, ".extracted")

    // Skip extraction if already done for this install.
    if (markerFile.exists()) {
      return extractDir.absolutePath
    }

    extractDir.mkdirs()

    val soNames = listOf(
      "libggml-cpu-android_armv8.2_1.so",
      "libggml-base.so",
      "libggml.so",
      "libllama.so",
      "libomp.so",
    )

    val apkPath = ctx.applicationInfo.sourceDir
    val abi = android.os.Build.SUPPORTED_ABIS.firstOrNull() ?: "arm64-v8a"

    ZipFile(apkPath).use { zip ->
      for (name in soNames) {
        val entryPath = "lib/$abi/$name"
        val entry = zip.getEntry(entryPath) ?: continue
        val outFile = File(extractDir, name)
        zip.getInputStream(entry).use { input ->
          FileOutputStream(outFile).use { output ->
            input.copyTo(output)
          }
        }
      }
    }

    markerFile.createNewFile()
    return extractDir.absolutePath
  }

  override fun onAttachedToEngine(flutterPluginBinding: FlutterPlugin.FlutterPluginBinding) {
    channel = MethodChannel(flutterPluginBinding.binaryMessenger, "onenm_local_llm")
    channel.setMethodCallHandler(this)
    appContext = flutterPluginBinding.applicationContext
    nativeLibDir = flutterPluginBinding.applicationContext.applicationInfo.nativeLibraryDir
  }

  override fun onMethodCall(call: MethodCall, result: Result) {
    when (call.method) {
      "pingNative" -> result.success("pong")

      "initBackend" -> {
        scope.launch {
          try {
            val libDir = getEffectiveLibDir()
            val ok = getNative().initBackend(libDir)
            withContext(Dispatchers.Main) {
              result.success(ok)
            }
          } catch (e: Exception) {
            withContext(Dispatchers.Main) {
              result.error("BACKEND_ERROR", e.message, null)
            }
          }
        }
      }

      "loadModel" -> {
        val modelPath = call.argument<String>("modelPath")
        if (modelPath == null) {
          result.error("INVALID_ARGUMENT", "modelPath is required", null)
        } else {
          scope.launch {
            try {
              val libDir = getEffectiveLibDir()
              val loaded = getNative().loadModel(modelPath, libDir)
              withContext(Dispatchers.Main) {
                result.success(loaded)
              }
            } catch (e: Exception) {
              withContext(Dispatchers.Main) {
                result.error("LOAD_ERROR", e.message, null)
              }
            }
          }
        }
      }

      "generate" -> {
        val prompt = call.argument<String>("prompt")
        if (prompt == null) {
          result.error("INVALID_ARGUMENT", "prompt is required", null)
        } else {
          val temperature = (call.argument<Double>("temperature") ?: 0.7).toFloat()
          val topK = call.argument<Int>("topK") ?: 40
          val topP = (call.argument<Double>("topP") ?: 0.9).toFloat()
          val maxTokens = call.argument<Int>("maxTokens") ?: 128
          val repeatPenalty = (call.argument<Double>("repeatPenalty") ?: 1.1).toFloat()
          scope.launch {
            try {
              val output = getNative().generate(prompt, temperature, topK, topP, maxTokens, repeatPenalty)
              withContext(Dispatchers.Main) {
                result.success(output)
              }
            } catch (e: Exception) {
              withContext(Dispatchers.Main) {
                result.error("GENERATE_ERROR", e.message, null)
              }
            }
          }
        }
      }

      "releaseModel" -> {
        native?.releaseModel()
        result.success(null)
      }

      else -> result.notImplemented()
    }
  }

  override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
    channel.setMethodCallHandler(null)
    scope.cancel()
  }
}