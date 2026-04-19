# 架构决策记录（ADR）

每个重要决策一个文件，命名 `NNNN-动词-名词.md`。

## 为什么要写

让 agent（与新贡献者）遇到相关问题时**不重新发明轮子或反向操作约束**。例：写过「评估过 Combine，选了 async/await」的 ADR，agent 就不会在新功能里突然引入 Combine。

## 怎么写

- Frontmatter 三个字段：`date` / `status` / `tracks`（freshness 检查用，可空）
- 正文四段：背景 / 决策 / 放弃的方案 / 后果
- 10–15 分钟一个，不追求完美

## status 取值

- `proposed` — 提议中
- `accepted` — 已接受（默认）
- `deprecated` — 已废弃，但未被替代
- `superseded-by:NNNN` — 被另一条 ADR 替代

## 踩坑往哪写

- **稳定的坑**（直接的约束）→ `CLAUDE.md` 的「勿踩」字段
- **有来龙去脉的坑**（坑改变了决策）→ 写成 ADR，背景里说明踩了什么坑

## 当前 ADR

- [0001 将最低系统版本降到 macOS 14](0001-lower-macos-deployment-target.md)
- [0002 使用 async/await + AsyncStream 替代 Combine](0002-async-await-over-combine.md)
- [0003 ASR provider 通过统一协议接入](0003-pluggable-asr-providers.md)
- [0004 本地 ASR 模型走用户目录托管，按 provider 独立校验](0004-local-model-storage.md)
- [0005 触发键固定单击/双击语义，不开放快捷键自定义](0005-trigger-key-interaction.md)
