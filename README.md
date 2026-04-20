<h1 align="center">Voily</h1>

<p align="center">Language: EN | <a href="./README_CN.md">简中</a></p>

<p align="center">
  <img src="https://img.shields.io/badge/macOS_14.0+-black?style=flat-square&logo=apple&logoColor=white" alt="macOS 14.0+">
  <img src="https://img.shields.io/badge/Swift-orange?style=flat-square&logo=swift&logoColor=white" alt="Swift">
  <img src="https://img.shields.io/badge/License-Apache_2.0-blue?style=flat-square" alt="Apache 2.0">
  <img src="https://img.shields.io/badge/Open_Source-green?style=flat-square" alt="Open Source">
</p>

**Press your trigger key, speak, and text appears at your cursor.**

Voily is an open-source macOS dictation app. Press your configured trigger key to start dictation, press it again to finish, and the recognized text is automatically pasted at the current cursor position — in any app. Long-press the trigger key to start quick Chinese-to-English translation. It supports both local and cloud-based ASR engines, optional LLM-powered text refinement, and a floating overlay that shows progress during capture and transcription.

## ✨ Features

- **Configurable trigger key** — Use either `Fn` or `Right Command`. Single press starts or finishes dictation, and long-pressing for 0.8s starts quick Chinese-to-English translation.
- **Multiple ASR engines** — Choose between local `SenseVoice Small` or cloud `Doubao ASR`, `Qwen ASR`, and `StepFun ASR`.
- **Live overlay feedback** — The floating overlay shows recording, transcription, translation, and injection state. Streaming providers can surface partial text while you speak.
- **LLM text refinement** — Optionally post-process transcriptions with LLM providers (DeepSeek, Alibaba Cloud, Volcengine, MiniMax, Kimi, Zhipu) to remove filler words, formalize tone, or organize into lists.
- **Glossary support** — Define custom terms and enable built-in glossary presets to improve recognition accuracy for domain-specific vocabulary.
- **Quick translation** — Long-press the trigger key to dictate in Chinese and get English output.
- **Menu bar dashboard** — View today's usage stats (duration, session count, character count) and a weekly sparkline chart from the menu bar.
- **Minimal and native** — Built with SwiftUI and AppKit; lives in your menu bar with an optional Dock icon.

## 📋 Requirements

- macOS 14.0 (Sonoma) or later
- Xcode 26+
- Microphone permission
- Accessibility permission (for text injection via paste)

## 🚀 Getting Started

### Build & Run

```bash
# Clone the repository
git clone https://github.com/BubblePtr/Voily.git
cd Voily

# Build
make build

# Run
make run
```

### Install to ~/Applications

```bash
make install
```

### Install from GitHub Releases

1. Download the latest notarized `.dmg` from GitHub Releases.
2. Open the disk image and drag `Voily.app` into `Applications`.
3. Launch `Voily.app` from `Applications`.
4. On first launch, grant:
   - Microphone
   - Accessibility

If macOS still warns about permissions, open `System Settings` -> `Privacy & Security` and enable the requested access manually.

### Build a GitHub Release artifact

```bash
# Archive a Release build to build/release/Voily.app
make release

# Package a distributable dmg
make package-dmg

# Inspect signing, hardened runtime, and Gatekeeper status
make verify-release
```

For the full signing, notarization, and GitHub release flow, see [docs/releasing.md](docs/releasing.md).

### Configuration

On first launch, Voily will ask for **Microphone** and **Accessibility** permissions. Then open Settings to configure:

1. **ASR Provider** — Select a speech recognition engine:
   - **SenseVoice Small** (local) — Downloads and manages the MLX model locally. No API key needed.
   - **Doubao ASR** (cloud) — Requires WebSocket URL, App ID, Token, and Resource ID.
   - **Qwen ASR** (cloud) — Requires WebSocket URL, API Key, and Model. The default endpoint and model are prefilled.
   - **StepFun ASR** (cloud) — Requires WebSocket URL, API Key, and Model.

2. **Text Refinement** (optional) — Enable LLM post-processing and configure a provider (DeepSeek / Alibaba Cloud DashScope / Volcengine / MiniMax / Kimi / Zhipu).

3. **Dictation Skills** — Toggle processing skills like filler-word removal, formalization, or ordered-list formatting.

4. **Glossary** — Add custom terms or enable built-in presets to improve recognition of specialized vocabulary.

## 🎯 Usage

| Action | Gesture |
|---|---|
| Start dictation | Press the selected trigger key once |
| Finish & paste | Press the selected trigger key again |
| Quick translate (ZH → EN) | Long-press the selected trigger key for 0.8s |

The floating overlay shows real-time status:
- 🎙️ **Recording** — Waveform animation with live partial text
- ⏳ **Transcribing** — Final recognition in progress
- ✨ **Refining** — LLM post-processing
- 📋 **Injecting** — Pasting result to cursor

## 🏗️ Project Structure

```
Sources/Voily/
├── App/                    # App entry point, delegate, Fn key monitor
├── Configuration/          # Settings, language definitions
├── Features/
│   ├── Overlay/            # Floating transcription overlay
│   └── Settings/           # Settings window
├── Services/
│   ├── Audio/              # ASR engines, audio capture, model management
│   └── Text/               # Text injection, LLM refinement
└── Storage/                # Usage statistics persistence
```

## 📄 License

This project is licensed under the [Apache License 2.0](LICENSE).
