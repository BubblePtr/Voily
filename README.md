<p align="center">
  <img src="assets/voily-icon.png" alt="Voily" width="96">
</p>

<h1 align="center">Voily</h1>

<p align="center">
  <b>Just speak — we'll do the rest.</b>
</p>

<p align="center">
  <a href="./README_CN.md">简中</a>
</p>

<p align="center">
  <img src="https://img.shields.io/badge/macOS_14.0+-black?style=flat-square&logo=apple&logoColor=white" alt="macOS 14.0+">
  <img src="https://img.shields.io/badge/Swift-orange?style=flat-square&logo=swift&logoColor=white" alt="Swift">
  <img src="https://img.shields.io/badge/License-Apache_2.0-blue?style=flat-square" alt="Apache 2.0">
</p>

<p align="center">
  <img src="assets/screenshots/hero.png" alt="Voily" width="720">
</p>

<!-- TODO: swap in a ~5s demo GIF once recorded — trigger key -> speak ->
     overlay transcribes -> text lands at the cursor. Save it as
     assets/screenshots/demo.gif and replace the hero <img> above. -->

---

Voily is an open-source, AI-powered voice input tool for macOS. Press a key, speak naturally, and your words land at the cursor — in any app. It does more than transcribe: an optional LLM cleans up filler, polishes your phrasing, or translates Chinese to English on the fly. The built-in engine runs fully on-device with no API key and no cost; cloud engines are there when you want higher accuracy. One key does it all.

## Why Voily

- **Speak faster than you type** — press the trigger key, talk, and text appears right at your cursor: email, editor, chat, terminal, any text field.
- **Local-first and private** — the built-in SenseVoice engine runs entirely on-device, with no network calls, no API key, and no per-request cost.
- **Translate on the same key** — long-press, speak Chinese, get English at the cursor. No mode switch, no second app.
- **Optional AI polish** — let an LLM strip filler words, rewrite into a formal register, or turn dictated steps into a numbered list.
- **Stays out of your way** — lives in the menu bar, no Dock icon by default, and mutes system audio while recording to prevent feedback.
- **Works where keystrokes fail** — text is injected through the system pasteboard, so it lands reliably in sandboxed apps, password fields, and remote desktops.
- **Open source and pluggable** — Apache 2.0, with five ASR engines behind one shared pipeline.

## How It Works

Press the trigger key to start recording. Voily captures the microphone, streams audio to a speech recognition engine, optionally refines the result with an LLM, and pastes the final text at your cursor. A floating overlay shows every step — recording, transcribing, refining, injecting — so you always know what's happening.

## Quick Start

### Download

Get the latest `.dmg` from [GitHub Releases](https://github.com/BubblePtr/Voily/releases/latest).

### Install

Open the disk image, drag **Voily.app** into `Applications`, then launch it.

### Grant Permissions

On first launch, the app will request two permissions:

| Permission | Purpose |
|---|---|
| Microphone | Capture your voice during dictation |
| Accessibility | Paste recognized text at the cursor (no keyboard simulation) |

Permission prompts appear on first run. If you dismiss them, reopen them from **Settings > Input**.

### Start Dictating

1. Pick your trigger key in Settings (`Fn` or `Right Command`).
2. Choose an ASR provider. **SenseVoice Small** runs locally out of the box with no API key. Cloud providers (Doubao, Fun-ASR, Qwen, StepFun) need credentials.
3. Press the trigger key, speak, press again. The overlay shows live status, then your text appears at the cursor.

| Action | Gesture |
|---|---|
| Dictate | Press trigger key -> speak -> press again |
| Translate (ZH -> EN) | Long-press trigger key (0.8s) -> speak -> confirm |

## Features

### Speech Recognition Engines

Voily ships with five ASR backends behind a shared capture pipeline. Switching engines does not change how dictation works.

| Provider | Mode | Needs API Key |
|---|---|---|
| **SenseVoice Small** | Local (MLX) | No |
| Doubao ASR | Cloud (WebSocket) | Yes |
| Fun-ASR | Cloud (WebSocket) | Yes |
| Qwen ASR | Cloud (WebSocket) | Yes |
| StepFun ASR | Cloud (WebSocket) | Yes |

Local SenseVoice runs on-device with no network calls, no API key, and no per-request cost. It downloads and manages the MLX model automatically under `~/Library/Application Support/Voily/LocalModels/`.

Cloud engines stream audio over WebSocket and support partial results: the overlay shows live text while you are still speaking, so you can see whether the engine is tracking.

<p align="center">
  <img src="assets/screenshots/setting-asr.png" alt="ASR Settings" width="640">
</p>

### LLM Text Refinement

After transcription, an optional LLM pass can process the text. You control what happens:

- **Remove filler words** — strip "um", "you know", and verbal padding
- **Make it formal** — rephrase casual speech into a polished register
- **Structure as ordered list** — if you dictated steps, they come out numbered

The refinement step is off by default. Enable it and pick a provider in Settings.

Supported LLM backends: **DeepSeek**, **Alibaba DashScope**, **Volcengine**, **MiniMax**, **Kimi**, **Zhipu**.

<p align="center">
  <img src="assets/screenshots/setting-text.png" alt="Text Refinement Settings" width="640">
</p>

### Custom Glossary

Define domain terms so the ASR engine recognizes them correctly. Add individual terms, or enable built-in presets. When connected to Fun-ASR, your glossary syncs automatically as hotword vocabulary before each session.

### Quick Translation

Long-press the trigger key to enter translation mode. Speak in Chinese, and English text is injected at the cursor. The overlay confirms the result before pasting, so you can cancel and retry if needed.

### Menu Bar Dashboard

Click the menu bar icon to see today's dictation activity: total duration, session count, and character count. A weekly sparkline gives you a trend at a glance. No separate window required.

<p align="center">
  <img src="assets/screenshots/menu-bar.png" alt="Menu Bar Dashboard" width="400">
</p>

### Thoughtful Defaults

- The trigger key (`Fn` or `Right Command`) stays out of your way. `Right Command` used as a modifier (e.g. `Right Command + C`) does not fire dictation.
- System audio is automatically muted during recording to prevent feedback.
- The app lives in the menu bar. A Dock icon is available as an option but off by default.

## Requirements

- macOS 14.0 (Sonoma) or later
- Apple Silicon Mac
- Microphone permission
- Accessibility permission

## For Developers

See [CONTRIBUTING.md](CONTRIBUTING.md) for build instructions, project layout, testing, and release workflow.

- Architecture overview: [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md)
- Design decisions: [docs/decisions/](docs/decisions/)

## License

[Apache License 2.0](LICENSE)
