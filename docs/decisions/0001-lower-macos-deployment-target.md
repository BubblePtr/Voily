---
date: 2026-04-18
status: accepted
tracks: []
---

# 将最低系统版本降到 macOS 14

## 背景

早期版本依赖 macOS 26 才有的 Liquid Glass 等 API（如 overlay 的玻璃质感壳层），导致大量 Sonoma / Sequoia 用户无法使用。社区反馈集中在「打不开」「样式异常」。

## 决策

将 deployment target 调整为 **macOS 14.0 (Sonoma)**，移除所有 macOS 26 专属 API 的硬依赖。需要新效果时改用 macOS 14 已有的 `Material` / `.regularMaterial` 等基础能力，必要时通过 `if #available` 渐进增强。

## 放弃的方案

- **保留 macOS 26 only**：用户面太窄，开源项目意义打折。
- **同时维护两套 UI 分支**：维护成本高，且 overlay 是核心交互路径，分叉会让回归测试爆炸。

## 后果

- 正面：覆盖用户面显著扩大；overlay 视觉一致性反而更可控。
- 负面：失去了一些 macOS 26 才有的视觉糖；后续若要回引高版本特性，必须强制走 `if #available` 路径，不允许整体抬升 deployment target 而不评估用户面影响。
- 约束沉淀进 `CLAUDE.md` 的「不能违反的约束」第 1 条。
