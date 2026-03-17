<p align="center">
  <img src="flutter-llama.cpp/assets/banner.png" alt="1nm banner" />
</p>

# 1nm — On-Device LLM SDKs

[![License: MIT](https://img.shields.io/badge/license-MIT-blue.svg)](LICENSE)

**Run large language models locally on mobile devices — no cloud, no API keys, fully offline.**

1nm provides lightweight SDKs that wrap [llama.cpp](https://github.com/ggml-org/llama.cpp) for mobile platforms, making it easy to integrate on-device AI into your apps.

---

## Packages

| Package                                   | Platform | Language       | Status       |
| ----------------------------------------- | -------- | -------------- | ------------ |
| [`flutter-llama.cpp`](flutter-llama.cpp/) | Android  | Dart / Flutter | ✅ Available |
| `kotlin-llama.cpp`                        | Android  | Kotlin         | 🚧 Planned   |
| `swift-llama.cpp`                         | iOS      | Swift          | 🚧 Planned   |

## flutter-llama.cpp

The Flutter plugin for on-device LLM inference on Android. Handles model downloading, native backend loading, and multi-turn chat through a simple Dart API.

```dart
final ai = OneNm(model: OneNmModel.tinyllama);
await ai.initialize();
final reply = await ai.chat('Hello!');
```

**[→ Full documentation](flutter-llama.cpp/README.md)**

[![pub package](https://img.shields.io/pub/v/onenm_local_llm.svg)](https://pub.dev/packages/onenm_local_llm)

## Repository Structure

```
onenm_local_llm/
├── flutter-llama.cpp/    # Flutter plugin (pub.dev: onenm_local_llm)
│   ├── lib/              #   Dart API
│   ├── android/          #   Kotlin + C++ native layer
│   ├── example/          #   Demo chat app
│   └── test/             #   Unit tests
├── .github/              # Issue templates, CI workflows
├── CONTRIBUTING.md       # Contribution guidelines
├── CODEOWNERS
└── LICENSE               # MIT
```

## Getting Started

Each package has its own README with setup instructions:

- **Flutter** → [`flutter-llama.cpp/README.md`](flutter-llama.cpp/README.md)

## License

This project is licensed under the MIT License — see the [LICENSE](LICENSE) file for details.

llama.cpp is licensed under the MIT License. See [llama.cpp LICENSE](https://github.com/ggml-org/llama.cpp/blob/master/LICENSE).

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md) for guidelines.
