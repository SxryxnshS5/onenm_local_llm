// Copyright 2026 1nm. All rights reserved.
// Use of this source code is governed by a MIT license that can be
// found in the LICENSE file.

import 'package:flutter_test/flutter_test.dart';
import 'package:onenm_local_llm/models.dart';

void main() {
  group('ChatTemplate', () {
    const template = ChatTemplate(
      system: '<|system|>\n{text}</s>\n',
      user: '<|user|>\n{text}</s>\n',
      assistant: '<|assistant|>\n{text}</s>\n',
    );

    test('formats single user message', () {
      final result = template.format(
        messages: [(role: 'user', text: 'Hello')],
      );
      expect(result, contains('<|user|>\nHello</s>'));
      expect(result, contains('<|system|>'));
      // Should end with the assistant prompt prefix
      expect(result, endsWith('<|assistant|>\n'));
    });

    test('uses custom system prompt', () {
      final result = template.format(
        systemPrompt: 'Be concise.',
        messages: [(role: 'user', text: 'Hi')],
      );
      expect(result, contains('Be concise.'));
      expect(result, isNot(contains('You are a helpful assistant.')));
    });

    test('uses default system prompt when none provided', () {
      final result = template.format(
        messages: [(role: 'user', text: 'Hi')],
      );
      expect(result, contains('You are a helpful assistant.'));
    });

    test('formats multi-turn conversation', () {
      final result = template.format(
        messages: [
          (role: 'user', text: 'Hello'),
          (role: 'assistant', text: 'Hi there!'),
          (role: 'user', text: 'How are you?'),
        ],
      );
      expect(result, contains('Hello'));
      expect(result, contains('Hi there!'));
      expect(result, contains('How are you?'));
    });
  });

  group('GenerationSettings', () {
    test('has sensible defaults', () {
      const settings = GenerationSettings();
      expect(settings.temperature, 0.7);
      expect(settings.topK, 40);
      expect(settings.topP, 0.9);
      expect(settings.maxTokens, 128);
      expect(settings.repeatPenalty, 1.1);
    });

    test('toMap() serialises all fields', () {
      const settings = GenerationSettings(temperature: 0.5, maxTokens: 256);
      final map = settings.toMap();
      expect(map['temperature'], 0.5);
      expect(map['topK'], 40);
      expect(map['topP'], 0.9);
      expect(map['maxTokens'], 256);
      expect(map['repeatPenalty'], 1.1);
    });
  });

  group('OneNmModel', () {
    test('tinyllama has correct id', () {
      expect(OneNmModel.tinyllama.id, 'tinyllama');
    });

    test('phi2 has correct id', () {
      expect(OneNmModel.phi2.id, 'phi2');
    });

    test('all contains both models', () {
      expect(OneNmModel.all, hasLength(2));
      expect(OneNmModel.all, contains(OneNmModel.tinyllama));
      expect(OneNmModel.all, contains(OneNmModel.phi2));
    });

    test('model URLs point to huggingface', () {
      for (final model in OneNmModel.all) {
        expect(model.ggufUrl, startsWith('https://huggingface.co/'));
        expect(model.ggufUrl, endsWith('.gguf'));
      }
    });

    test('model file names end with .gguf', () {
      for (final model in OneNmModel.all) {
        expect(model.fileName, endsWith('.gguf'));
      }
    });
  });
}
