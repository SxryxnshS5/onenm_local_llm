// Copyright 2026 1nm. All rights reserved.
// Use of this source code is governed by a MIT license that can be
// found in the LICENSE file.

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'onenm_local_llm_platform_interface.dart';

/// Android implementation of [OnenmLocalLlmPlatform] using a [MethodChannel].
///
/// Communicates with the Kotlin plugin host via the `onenm_local_llm` channel.
class MethodChannelOnenmLocalLlm extends OnenmLocalLlmPlatform {
  /// The method channel used to interact with the native platform.
  @visibleForTesting
  final methodChannel = const MethodChannel('onenm_local_llm');

  @override
  Future<String?> pingNative() async {
    return await methodChannel.invokeMethod<String>('pingNative');
  }

  @override
  Future<bool?> initBackend() async {
    return await methodChannel.invokeMethod<bool>('initBackend');
  }

  @override
  Future<bool?> loadModel(String modelPath) async {
    return await methodChannel.invokeMethod<bool>(
      'loadModel',
      {'modelPath': modelPath},
    );
  }

  @override
  Future<String?> generate(String prompt, Map<String, dynamic> settings) async {
    return await methodChannel.invokeMethod<String>(
      'generate',
      {'prompt': prompt, ...settings},
    );
  }

  @override
  Future<void> releaseModel() async {
    await methodChannel.invokeMethod('releaseModel');
  }
}
