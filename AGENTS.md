# Voily — AI Coding Agent 指南

> 本文件在原有 `AGENTS.md` / `CLAUDE.md` 基础上，根据仓库实际代码、配置与文档整理而成。阅读对象是对项目零了解的 AI coding agent；若发现本文与代码不一致，以代码与 `docs/decisions/` 中的 ADR 为准。

## 1. 项目简介

Voily 是一款开源 macOS 语音输入应用：按一下触发键开始录音，再按一下停止并转写，最终把文本粘贴到光标位置。支持本地 / 云端 ASR（自动语音识别）引擎，可选 LLM 文本润色 / 中→英快捷翻译，并配有实时浮动 overlay。

- 产品形态：菜单栏应用，Dock 图标可关闭，设置窗口可单独开关而不退出应用。
- 本地引擎：SenseVoice Small，基于 MLX Swift 在应用进程内推理，无需 API key。
- 云端引擎：Doubao ASR、Fun-ASR、Qwen ASR、StepFun ASR，均通过 WebSocket / HTTP 流式识别。
- 文本润色：DeepSeek、阿里云百炼、火山引擎、MiniMax、Kimi、智谱。
- 许可：Apache License 2.0。

## 2. 技术栈与系统要求

| 项目 | 说明 |
|---|---|
| 语言 | Swift 6.0 |
| UI | SwiftUI（业务 UI）+ AppKit（菜单栏、浮窗、系统集成） |
| 最低系统 | macOS 14.0 (Sonoma) |
| 架构 | 主要面向 Apple Silicon；Xcode Debug 构建默认 `ONLY_ACTIVE_ARCH=YES` |
| 包管理 | Swift Package Manager（SPM） |
| Xcode 工程 | `project.yml` 是 XcodeGen 源文件；`Voily.xcodeproj` 是本地生成物，不要手改 |
| 核心依赖 | `mlx-swift`（本地 SenseVoice 推理）、`PermissionFlow`（权限引导）、`Sparkle`（应用更新，本地 Vendor） |
| 官网 | `website/` 是独立子项目：Bun + Vite + React + TanStack Router，部署到 Cloudflare Pages |

关键配置文件：

- `Package.swift` — SPM 包描述，声明 `VoilyCore` library、`VoilyApp` executable、测试目标。
- `project.yml` — XcodeGen 源文件，生成 `Voily.xcodeproj`。
- `Makefile` — 日常构建、测试、本地安装、发布入口。
- `Resources/VoilyApp/Info.plist` / `Voily.entitlements` — 应用信息与权限声明。
- `scripts/release.sh` — 归档、打包、签名、公证、验证的发布脚本。
- `scripts/dmgbuild_settings.py` — DMG 布局配置。
- `website/package.json` — 官网依赖与脚本。

## 3. 代码组织与模块分层

```text
Sources/
├── VoilyCore/          # 可脱离 app bundle 测试的核心逻辑（SwiftPM library）
│   ├── Configuration/  # AppSettings、ASRProvider、TextRefinementProvider 等枚举与配置
│   ├── Services/
│   │   ├── Audio/      # Fun-ASR 消息/词库、TranscriptAccumulator、PartialTranscriptDisplayThrottle
│   │   └── Text/       # LLMRefinementService、prompt 构造
│   ├── Storage/        # UsageStore（用量统计）
│   └── Support/        # AppLocalization、DebugLog 等工具
├── VoilyApp/           # SwiftUI/AppKit 应用（XcodeGen 生成的 app target）
│   ├── App/            # AppController、AppDelegate、VoilyApp、PermissionCoordinator、触发键监听
│   ├── Features/
│   │   ├── Settings/   # 设置窗口相关 SwiftUI 视图与控制器
│   │   └── Overlay/    # 浮动 overlay 状态与面板控制器
│   └── Services/
│       ├── Audio/      # AudioCaptureService、ASRCaptureSession、各 ASR provider 实现
│       ├── Text/       # TextInjectionService（粘贴注入）
│       └── Media/      # SystemAudioOutputMuteService（系统播放静音）
Tests/
├── VoilyCoreTests/     # SPM 纯逻辑测试
└── VoilyTests/         # Xcode app-hosted 测试
Resources/VoilyApp/     # Info.plist、entitlements、Assets.xcassets、本地化 lproj、BrandIcons
website/                # 产品官网（独立 Node 项目）
```

