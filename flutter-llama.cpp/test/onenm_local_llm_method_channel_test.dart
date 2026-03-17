// Copyright 2026 1nm. All rights reserved.
// Use of this source code is governed by a MIT license that can be
// found in the LICENSE file.

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:onenm_local_llm/onenm_local_llm_method_channel.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final platform = MethodChannelOnenmLocalLlm();
  final log = <MethodCall>[];

  setUp(() {
    log.clear();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(platform.methodChannel, (call) async {
      log.add(call);
      switch (call.method) {
        case 'pingNative':
          return 'pong';
        case 'loadModel':
          return true;
        case 'generate':
          return 'Hello world';
        case 'releaseModel':
          return null;
        default:
          return null;
      }
    });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(platform.methodChannel, null);
  });

  test('pingNative returns pong', () async {
    final result = await platform.pingNative();
    expect(result, 'pong');
  });

  test('loadModel sends modelPath', () async {
    final result = await platform.loadModel('/path/to/model.gguf');
    expect(result, true);
    expect(log.last.method, 'loadModel');
    expect(log.last.arguments['modelPath'], '/path/to/model.gguf');
  });

  test('generate sends prompt and settings', () async {
    final settings = {
      'temperature': 0.7,
      'topK': 40,
      'topP': 0.9,
      'maxTokens': 128,
      'repeatPenalty': 1.1,
    };
    final result = await platform.generate('Hello', settings);
    expect(result, 'Hello world');
    expect(log.last.method, 'generate');
    expect(log.last.arguments['prompt'], 'Hello');
    expect(log.last.arguments['temperature'], 0.7);
  });

  test('releaseModel completes', () async {
    await platform.releaseModel();
    expect(log.last.method, 'releaseModel');
  });
}
