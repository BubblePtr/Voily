# Voily 架构全貌

> 本文件收编现有零散文档，作为 agent 与新贡献者理解整体结构的入口。

## 1. 模块分层

```
Sources/Voily/
├── App/             # 应用生命周期、Fn 键监听、权限协调
├── Configuration/   # 用户设置、语言枚举
├── Features/        # 业务 UI（SwiftUI）
│   ├── Overlay/     # 录音/转写浮窗
│   └── Settings/    # 设置窗口与 dashboard
├── Services/        # 核心能力实现
│   ├── Audio/       # 录音 + ASR provider
│   ├── Text/        # LLM 润色 + 文本注入
│   └── Media/       # 系统播放静音
├── Storage/         # 使用统计本地持久化
└── Resources/       # Assets / 配置资源
```

依赖方向：`App` → `Features` → `Services` / `Storage` → `Configuration`。下层不反向依赖上层。

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

统一会话抽象在 `Services/Audio/ASRCaptureSession.swift`，provider 选择集中在 `LiveASRCaptureSessionFactory`。当前实现：

- `SenseVoiceResidentService`（本地，MLX 常驻服务）
- `DoubaoStreamingASRService`（云端，WebSocket）
- `FunASRRealtimeService` + `FunASRVocabularyService`（云端，WebSocket + 热词词表同步）
- `QwenRealtimeASRService`（云端，HTTP/WS）
- `StepRealtimeASRService`（云端）

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
- `make run` — 构建并运行
- `make install` — 安装到 `~/Applications`
- `make test` — 运行 SwiftPM 逻辑测试和 Xcode app/unit 测试；详见 [testing.md](testing.md)
- 更多目标见 [Makefile](../Makefile)

## 5. 权限与系统集成

- **麦克风**：录音前必须取得，由 `PermissionCoordinator` 统一引导
- **辅助功能（Accessibility）**：粘贴注入需要，缺失时 `TextInjectionService` 会降级提示
- **菜单栏 / Dock**：菜单栏常驻，Dock 图标可选；关闭设置窗口不退出 app（见 `AppController`）
