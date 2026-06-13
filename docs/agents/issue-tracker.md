# Issue tracker：Local Markdown

本仓库的 issues 和 PRD 以 markdown 文件形式存放在 `.scratch/` 下。

## 约定

- 一个功能或工作流对应一个目录：`.scratch/<feature-slug>/`
- PRD 文件为：`.scratch/<feature-slug>/PRD.md`
- 实施 issue 放在：`.scratch/<feature-slug>/issues/<NN>-<slug>.md`
- issue 编号从 `01` 开始
- triage 状态记录为 issue 文件顶部附近的 `Status:` 行
- 状态字符串见 `docs/agents/triage-labels.md`
- 评论和对话历史追加到文件底部的 `## Comments` 区域

## 当技能说 “publish to the issue tracker”

在 `.scratch/<feature-slug>/` 下创建对应 markdown 文件；目录不存在时先创建目录。

## 当技能说 “fetch the relevant ticket”

读取用户提供的 `.scratch/` 路径、issue 编号或相关 markdown 文件。
