// Copyright 2026 1nm. All rights reserved.
// Use of this source code is governed by a MIT license that can be
// found in the LICENSE file.

import 'package:plugin_platform_interface/plugin_platform_interface.dart';

import 'onenm_local_llm_method_channel.dart';

/// The platform-agnostic interface that platform-specific implementations
/// must extend.
///
/// This follows the federated plugin pattern recommended by Flutter.
/// See: https://docs.flutter.dev/packages-and-plugins/developing-packages#federated-plugins
abstract class OnenmLocalLlmPlatform extends PlatformInterface {
  /// Constructs an [OnenmLocalLlmPlatform].
  OnenmLocalLlmPlatform() : super(token: _token);

  static final Object _token = Object();

  static OnenmLocalLlmPlatform _instance = MethodChannelOnenmLocalLlm();

  /// The default instance of [OnenmLocalLlmPlatform] to use.
  ///
  /// Defaults to [MethodChannelOnenmLocalLlm].
  static OnenmLocalLlmPlatform get instance => _instance;

  /// Platform-specific implementations should set this to their own
  /// platform-specific class that extends [OnenmLocalLlmPlatform].
  static set instance(OnenmLocalLlmPlatform instance) {
    PlatformInterface.verifyToken(instance, _token);
    _instance = instance;
  }

  /// Verifies the native bridge is reachable. Returns `"pong"` on success.
  Future<String?> pingNative() {
    throw UnimplementedError('pingNative() has not been implemented.');
  }

  /// Initialises the ggml backend. Returns `true` if at least one backend loaded.
  Future<bool?> initBackend() {
    throw UnimplementedError('initBackend() has not been implemented.');
  }

  /// Loads a GGUF model from the given [modelPath]. Returns `true` on success.
  Future<bool?> loadModel(String modelPath) {
    throw UnimplementedError('loadModel() has not been implemented.');
  }

  /// Generates text for the given [prompt] using the provided [settings].
  Future<String?> generate(String prompt, Map<String, dynamic> settings) {
    throw UnimplementedError('generate() has not been implemented.');
  }

  /// Releases all native resources (model, context, backend).
  Future<void> releaseModel() {
    throw UnimplementedError('releaseModel() has not been implemented.');
  }
}