依赖方向：**`VoilyApp` → `VoilyCore`**。`VoilyCore` 不依赖 SwiftUI、AppKit、app bundle 生命周期、麦克风、辅助功能或代码签名状态。`Sources/Voily/` 目前仅保留空目录，无实际代码。

## 4. 核心流程

一次典型听写流程：

1. `TriggerKeyMonitor` 通过 IOKit / CGEvent tap 监听触发键（`Fn` 或 `右 Command`）。
   - 短按：开始 / 结束普通听写。
   - 长按 ≥0.8s：进入中→英快捷翻译。
   - 右 Command 作为组合键修饰时不触发。
2. 若开启「录音时静音系统输出」，`SystemAudioOutputMuteService` 先静音系统音频，防止回授。
3. `AudioCaptureService` 拉取麦克风样本，喂给当前 ASR provider。
4. 流式 provider 的 partial 结果经 `TranscriptAccumulator` 抹平语义差异，再经 `PartialTranscriptDisplayThrottle`（默认 220ms）节流后更新 overlay。
5. 普通听写通过再次短按触发键结束；快捷翻译通过 overlay 的确认 / 取消按钮结束。
6. 拿到 final 文本后，若开启文本润色，调用 `LLMRefinementService`。
7. `TextInjectionService` 通过系统粘贴板把文本粘贴到光标位置（需要 Accessibility 权限），并恢复粘贴板原内容。
8. `UsageStore` 记录本次会话时长、字符数、应用来源等。

### 4.1 ASR provider 抽象

所有 ASR 引擎实现统一的 `ASRCaptureSession` 协议（`Sources/VoilyApp/Services/Audio/ASRCaptureSession.swift`）：

```swift
@MainActor
protocol ASRCaptureSession: AnyObject {
    func start(onPartial: @escaping @Sendable (String) -> Void) async throws
    func append(_ buffer: AVAudioPCMBuffer) async throws
    func finish() async throws -> ASRCaptureSessionFinalResult
    func cancel() async
}
```

运行时 provider 选择集中在 `LiveASRCaptureSessionFactory`。当前实现：

- `SenseVoiceNativeCaptureSession` / `SenseVoiceNativeService` — 本地 MLX Swift 推理。
- `DoubaoCaptureSession` / `DoubaoStreamingASRService` — 字节跳动 Doubao 流式识别。
- `FunASRCaptureSession` / `FunASRRealtimeService` + `FunASRVocabularyService` — 阿里云 Fun-ASR，支持热词词表同步。
- `QwenCaptureSession` / `QwenRealtimeASRService` — 通义千问实时识别。
- `StepCaptureSession` / `StepRealtimeASRService` — StepFun 实时识别。

> 注意：部分旧文档或配置文件可能使用 `SpeechTranscriptionService` 一词，但当前代码中的统一协议是 `ASRCaptureSession`。新增 provider 时请实现 `ASRCaptureSession` 并在 `LiveASRCaptureSessionFactory` 注册。

Settings 里的「测试连接」不属于 `ASRCaptureSession`，由独立的 `ASRConnectionTester` 负责。

### 4.2 本地 SenseVoice 模型

- 模型文件下载到 `~/Library/Application Support/Voily/LocalModels/senseVoice/model/`。
- 由 `ManagedASRModelStore` 负责下载、校验、卸载。
- 当前本地热路径是 `SenseVoiceNativeService`，通过 `mlx-swift` 在应用进程内推理；`SenseVoiceResidentService` 仅作为历史 fallback 保留。
- 仓库内**严禁**提交模型权重。

