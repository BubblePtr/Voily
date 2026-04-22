---
date: 2026-04-19
status: accepted
tracks: []
---

# ASR provider 通过统一协议接入

## 背景

Voily 需要同时支持本地引擎（SenseVoice）与多家云端流式 ASR（Doubao、Fun-ASR、Qwen、StepFun…），且后续会持续增加。早期某次新增 provider 时直接在调用方写了 `switch provider` 分支，导致 overlay / settings / 注入路径各自重复判断，新增引擎时改动面失控。

## 决策

所有 ASR 引擎通过统一会话抽象 `ASRCaptureSession`（位于 `Sources/Voily/Services/Audio/`）接入，暴露纯会话职责：

1. `start(onPartial:)`：启动一次实时会话并接收 partial 回调
2. `append(_:)`：持续喂入录音 buffer；chunk 级错误直接向上抛出
3. `finish()` / `cancel()`：主动结束会话拿到 final，或中途取消

调用方只持有协议类型，provider 选择集中在 `ASRCaptureSessionFactory` 一层。

连接测试不属于 `ASRCaptureSession`。settings 里的「测试连接」按钮继续走独立的 `ASRConnectionTester`，由 provider 配套 service（而不是捕获会话）提供探活能力；工厂层负责运行时 session 构建，`ASRConnectionTester` 负责配置侧连通性验证，两者边界分离。

### partial 语义统一

各家云 ASR 的 partial 协议语义不同，必须在协议层抹平后再交给上层：

| Provider | 事件 | 字段语义 | 处理 |
|---|---|---|---|
| Fun-ASR | `result-generated` | 当前句快照，`sentence_end=true` 时提交 final sentence | `updatePartial` 替换 + `commitCurrentSentence` |
| StepFun | `conversation.item.input_audio_transcription.delta` | 增量片段 | `appendDelta` 累积 |
| Doubao | `decoded.text` | 当前 utterance 快照 | `updatePartial` 直接替换 |
| Qwen | `conversation.item.input_audio_transcription.text` | partial 快照 | `updatePartial` 直接替换 |

由 `TranscriptAccumulator` 统一对外提供 `currentPartialText`；UI 侧的 `PartialTranscriptDisplayThrottle` 默认 220ms 节流，所有 provider 共用，避免逐家在 overlay 里重复防抖。

## 放弃的方案

- **每个 provider 一个独立 ViewModel + 调用路径**：复制粘贴严重，bug 修一处漏三处。
- **沿用系统 Speech.framework 回退链路**：会让调用方继续承担 provider 特判，与项目其它部分的 async/await 风格不一致（见 ADR 0002）。

## 后果

- 正面：新增 provider 只需实现协议 + 在工厂注册 + 写 settings 配置面板；overlay / 注入路径零改动。像 Fun-ASR 这类需要额外词表同步的 provider，也应把差异收敛在 provider/配套 service 内，而不是泄漏到 UI。
- 负面：不同云厂商的鉴权 / 配置字段差异大，settings 面板仍需 per-provider 实现，无法完全抽象 —— 接受，settings 是天然的边界。
- 约束沉淀进 `CLAUDE.md` 的「不能违反的约束」第 3 条。
