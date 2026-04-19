---
date: 2026-04-19
status: accepted
tracks: []
---

# 使用 async/await + AsyncStream 替代 Combine

## 背景

Voily 的核心数据流是「麦克风样本 → ASR partial → final → 润色 → 注入」，本质是一条单向的异步流水线。早期评估过用 Combine 串联各阶段。

## 决策

统一用 **async/await + AsyncStream / AsyncThrowingStream** 表达异步流；UI 侧用 SwiftUI 的 `@Observable` / `@StateObject` 直接订阅状态，不引入 Combine 的 `Publisher` 链。

## 放弃的方案

- **Combine**：操作符链在调试时栈极深；`AnyCancellable` 生命周期管理与 ASR provider 的连接生命周期容易错配；与 async/await 桥接需要额外 boilerplate。
- **回调闭包 / delegate**：状态机一旦超过 3 个阶段就难以读懂，且容易漏掉错误传播。

## 后果

- 正面：错误传播沿 `try await` 自然向上；取消通过 `Task` 取消即可，与 ASR WebSocket 关闭路径对齐。
- 负面：部分 SwiftUI 视图需要在 `.task { }` 里手动消费 stream，比 Combine 的 `.sink` 略啰嗦 —— 接受。
- 约束沉淀进 `CLAUDE.md` 的「不能违反的约束」第 2 条。新代码不允许 `import Combine`。
