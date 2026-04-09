<h1 align="center">Voily</h1>

<p align="center">Language: EN | <a href="./README_CN.md">简中</a></p>

<p align="center">
  <img src="https://img.shields.io/badge/macOS_26.0+-black?style=flat-square&logo=apple&logoColor=white" alt="macOS 26.0+">
  <img src="https://img.shields.io/badge/Swift-orange?style=flat-square&logo=swift&logoColor=white" alt="Swift">
  <img src="https://img.shields.io/badge/Open_Source-green?style=flat-square" alt="Open Source">
</p>

**Press Fn, speak, and text appears at your cursor.**

Voily is an open-source macOS dictation app. Hold the Fn key to record your voice, release to transcribe, and the recognized text is automatically pasted at the current cursor position — in any app. It supports both local and cloud-based ASR engines, optional LLM-powered text refinement, and a real-time floating overlay that shows transcription progress.

## ✨ Features

- **Fn-key triggered dictation** — Hold Fn to record, release to transcribe and paste. Double-press Fn for quick Chinese-to-English translation.
- **Multiple ASR engines** — Choose between local (SenseVoice) or cloud (Doubao Streaming, Qwen ASR) speech recognition providers.
- **Real-time partial results** — See transcription text appear in a floating overlay while you speak.
- **LLM text refinement** — Optionally post-process transcriptions with LLM providers (DeepSeek, Alibaba Cloud, Volcengine) to remove filler words, formalize tone, or organize into lists.
- **Glossary support** — Define custom terms and enable built-in glossary presets to improve recognition accuracy for domain-specific vocabulary.
- **Quick translation** — Double-press Fn to dictate in Chinese and get English output.
- **Menu bar dashboard** — View today's usage stats (duration, session count, character count) and a weekly sparkline chart from the menu bar.
- **Minimal and native** — Built with SwiftUI and AppKit; lives in your menu bar with an optional Dock icon.

## 📋 Requirements

- macOS 26.0 (Tahoe) or later
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

### Configuration

On first launch, Voily will ask for **Microphone** and **Accessibility** permissions. Then open Settings to configure:

1. **ASR Provider** — Select a speech recognition engine:
   - **SenseVoice Small** (local) — Requires downloading the ONNX model. No API key needed.
   - **Doubao Streaming** (cloud) — Requires Base URL, API Key, and Model.
   - **Qwen ASR** (cloud) — Requires API Key. Pre-configured with default endpoint and model.

2. **Text Refinement** (optional) — Enable LLM post-processing and configure a provider (DeepSeek / Alibaba Cloud DashScope / Volcengine).

3. **Dictation Skills** — Toggle processing skills like filler-word removal, formalization, or ordered-list formatting.

4. **Glossary** — Add custom terms or enable built-in presets to improve recognition of specialized vocabulary.

## 🎯 Usage

| Action | Gesture |
|---|---|
| Start dictation | Hold **Fn** key |
| Finish & paste | Release **Fn** key |
| Quick translate (ZH → EN) | Double-press **Fn** key |

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

Open source. See the repository for license details.
