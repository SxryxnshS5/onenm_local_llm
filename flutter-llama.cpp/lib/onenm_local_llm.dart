// Copyright 2026 1nm. All rights reserved.
// Use of this source code is governed by a MIT license that can be
// found in the LICENSE file.

/// On-device LLM inference for Flutter.
///
/// This library provides a high-level API for running large language models
/// locally on Android devices using [llama.cpp](https://github.com/ggml-org/llama.cpp).
///
/// {@category Getting Started}
library onenm_local_llm;

import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

import 'onenm_local_llm_platform_interface.dart';
import 'models.dart';

export 'models.dart';

/// Callback that receives human-readable status messages during model
/// download and loading (e.g. `"Downloading TinyLlama 1.1B Chat (42.3%)"`).
typedef OneNmProgressCallback = void Function(String status);

/// High-level API for on-device LLM inference.
///
/// [OneNm] handles the full lifecycle: downloading the GGUF model from
/// HuggingFace (if not already cached), loading it into memory via llama.cpp,
/// and exposing simple `chat()` / `generate()` methods.
///
/// ## Quick start
///
/// ```dart
/// final ai = OneNm(model: OneNmModel.tinyllama);
/// await ai.initialize();          // downloads + loads model
/// final reply = await ai.chat('Hello!');  // multi-turn chat
/// print(reply);
/// ai.dispose();                    // release native resources
/// ```
///
/// ## Chat vs Generate
///
/// * [chat] maintains conversation history and applies the model's
///   [ChatTemplate] automatically — use this for conversations.
/// * [generate] sends a raw prompt without any formatting — use this
///   for completions, custom templates, or single-shot prompts.
///
/// ## Thread safety
///
/// This class is **not** thread-safe. Call all methods from the same
/// isolate (typically the main isolate).
class OneNm {
  /// The model to load and run inference on.
  final ModelInfo model;

  /// Sampling / generation parameters (temperature, top-k, etc.).
  final GenerationSettings settings;

  /// Optional callback for download/load progress updates.
  final OneNmProgressCallback? onProgress;

  /// When `true`, detailed `[1nm]` logs are printed to the debug console.
  ///
  /// Includes timing information for model loading, generation, etc.
  /// Defaults to `false`.
  final bool debug;

  bool _ready = false;

  final _history = <({String role, String text})>[];
  String? _systemPrompt;

  /// Creates a new [OneNm] instance.
  ///
  /// * [model] — which LLM to use (see [OneNmModel] for built-in options).
  /// * [settings] — sampling parameters; defaults are suitable for chat.
  /// * [onProgress] — optional callback for download / load status messages.
  /// * [debug] — enable verbose `[1nm]` logs in the debug console.
  OneNm({
    required this.model,
    this.settings = const GenerationSettings(),
    this.onProgress,
    this.debug = false,
  });

  /// Log a debug message. Only prints when [debug] is `true`.
  void _log(String msg) {
    if (debug) debugPrint('[1nm] $msg');
  }

  /// Report a status message to [onProgress] and, if [debug] is on, the
  /// debug console.
  void _report(String msg) {
    _log(msg);
    onProgress?.call(msg);
  }

  /// Downloads the model (if not cached) and loads it into memory.
  ///
  /// Must be called before [chat] or [generate]. If the download or load
  /// fails, one automatic retry is attempted after deleting the file.
  ///
  /// Throws an [Exception] if loading ultimately fails.
  Future<void> initialize() async {
    final sw = Stopwatch()..start();
    _log('Initializing with model: ${model.name}');
    _log('Settings: temp=${settings.temperature}, topK=${settings.topK}, '
        'topP=${settings.topP}, maxTokens=${settings.maxTokens}, '
        'repeatPenalty=${settings.repeatPenalty}');

    // Init backend early — surfaces backend issues before downloading.
    _report('Preparing backend...');
    final backendOk = await OnenmLocalLlmPlatform.instance.initBackend();
    if (backendOk != true) {
      _log('Warning: no ggml backends loaded — model loading may fail');
    }

    final modelPath = await _ensureModel();

    _report('Loading model...');
    final loadSw = Stopwatch()..start();
    final loaded = await OnenmLocalLlmPlatform.instance.loadModel(modelPath);
    if (loaded != true) {
      // Load failed — likely corrupted download. Delete and retry once.
      _report('Load failed, re-downloading...');
      final file = File(modelPath);
      if (await file.exists()) await file.delete();
      await _downloadModel(modelPath);

      _report('Loading model (retry)...');
      loadSw.reset();
      final retryLoaded =
          await OnenmLocalLlmPlatform.instance.loadModel(modelPath);
      if (retryLoaded != true) throw Exception('Failed to load model');
    }
    _log('Model loaded in ${_elapsed(loadSw)}');
    _ready = true;
    _report('Ready');
    _log('Total initialization: ${_elapsed(sw)}');
  }

