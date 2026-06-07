# Voily 架构全貌

> 本文件收编现有零散文档，作为 agent 与新贡献者理解整体结构的入口。

## 1. 模块分层

```
Sources/
├── VoilyCore/       # SwiftPM library，承载可脱离 app bundle 测试的核心逻辑
│   ├── Configuration/
│   ├── Services/
│   │   ├── Audio/   # Fun-ASR 消息/词库、转写文本累积与 partial 节流
│   │   └── Text/    # LLM 润色/翻译请求构造
│   ├── Storage/
│   └── Support/
└── VoilyApp/        # SwiftUI/AppKit app，承载系统集成与 UI
    ├── App/
    ├── Features/
    └── Services/
        ├── Audio/   # 录音、ASR capture session、云端/本地 app-hosted provider
        ├── Text/    # 粘贴注入
        └── Media/   # 系统播放静音

Resources/VoilyApp/  # Info.plist、entitlements、Assets、lproj、BrandIcons
project.yml          # XcodeGen 源文件，本地生成 Voily.xcodeproj
```

依赖方向：`VoilyApp` → `VoilyCore`。`VoilyCore` 不依赖 SwiftUI/AppKit UI、app bundle 生命周期、麦克风、辅助功能或代码签名状态。

## 2. 关键流程

### 2.1 一次听写

1. `TriggerKeyMonitor` 解析触发键手势：单击开始/结束普通听写，长按进入中→英快捷翻译；触发键可选 `Fn` 或 `右 Command`
2. `SystemMediaPlaybackService` 静音系统输出（防回授）
3. `AudioCaptureService` 拉取麦克风样本，喂给当前 ASR provider
4. 流式 provider 的 partial 经 `PartialTranscriptDisplayThrottle` 节流后更新浮窗；非流式路径只显示状态和最终结果
5. 普通听写在再次触发时收尾，快捷翻译通过 overlay 的确认/取消交互结束录音；随后拿到 final，可选走 `LLMRefinementService` 润色或翻译
6. `TextInjectionService` 通过粘贴注入光标位置
7. `UsageStore` 记录本次时长 / 字符数

### 2.2 ASR provider

统一会话抽象在 `Sources/VoilyApp/Services/Audio/ASRCaptureSession.swift`，provider 选择集中在 `LiveASRCaptureSessionFactory`。当前实现：

- `SenseVoiceNativeService`（本地，MLX Swift 进程内推理）
- `DoubaoStreamingASRService`（云端，WebSocket）
- `FunASRRealtimeService` + `FunASRVocabularyService`（云端，WebSocket + 热词词表同步）
- `QwenRealtimeASRService`（云端，HTTP/WS）
- `StepRealtimeASRService`（云端）

本地 SenseVoice 使用 MLX Swift 在 app 进程内推理，不再随安装包分发 Python runtime。模型权重仍由设置页下载到用户目录，见 [0008-native-mlx-swift-sensevoice-runtime.md](decisions/0008-native-mlx-swift-sensevoice-runtime.md)。

Settings 里的「测试连接」不属于 `ASRCaptureSession`；这一职责由独立的 `ASRConnectionTester` 承担。

新增 provider 见 [docs/decisions/0003-pluggable-asr-providers.md](decisions/0003-pluggable-asr-providers.md)。

### 2.3 LLM 文本润色

`LLMRefinementService` 通过兼容 OpenAI chat completions 的 HTTP 接口调用文本润色 provider。当前 provider 包括 DeepSeek、阿里云百炼、火山引擎、MiniMax、Kimi 和智谱；设置项统一保存在 `TextRefinementProviderConfig`，包含 Base URL、API Key 和 Model。

DeepSeek 的默认 Base URL 是 `https://api.deepseek.com`，默认模型是 `deepseek-v4-flash`，API Key 默认留空，由用户在设置中填写。升级旧配置时，`https://api.deepseek.com/v1` 会规范化为新的 Base URL，`deepseek-chat` 与 `deepseek-reasoner` 会迁移为 `deepseek-v4-flash`，已保存的 API Key 会保留。DeepSeek 请求会显式发送 `thinking: { type: "disabled" }`，避免文本润色路径输出思考内容或引入额外延迟。

## 3. 现有零散文档

不强迫迁移，原地保留，通过本文件链接收编：

- 用户向：[README.md](../README.md) · [README_CN.md](../README_CN.md)
- 历史设计稿（specs 跟踪入库；plans 是 agent 工作产物，已 gitignore，不在仓库内）：
  - [macOS 14 兼容性 design](superpowers/specs/2026-04-18-macos14-compatibility-design.md)
- 决策记录：[decisions/](decisions/)

## 4. 构建与发布

- `make build` — debug 构建
- `make prepare-sensevoice-runtime` — 兼容旧流程的 no-op；当前本地 SenseVoice 使用 MLX Swift runtime
- `make run` — 构建并运行
- `make install-dev` — 构建 Release/Developer ID 本地验收版并安装到 `/Applications`
- `make install-debug` — 构建 Debug/Apple Development 版并安装到 `/Applications`
- `make test` — 运行 SwiftPM 逻辑测试和 Xcode app/unit 测试；详见 [testing.md](testing.md)
- `make generate` — 用 XcodeGen 从 `project.yml` 生成本地 `Voily.xcodeproj`
- 更多目标见 [Makefile](../Makefile)

## 5. 权限与系统集成

- **麦克风**：录音前必须取得，由 `PermissionCoordinator` 负责状态读取和首次系统弹窗请求；设置页失败修复入口由 `MicrophonePermissionGuide` 通过 PermissionFlow 打开系统设置。
- **辅助功能（Accessibility）**：全局触发键监听和粘贴注入需要。`AccessibilityPermissionGuide` 通过 PermissionFlow 打开辅助功能设置，并把当前 App 作为建议授权对象传给引导面板。
- **权限状态 UI**：`SettingsPermissionSnapshot` 表示麦克风 / 辅助功能状态，`SettingsPermissionCard` 在输入设置页提供完整修复入口；首页只显示状态胶囊和缺失权限 banner，把交互引导回输入设置页。
- **刷新策略**：权限状态只在相关页面 active 时轻量轮询，用户从系统设置授权后会自动刷新；手动「重新检查」仍保留。
- **本地调试准备**：`make prepare-debug` 会先重置相关权限，并注销、移除已安装副本，再安装并启动调试构建，便于从 release / Developer ID 版本切换到本地 debug 版本。
- **菜单栏 / Dock**：菜单栏常驻，Dock 图标可选；关闭设置窗口不退出 app（见 `AppController`）。

权限引导决策见 [0006-permissionflow-permission-guidance.md](decisions/0006-permissionflow-permission-guidance.md)。