### 4.3 LLM 文本润色

`LLMRefinementService` 通过兼容 OpenAI chat completions 的 HTTP 接口调用。默认 DeepSeek Base URL `https://api.deepseek.com`，模型 `deepseek-v4-flash`，请求时显式发送 `thinking: { type: "disabled" }` 以避免输出思考内容。支持技能：去语气词、更正式、整理成有序列表。

## 5. 构建与运行命令

环境要求：macOS 14.0+、Xcode 26+、XcodeGen（`brew install xcodegen`）。若使用本地 SenseVoice，需要 Xcode Metal Toolchain（`xcodebuild -downloadComponent MetalToolchain`）。

```bash
# 生成 Xcode 工程并 Debug 构建
make build

# 构建并运行
make run

# 仅生成本地 Xcode 工程
make generate

# 本地安装 Release / Developer ID 版本到 /Applications（用于功能验收）
make install-dev

# 本地安装 Debug / Apple Development 版本到 /Applications
make install-debug

# 重置权限、注销旧应用、安装 Debug 版并启动（适合从 release 切回 debug）
make prepare-debug
```

旧的 SenseVoice Python runtime 相关 target（`prepare-sensevoice-runtime`、`verify-sensevoice-runtime`、`embed-sensevoice-runtime-debug`）当前为兼容 no-op，因为本地推理已改为 MLX Swift。

## 6. 测试策略与命令

项目有两套测试，**不要默认只跑一套**。

```bash
# 完整测试套件：SwiftPM 逻辑测试 + Xcode app/unit 测试
make test

# 仅 SwiftPM 逻辑测试（sandbox-safe，不依赖 app bundle、权限、签名）
make test-core

# 仅 Xcode app/unit 测试（依赖完整 Voily.app target）
make test-app

# 枚举测试用例
swift test list
```

### 6.1 测试分层

- `VoilyCoreTests`（`Tests/VoilyCoreTests/`）：验证 `VoilyCore` 中的纯逻辑。
  - 覆盖：设置持久化与迁移、转写文本累积、`FunASRRealtimeService` 消息构造、`FunASRVocabularyService` 词表同步计划、`LLMRefinementService` prompt 组装、`UsageStore` 统计等。
  - 不应依赖麦克风、辅助功能、菜单栏、窗口生命周期、代码签名或真实网络连接。

- `VoilyTests`（`Tests/VoilyTests/`）：app-hosted 测试，依赖完整 `Voily.app`。
  - 覆盖：`AppController`、触发键状态机、`ASRCaptureSession`、各 provider 连接测试、`AudioCaptureService`、系统音频静音、资源文件等。

### 6.2 在受限环境跑测试

若 workspace 对沙盒或 module cache 敏感，可显式指定缓存路径：

```bash
# 纯逻辑测试
env CLANG_MODULE_CACHE_PATH="$PWD/.build/ModuleCache" \
  swift test \
  --disable-sandbox \
  --scratch-path "$PWD/.build"

# app-hosted 编译验证（不需要运行 runner 时）
make generate
env CLANG_MODULE_CACHE_PATH="$PWD/.xcodebuild/ModuleCache" \
  xcodebuild \
  -project "$PWD/Voily.xcodeproj" \
  -scheme Voily \
  -configuration Debug \
  -destination 'platform=macOS,arch=arm64' \
  -derivedDataPath "$PWD/.xcodebuild" \
  build-for-testing \
  CODE_SIGNING_ALLOWED=NO \
  ENABLE_USER_SCRIPT_SANDBOXING=NO \
  OTHER_SWIFT_FLAGS='$(inherited) -disable-sandbox'
```

## 7. 代码风格与开发约定

### 7.1 不能违反的约束