  /// Sends a chat message and returns the model's reply.
  ///
  /// Conversation history is maintained automatically. The model's
  /// [ChatTemplate] is applied to format the full prompt including all
  /// prior turns.
  ///
  /// An optional [systemPrompt] sets the system instruction for the
  /// conversation. Once set, it persists across subsequent calls until
  /// changed.
  ///
  /// Throws a [StateError] if [initialize] has not been called.
  Future<String> chat(String message, {String? systemPrompt}) async {
    if (!_ready) throw StateError('Call initialize() first');
    _systemPrompt = systemPrompt ?? _systemPrompt;

    _history.add((role: 'user', text: message));
    _log('Chat message (${message.length} chars, ${_history.length} turns)');

    final prompt = model.chatTemplate.format(
      systemPrompt: _systemPrompt,
      messages: _history,
    );
    _log('Formatted prompt: ${prompt.length} chars');

    final sw = Stopwatch()..start();
    _log('Generating response...');
    final result =
        await OnenmLocalLlmPlatform.instance.generate(prompt, settings.toMap());
    final reply = (result ?? '').trim();
    _log('Response generated in ${_elapsed(sw)} (${reply.length} chars)');

    _history.add((role: 'assistant', text: reply));
    return reply;
  }

  /// Generates a raw text completion for the given [prompt].
  ///
  /// No chat template or history is applied — the prompt is sent as-is.
  /// For multi-turn conversations, prefer [chat].
  ///
  /// Throws a [StateError] if [initialize] has not been called.
  Future<String> generate(String prompt) async {
    if (!_ready) throw StateError('Call initialize() first');
    _log('Generate called (${prompt.length} chars)');
    final sw = Stopwatch()..start();
    final result =
        await OnenmLocalLlmPlatform.instance.generate(prompt, settings.toMap());
    final output = result ?? '';
    _log('Generated in ${_elapsed(sw)} (${output.length} chars)');
    return output;
  }

  /// Clears the conversation history to start a fresh chat session.
  void clearHistory() {
    _log('History cleared (was ${_history.length} messages)');
    _history.clear();
  }

  /// Releases all native resources (model, context, backend).
  ///
  /// After calling this, the instance cannot be used again unless
  /// [initialize] is called once more.
  Future<void> dispose() async {
    _log('Disposing...');
    await OnenmLocalLlmPlatform.instance.releaseModel();
    _ready = false;
    _log('Disposed');
  }

  // ── Internal helpers ──────────────────────────────────────────

  /// Format a [Stopwatch] elapsed time as a human-readable string.
  static String _elapsed(Stopwatch sw) {
    final ms = sw.elapsedMilliseconds;
    if (ms < 1000) return '${ms}ms';
    return '${(ms / 1000).toStringAsFixed(1)}s';
  }

  /// Returns the local path to the GGUF file, downloading it if needed.
  Future<String> _ensureModel() async {
    final appDir = await getApplicationDocumentsDirectory();
    final modelDir = Directory('${appDir.path}/models');
    await modelDir.create(recursive: true);

    final modelPath = '${modelDir.path}/${model.fileName}';
    final file = File(modelPath);

    if (await file.exists()) {
      final size = await file.length();
      final expectedMin = model.sizeMB * 0.95 * 1024 * 1024;
      if (size >= expectedMin) {
        _report('Model found (${(size / 1024 / 1024).toStringAsFixed(1)} MB)');
        return modelPath;
      }
      // File too small — probably a truncated download
      _report('Incomplete model file, re-downloading...');
      await file.delete();
    }

    await _downloadModel(modelPath);
    return modelPath;
  }

  /// Downloads the GGUF model file with up to 3 retry attempts.
  Future<void> _downloadModel(String modelPath) async {
    const maxAttempts = 3;
    for (int attempt = 1; attempt <= maxAttempts; attempt++) {
      try {
        _report('Downloading ${model.name} (~${model.sizeMB} MB)...'
            '${attempt > 1 ? ' (attempt $attempt/$maxAttempts)' : ''}');

        final request = http.Request('GET', Uri.parse(model.ggufUrl));
        final response = await http.Client().send(request);

        if (response.statusCode != 200) {
          throw Exception('HTTP ${response.statusCode}');
        }

        final totalBytes = response.contentLength ?? model.sizeMB * 1024 * 1024;
        int receivedBytes = 0;

        final file = File(modelPath);
        final sink = file.openWrite();
        await for (final chunk in response.stream) {
          sink.add(chunk);
          receivedBytes += chunk.length;
          final pct = (receivedBytes / totalBytes * 100).toStringAsFixed(1);
          final recvMB = (receivedBytes / 1024 / 1024).toStringAsFixed(1);
          final totalMB = (totalBytes / 1024 / 1024).toStringAsFixed(1);
          _report('Downloading ${model.name}...\n'
              '$recvMB / $totalMB MB ($pct%)');
        }
        await sink.close();

        // Verify file size
        final size = await file.length();
        final expectedMin = model.sizeMB * 0.95 * 1024 * 1024;
        if (size < expectedMin) {
          await file.delete();
          throw Exception(
              'Download incomplete: ${(size / 1024 / 1024).toStringAsFixed(1)} MB');
        }

        _report('Download complete');
        return;
      } catch (e) {
        if (attempt == maxAttempts) rethrow;
        final delay = Duration(seconds: 2 << (attempt - 1)); // 2s, 4s
        _report('Download failed: $e\nRetrying in ${delay.inSeconds}s...');
        await Future.delayed(delay);
      }
    }
  }
}
