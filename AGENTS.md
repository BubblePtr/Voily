# Voily

## 这是什么

开源 macOS 听写应用：按一下触发键开始录音，再按一下停止转写，自动粘贴到光标位置。支持本地 / 云端 ASR 引擎，可选 LLM 文本润色，提供实时浮动 overlay。

## 技术栈

- SwiftUI + AppKit（菜单栏 / 浮窗 / 系统集成走 AppKit，业务 UI 走 SwiftUI）
- 最低系统版本：macOS 14.0 (Sonoma)
- 包管理：SPM
- 工程：Voily.xcodeproj，命令行用 `make build` / `make run` / `make install`

## 不能违反的约束

1. **最低系统版本 macOS 14.0**。不要使用 macOS 15 / 26 才有的 API；如必须使用，必须用 `if #available` 包裹并提供 fallback。详见 `docs/decisions/0001-lower-macos-deployment-target.md`。
2. **不引入 Combine**。新代码统一使用 async/await + AsyncStream。详见 `docs/decisions/0002-async-await-over-combine.md`。
3. **ASR provider 必须实现统一抽象**。新增引擎走 `SpeechTranscriptionService` 协议，不在调用方写 if/else 分支；partial 语义差异在 `TranscriptAccumulator` 抹平，UI 节流统一走 `PartialTranscriptDisplayThrottle`（默认 220ms）。详见 `docs/decisions/0003-pluggable-asr-providers.md`。
4. **录音期间必须静音系统输出**，避免回授。逻辑集中在 `SystemMediaPlaybackService`，不要在各 ASR provider 里各自实现。
5. **文本注入只走粘贴路径**（需要 Accessibility 权限），不要尝试 CGEvent 模拟键盘逐字输入。
6. **不在仓库里提交 API key、token、模型权重**。本地模型走 `ManagedASRModelStore` 下载到 `~/Library/Application Support/Voily/LocalModels/`，按 provider 独立校验。详见 `docs/decisions/0004-local-model-storage.md`。
7. **触发键交互固定**：短按=听写切换（tap 开始，再 tap 结束），长按（≥0.8s）=中英翻译；右 Command 出现在组合键里时不触发；监听走 IOKit，不要换成 NSEvent global monitor。详见 `docs/decisions/0005-trigger-key-interaction.md`。

## 知识地图

- 架构全貌 → [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md)
- 决策背后的原因 → [docs/decisions/](docs/decisions/)
- 历史设计稿（specs 跟踪入库；plans 已 gitignore） → [docs/superpowers/specs/](docs/superpowers/specs/)
- 用户文档（中英） → [README.md](README.md) / [README_CN.md](README_CN.md)

## 当前状态

- 正在做：稳定 macOS 14 兼容性回归后续修复；overlay 视觉简化收尾
- 勿踩：
  - Settings 窗口的 SwiftUI Scene 生命周期与 NSApp activation policy 有耦合，关闭窗口不能让 app 退出 —— 见 `AppController` / `SettingsWindowController`
  - Doubao 流式转写的解码器对部分包格式敏感，改动需要回归 [docs/superpowers/specs](docs/superpowers/specs) 里的 case
  - Fn 键监听依赖 IOKit，不要替换成 NSEvent global monitor（拿不到 Fn 的按下/抬起）
