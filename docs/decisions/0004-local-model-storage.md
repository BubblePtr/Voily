---
date: 2026-04-19
status: accepted
tracks: []
---

# 本地 ASR 模型走用户目录托管，按 provider 独立校验

## 背景

本地 ASR（SenseVoice Small，约 936MB）需要落盘到用户机器，又不能塞进 app bundle（体积、签名、更新都吃不消）。早期评估过 GGUF CLI 批处理模式，随后收敛为常驻服务路线；当前运行时已改为 MLX Swift 原生推理，见 ADR 0008。

## 决策

- 模型文件存放在 `~/Library/Application Support/Voily/LocalModels/`，由 `ManagedASRModelStore` 管理下载、校验、卸载。
- 不同 provider（ONNX / MLX 模型目录）**各自独立校验**，不共用一个全局「已就绪」状态——某 provider 模型缺失不应阻塞其它 provider 可用。
- 本地 ASR 上层只看到统一的 `ASRCaptureSession` 抽象（见 ADR 0003）；当前 SenseVoice 热路径由 `SenseVoiceNativeService` 通过 MLX Swift 在 app 进程内推理，见 ADR 0008。
- `SenseVoiceResidentService` 曾用于 Python / MLX 常驻服务路线，当前只保留为开发 fallback 和历史测试对象。

## 放弃的方案

- **塞进 app bundle**：bundle 体积爆炸，签名/公证流程拖慢发布。
- **每次启动从 CLI 冷加载**：实测延迟过高（>500ms），常驻服务把热路径压到 ~120ms。
- **统一「模型就绪」全局开关**：一旦新增 provider 就破坏既有 provider 的可用状态，违反 ADR 0003 的可插拔精神。

## 后果

- 正面：用户可以按需安装/卸载某个本地引擎；新增本地 provider 不动既有路径。
- 负面：用户首次使用要等下载；存储路径在 `Application Support` 下，删 app 不会自动清理 —— 卸载文档需要点出这一点。
- 仓库内**严禁**提交模型权重（已在 CLAUDE.md「不能违反的约束」第 6 条声明）。
