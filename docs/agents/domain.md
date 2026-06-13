# Domain Docs

本文件说明工程技能在探索 Voily 代码库时，应如何读取项目上下文与架构决策。

## Layout

本仓库使用 single-context 布局。

当前没有单独的 `CONTEXT.md` 或 `CONTEXT-MAP.md`。项目级上下文以根目录 `AGENTS.md` 为准；架构决策记录位于 `docs/decisions/`。

## Before exploring, read these

- `AGENTS.md`：项目简介、技术栈、模块分层、核心流程、约束和知识地图
- `docs/decisions/`：与当前任务相关的 ADR / decision record
- `README.md` / `README_CN.md`：用户视角的产品说明
- `docs/ARCHITECTURE.md`：架构全貌与关键流程，如文件存在且任务涉及架构时阅读
- `CONTRIBUTING.md` 和 `docs/testing.md`：涉及构建、测试或贡献流程时阅读

如果某个文件不存在，静默跳过，不要为了满足本文件而提前创建空文档。

## Vocabulary

输出 issue 标题、诊断假设、测试名称或重构建议时，优先使用 `AGENTS.md` 与相关 ADR 中已有的领域词汇，不要发明同义词。

## ADR conflicts

如果建议或实现会违反 `docs/decisions/` 中已有决策，需要显式指出冲突，并说明为什么值得重新打开这个决策。
