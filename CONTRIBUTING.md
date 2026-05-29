# Contributing to Voily

## Development Setup

### Prerequisites

- macOS 14.0 (Sonoma) or later
- Xcode 26+
- [XcodeGen](https://github.com/yonaskolb/XcodeGen) (`brew install xcodegen`)

### Clone, Build, Run

```bash
git clone https://github.com/BubblePtr/Voily.git
cd Voily

# Generate Xcode project from project.yml, then build
make build

# Build and launch
make run
```

`make build` regenerates `Voily.xcodeproj` from `project.yml` with XcodeGen before invoking Xcode. Install XcodeGen locally if the command is missing.

### Install Locally for Validation

```bash
# Release configuration, Developer ID signing, installed to /Applications.
# Use this for PR and feature validation on a development machine.
make install-dev

# Debug configuration, Apple Development signing, installed to /Applications.
# Use this only when you need LLDB/debug-only behavior.
make install-debug
```

### Reset Permissions for Testing

```bash
# Resets Voily's microphone and Accessibility grants, then installs the test build.
# Useful for regression-testing the first-launch permission flow.
make test-permission-flow
```

### Running Tests

```bash
# Full test suite: SwiftPM logic tests + Xcode app/unit tests
make test

# SwiftPM logic tests only (sandbox-safe, no app bundle needed)
make test-core

# Xcode app/unit tests only (requires full app target)
make test-app
```

See [docs/testing.md](docs/testing.md) for test coverage details and conventions.

## Project Structure

```text
Sources/
├── VoilyCore/              # SwiftPM library: settings, storage, transcript logic, LLM/Fun-ASR core
└── VoilyApp/               # SwiftUI/AppKit app: lifecycle, permissions, UI, audio capture, services
Resources/VoilyApp/         # Info.plist, entitlements, asset catalogs, localized strings, brand icons
Tests/
├── VoilyCoreTests/         # SwiftPM logic tests
└── VoilyTests/             # Xcode app-hosted tests
project.yml                 # XcodeGen source of truth for Voily.xcodeproj
```

Dependency direction: `VoilyApp` → `VoilyCore`. `VoilyCore` has no dependency on SwiftUI, AppKit, app bundle lifecycle, microphone, Accessibility, or code signing state.

See [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) for the full module layout, key flows, and design rationale.

## Building a Release

```bash
make release        # Archive Release build → build/release/Voily.app
make package-dmg    # Create distributable .dmg
make verify-release # Inspect signing, hardened runtime, and Gatekeeper status
```

For the complete signing, notarization, and GitHub Release publishing flow, see [docs/releasing.md](docs/releasing.md).

## Design Constraints

See [AGENTS.md](AGENTS.md) for non-negotiable constraints when contributing code. Key rules include:

- Minimum deployment target: **macOS 14.0** (no macOS 15+ only APIs without `#available` fallback)
- Use **async/await + AsyncStream** — do not introduce Combine
- All ASR providers must implement the **`SpeechTranscriptionService`** protocol
- System audio must be **muted during recording** (handled by `SystemMediaPlaybackService`)
- Text injection is **paste-only** (no CGEvent keyboard simulation)
- Never commit API keys, tokens, or model weights
- Trigger key monitoring uses **IOKit**, not NSEvent global monitor

## Architecture Decisions

Key decisions are recorded in [docs/decisions/](docs/decisions/):

| # | Topic |
|---|---|
| [0001](docs/decisions/0001-lower-macos-deployment-target.md) | Lowering macOS deployment target |
| [0002](docs/decisions/0002-async-await-over-combine.md) | Async/await over Combine |
| [0003](docs/decisions/0003-pluggable-asr-providers.md) | Pluggable ASR providers |
| [0004](docs/decisions/0004-local-model-storage.md) | Local model storage |
| [0005](docs/decisions/0005-trigger-key-interaction.md) | Trigger key interaction |
| [0006](docs/decisions/0006-permissionflow-permission-guidance.md) | Permission flow & guidance |
