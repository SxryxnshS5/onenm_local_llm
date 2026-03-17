# onenm_local_llm — Example Chat App

A minimal Material 3 chat app that demonstrates using the `onenm_local_llm` plugin for on-device LLM inference.

## What it Does

1. Downloads the TinyLlama 1.1B Chat model on first launch (~638 MB).
2. Shows download/loading progress with a spinner.
3. Provides a chat interface where you can have multi-turn conversations with the model — all running locally on the device.

## Running

```bash
# From the example/ directory
flutter run
```

> **Important:** Use a physical arm64-v8a Android device. Emulators (x86_64) cannot load the prebuilt native libraries.

## Screenshot Flow

1. **Loading** — Progress bar while downloading/loading the model.
2. **Chat** — Send messages and receive AI-generated replies.
3. **Typing indicator** — Shown while the model is generating a response.

## Key Code

The entire app is in [`lib/main.dart`](lib/main.dart). Key points:

```dart
// Initialise the plugin
final ai = OneNm(
  model: OneNmModel.tinyllama,
  onProgress: (msg) => setState(() => _initStatus = msg),
);
await ai.initialize();

// Send a chat message
final reply = await ai.chat('Hello!');
```