1. **最低系统版本 macOS 14.0**。不要使用 macOS 15 / 26 专属 API；如必须使用，用 `if #available` 包裹并提供 fallback。
2. **不引入 Combine**。新代码统一使用 async/await + `AsyncStream` / `AsyncThrowingStream`。代码中不允许 `import Combine`。
3. **ASR provider 必须实现统一抽象 `ASRCaptureSession`**。不要在调用方写 provider switch；partial 语义差异在 `TranscriptAccumulator` 抹平，UI 节流统一走 `PartialTranscriptDisplayThrottle`（默认 220ms）。
4. **录音期间必须静音系统输出**，避免回授。逻辑集中在 `SystemAudioOutputMuteService`，不要在各 ASR provider 里各自实现。
5. **文本注入只走粘贴路径**（需要 Accessibility 权限），不要尝试 CGEvent 模拟键盘逐字输入。
6. **不在仓库里提交 API key、token、模型权重**。本地模型走 `ManagedASRModelStore` 下载到用户目录，按 provider 独立校验。
7. **触发键交互固定**：短按 = 听写切换，长按 ≥0.8s = 中→英翻译；右 Command 出现在组合键里时不触发；监听走 IOKit / CGEvent tap，不要换成 NSEvent global monitor。

### 7.2 其他约定

