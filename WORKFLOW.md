---
tracker:
  kind: linear
  project_slug: 91edc9d17632
  api_key: $LINEAR_API_KEY
  assignee: me
  active_states:
    - Todo
    - In Progress
  terminal_states:
    - Done
    - Canceled
    - Duplicate
polling:
  interval_ms: 30000
server:
  host: 127.0.0.1
  port: 4011
workspace:
  root: /tmp/concerto_voily_workspaces
hooks:
  after_create: |
    if [ ! -d .git ]; then
      git clone /Users/void/code/opensource/voily .
    fi
agent:
  max_concurrent_agents: 1
  max_turns: 10
codex:
  command: codex app-server
  approval_policy: never
  thread_sandbox: workspace-write
  turn_timeout_ms: 1800000
  stall_timeout_ms: 180000
---
你正在处理 Voily 仓库中的 Linear issue `{{ issue.identifier }}`。

{% if attempt %}
这是第 {{ attempt }} 次重试。继续使用当前 workspace 中已有的文件状态，不要假设上一次的会话上下文仍然存在。
{% else %}
这是第一次处理这个 issue。
{% endif %}

当前 issue 信息：

- 标题：{{ issue.title }}
- 状态：{{ issue.state }}
- 标签：{{ issue.labels }}
- 链接：{{ issue.url }}

Issue 描述：
{{ issue.description | default: "无描述" }}

仓库与工程约束：

- 只在当前 workspace 中工作，不要越出该目录。
- 这是一次调试期的通用 workflow，不要要求人类做即时跟进。
- 优先做最小、可维护、易验证的修改；不要顺手重构无关模块。
- 保持 Voily 现有约束：最低 macOS 14、不要引入 Combine、ASR provider 继续走现有抽象。
- 不要执行任何 git 发布动作，包括 `git commit`、`git push`、`gh pr create`、`git merge`、`git rebase`。
- 可以使用只读 git 命令和普通文件修改。
- 如需查询或回写 Linear，请使用 `linear_graphql` 动态工具。

状态与停止规则：

- 如果 issue 仍在 `Todo`，开始工作前先推进到 `In Progress`。
- `Todo` 和 `In Progress` 是继续工作的状态。
- `In Review` 代表人工接手；看到该状态后不要继续编码。
- `Done`、`Canceled`、`Duplicate` 代表终态；不要继续工作。
- 如果缺少 repo checkout、Xcode、SwiftPM、测试依赖或其他必要环境，写一条 Linear 评论说明阻塞原因，然后停止；默认不要改状态。
- 如果仓库内修改和自动验证已经完成，但剩余工作需要真实 App、文件选择器、系统权限、音频输入或人工主观验收，写一条 Linear 评论说明“只差人工验收”，然后把 issue 推进到 `In Review` 并停止。
- 不要把单纯的运行失败、编译失败或测试失败自动推进到 `In Review`；先在评论中写清当前失败点，再停止。

执行要求：

1. 先确认 workspace 中确实是 Voily 仓库，并定位与 issue 最相关的模块、视图、测试或文档。
2. 先复现或定位问题，再做最小修复；如果 issue 描述不够精确，优先通过代码路径和现有测试缩小范围。
3. 验证命令优先使用仓库原生命令，例如 `make build`、`make test`，或更窄的 `xcodebuild test -only-testing:...`。
4. 不要运行需要人工交互的 GUI 验证流程来阻塞会话；遇到这类需求时按上面的停止规则处理。
5. 完成后在 Linear 留下简短评论，包含：
   - 已完成什么
   - 运行了哪些验证，结果如何
   - 是否存在阻塞或剩余人工步骤

完成标准：

- 代码修改范围与 issue 直接相关。
- 至少运行一条与改动匹配的自动验证命令，或明确说明为什么当前环境无法运行。
- Linear 中留下足够让人工接手的评论。
- 只有在“仓库内工作完成，只差人工验收”时才推进到 `In Review`。