- 并发模型：Swift 6 严格并发，UI 相关类标 `@MainActor`；跨边界数据标 `Sendable`。
- UI：业务视图用 SwiftUI；菜单栏、overlay、窗口生命周期、权限弹窗用 AppKit。
- 字符串本地化：用户可见字符串通过 `AppLocalization.localized(_:)` 走本地化表，支持 en / zh-Hans / zh-Hant / ja。
- 调试：使用 `Sources/VoilyCore/Support/DebugLog.swift` 中的 `debugLog`，便于统一开关。
- Commit message：合并阶段需遵守 [Conventional Commits](https://www.conventionalcommits.org/)。
- 架构变更：新增模块、新增 ASR / LLM provider、协议改动、依赖方向调整时，需在 `docs/decisions/` 新增或更新 ADR。
- 文档同步：改动影响用户可见行为、配置方式、支持矩阵或架构边界时，同步更新 `README.md`、`README_CN.md`、`docs/ARCHITECTURE.md` 与相关 ADR。

## 8. 权限与系统集成

Voily 需要两类 macOS 权限：

- **麦克风**：录音前必须取得。`PermissionCoordinator` 负责状态读取和首次系统弹窗请求。
- **辅助功能（Accessibility）**：全局触发键监听和粘贴注入需要。`AccessibilityPermissionGuide` 通过 `PermissionFlow` 打开系统辅助功能设置，并把当前 App 作为建议授权对象。

设置页「输入」标签提供完整权限检查卡片；首页只显示状态胶囊和缺失权限 banner。权限状态只在相关页面 active 时轻量轮询，用户从系统设置授权后会自动刷新。

## 9. 发布与部署

应用通过 GitHub Releases 分发，不走 Mac App Store，保持 App Sandbox 关闭。

### 9.1 本地发布命令

```bash
make release          # Archive Release 构建 → build/release/Voily.app
make package-dmg      # 生成可分发 DMG
make verify-release   # 检查 bundle id、签名、Hardened Runtime、Gatekeeper

# 公证与装订（需要 VOILY_NOTARY_PROFILE）
ARTIFACT=build/release/artifacts/Voily-0.1.5.dmg make notarize
ARTIFACT=build/release/artifacts/Voily-0.1.5.dmg make staple
ARTIFACT=build/release/artifacts/Voily-0.1.5.dmg make verify-release
```

### 9.2 自动化发布

`.github/workflows/release.yml` 在推送 `vMAJOR.MINOR.PATCH` 标签时触发，运行在自托管 release runner（标签：`self-hosted`, `macOS`, `ARM64`, `voily-release`）。流程：

1. 检查签名身份、`VOILY_NOTARY_PROFILE`、Sparkle 私钥。
2. `make release` → `make package-dmg`。
3. 公证、装订、验证。
4. 读取 `docs/releases/${RELEASE_TAG}.md` 作为 GitHub Release body 与 Sparkle release notes。
5. 生成 `appcast.xml` 与 delta 更新包，上传至 GitHub Release。

版本规则：

- `project.yml` 中 `MARKETING_VERSION` 为三段语义版本（当前 `0.1.5`）。
- `CURRENT_PROJECT_VERSION` 为整数 build 号（当前 `5`）。
- Git tag 必须为 `v${MARKETING_VERSION}`，例如 `v0.1.5`。
- 必须存在 `docs/releases/v0.1.5.md`。

### 9.3 官网部署

`.github/workflows/deploy-website.yml` 在 `main` 分支 `website/**` 变更时触发，使用 Bun 构建并部署到 Cloudflare Pages。

### 9.4 PR 自动化代码审查

`.github/workflows/open-code-review.yml` 在 PR 开启 / 更新时运行，使用 DeepSeek LLM 进行只读审查，重点关注项目约束与实际缺陷，最多报告 3 条阻塞/严重问题。

## 10. 安全与合规

- **密钥与 token**：任何 API key、Sparkle 私钥、notarytool 凭证均不得提交到仓库。本地开发时 API key 由用户在 Settings 中填写。
- **签名与公证**：Release 使用 `Developer ID Application` 签名，启用 Hardened Runtime； entitlement 中声明 `com.apple.security.device.audio-input`。发布前必须完成公证与装订。
- **文本注入**：仅通过粘贴板 + Command+V 事件注入文本，并恢复用户原粘贴板内容；不使用逐字模拟键盘输入。
- **模型文件**：本地模型下载到用户目录，不在 app bundle 中分发；清除缓存不删除用户设置或云端凭证。
- **隐私**：Voily 不读取系统权限列表，也不持久化权限授权记录；权限缺失时录音和注入路径会停在本地提示。

## 11. 当前状态与常见陷阱

- 正在进行：稳定 macOS 14 兼容性回归后续修复；overlay 视觉简化收尾。
- **Settings 窗口生命周期**：`SettingsWindowController` / `AppController` 与 `NSApp.activationPolicy` 有耦合，关闭设置窗口不能让 app 退出。
- **Doubao 流式转写**：解码器对部分包格式敏感，改动后需回归 `docs/superpowers/specs/` 中的 case。
- **Fn 键监听**：依赖 IOKit / CGEvent tap，不能替换为 `NSEvent` global monitor，因为后者拿不到 Fn 的按下 / 抬起。
- **SenseVoiceResidentService**：旧的 Python / MLX 常驻服务路线已不再是默认热路径，仅作历史 fallback；默认本地 ASR 是 `SenseVoiceNativeService`。
- **触发键状态机**：核心逻辑在 `TriggerKeyMonitorCore` / `TriggerKeyGestureStateMachine` 中，不要在 `AppController` 里引入新的手势解释。

## 12. 知识地图

| 想了解什么 | 看哪里 |
|---|---|
| 用户快速开始 | `README.md` / `README_CN.md` |
| 架构全貌与关键流程 | `docs/ARCHITECTURE.md` |
| 开发、构建、测试、提交流程 | `CONTRIBUTING.md` |
| 架构决策与约束来源 | `docs/decisions/` |
| 测试分层与维护约定 | `docs/testing.md` |
| 签名、公证、GitHub Release 流程 | `docs/releasing.md` |
| 历史设计稿与回归用例 | `docs/superpowers/specs/` |
| 自动化审查规则 | `.coderabbit.yaml`、`.github/workflows/open-code-review.yml` |
| 自托管 agent workflow 规则 | `WORKFLOW.md` |

## Agent skills

### Issue tracker

Issues and PRDs are tracked as local markdown under `.scratch/`. See `docs/agents/issue-tracker.md`.

### Triage labels

Triage uses the default five-role vocabulary. See `docs/agents/triage-labels.md`.

### Domain docs

This repo uses a single-context layout, with `AGENTS.md` as the current domain context source and `docs/decisions/` for ADRs. See `docs/agents/domain.md`.
