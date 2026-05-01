---
tracker:
  kind: linear
  project_slug: 91edc9d17632
  api_key: $LINEAR_API_KEY
  assignee: me
  active_states:
    - Todo
    - In Progress
    - Merging
    - Rework
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
  root: /Users/void/.concerto/workspaces/voily
hooks:
  after_create: |
    if [ ! -d .git ]; then
      git clone git@github.com:BubblePtr/Voily.git .
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
- 在 `Todo` / `In Progress` / `Rework` 阶段不要执行任何 git 发布动作，包括 `git commit`、`git push`、`gh pr create`、`git merge`、`git rebase`；这些阶段只允许普通文件修改和只读 git 命令。
- 只有当 issue 已经由人工推进到 `Merging` 时，才允许执行仓库收尾发布动作；不要直接 push 到 `main`。
- 如需查询或回写 Linear，请使用 `linear_graphql` 动态工具。
- 使用一个持久的 Linear 评论作为 proof-of-work 载体，标题必须是 `## Codex Workpad`；不要额外发布零散的完成总结评论。

状态流与停止规则：

- `Todo`：先推进到 `In Progress`，再创建或更新 `## Codex Workpad`，然后开始分析、实现和验证。
- `In Progress`：继续执行开发与验证，持续更新同一个 `## Codex Workpad`。
- `In Review`：人工验收态；看到该状态后不要继续编码，不要改 issue 内容，等待人工决策。
- `Rework`：按 review 反馈继续修正，更新同一个 `## Codex Workpad`，完成后重新回到验证与 handoff。
- `Merging`：人工已通过验收；只执行收尾发布流程，完成后推进到 `Done`。
- `Done`、`Canceled`、`Duplicate` 代表终态；不要继续工作。
- 如果缺少 repo checkout、Xcode、SwiftPM、测试依赖或其他必要环境，在 `## Codex Workpad` 的 `Notes` 与 `Validation` 中记录阻塞原因和需要的人类动作，然后停止；默认不要改状态。
- 如果仓库内修改和自动验证已经完成，但剩余工作需要真实 App、文件选择器、系统权限、音频输入或人工主观验收，在 `## Codex Workpad` 中记录“只差人工验收”的证据，然后把 issue 推进到 `In Review` 并停止。
- 不要把单纯的运行失败、编译失败或测试失败自动推进到 `In Review`；先在 `## Codex Workpad` 中写清当前失败点，再停止。

执行要求：

1. 先确认 workspace 中确实是 Voily 仓库，并记录环境戳到 `## Codex Workpad` 顶部：
   ```text
   <hostname>:<abs-workdir>@<short-sha>
   ```
2. 查找或创建一个未 resolved 的 `## Codex Workpad` 评论；后续计划、验收标准、验证记录、阻塞说明和 handoff notes 都只更新这个评论。
3. 在 `## Codex Workpad` 中维护这些章节，并在执行过程中持续勾选：
   - `### Plan`
   - `### Acceptance Criteria`
   - `### Validation`
   - `### Notes`
   - `### Confusions`（只有存在困惑时才保留）
4. 先复现或定位问题，再做最小修复；如果 issue 描述不够精确，优先通过代码路径和现有测试缩小范围，并把复现信号记录到 `Notes`。
5. 如果 issue 描述、评论中包含 `Validation`、`Test Plan` 或 `Testing` 要求，必须复制到 `Acceptance Criteria` 或 `Validation`，不能降级为可选项。
6. 严格按测试分层选择验证命令，不要默认运行 `make test`，也不要为了“更保险”自动追加 app-hosted `xcodebuild test`。
7. 如果改动主要落在下列 sandbox-safe / hostless 逻辑范围，优先只运行下面这条完整命令；不要先尝试不带 workspace-local module cache / scratch path 的旧版 `swift test` 命令：
   ```bash
   env CLANG_MODULE_CACHE_PATH="$PWD/.build/ModuleCache" \
     swift test \
     --disable-sandbox \
     --scratch-path "$PWD/.build"
   ```
   适用范围包括：
   - `Sources/Voily/Configuration/`
   - `Sources/Voily/Services/Audio/FunASRRealtimeService.swift`
   - `Sources/Voily/Services/Audio/FunASRVocabularyService.swift`
   - `Sources/Voily/Services/Audio/TranscriptLogic.swift`
   - `Sources/Voily/Services/Text/LLMRefinementService.swift`
   - `Sources/Voily/Storage/`
   - 其他明显不依赖 `Voily.app`、XCTest runner、GUI、系统权限、音频设备的纯逻辑改动
8. 如果改动命中了 app-hosted 代码路径，但当前任务只需要确认可编译，不需要实际运行 XCTest runner，则只运行下面这条完整命令；不要先尝试不带 `OTHER_SWIFT_FLAGS='$(inherited) -disable-sandbox'` 的旧版 `xcodebuild` 命令：
   ```bash
   env CLANG_MODULE_CACHE_PATH="$PWD/.xcodebuild/ModuleCache" \
     xcodebuild \
     -project "$PWD/Voily.xcodeproj" \
     -scheme Voily \
     -configuration Debug \
     -destination 'platform=macOS,arch=arm64' \
     -derivedDataPath "$PWD/.xcodebuild" \
     build-for-testing \
     CODE_SIGNING_ALLOWED=NO \
     ENABLE_USER_SCRIPT_SANDBOXING=NO \
     OTHER_SWIFT_FLAGS='$(inherited) -disable-sandbox'
   ```
   只有这条完整命令失败后，才允许把 app-hosted 编译验证标记为当前环境阻塞。
9. 只有 issue 明确依赖 app/runtime 行为，或者改动落在下列 runner-required 范围时，才允许运行 app-hosted XCTest：
   - `Sources/Voily/App/`
   - `Sources/Voily/Services/Audio/ASRCaptureSession.swift`
   - `Sources/Voily/Services/Audio/ASRConnectionTester.swift`
   - `Sources/Voily/Services/Audio/AudioCaptureService.swift`
   - `Sources/Voily/Services/Audio/DoubaoStreamingASRService.swift`
   - `Sources/Voily/Services/Media/SystemMediaPlaybackService.swift`
   - app resource、brand icon、trigger key 相关代码
   对应命令是：
   ```bash
   env CLANG_MODULE_CACHE_PATH="$PWD/.xcodebuild/ModuleCache" \
     xcodebuild \
     -project "$PWD/Voily.xcodeproj" \
     -scheme Voily \
     -configuration Debug \
     -destination 'platform=macOS,arch=arm64' \
     -derivedDataPath "$PWD/.xcodebuild" \
     test \
     CODE_SIGNING_ALLOWED=NO \
     ENABLE_USER_SCRIPT_SANDBOXING=NO \
     OTHER_SWIFT_FLAGS='$(inherited) -disable-sandbox'
   ```
   如果这条完整命令因为当前 sandbox、test runner 或系统服务边界失败，要在 `## Codex Workpad` 中明确记录，不要再升级到更宽的验证范围。
10. 不要运行需要人工交互的 GUI 验证流程来阻塞会话；遇到这类需求时按上面的停止规则处理，并把人工验收路径写入 `Acceptance Criteria`。
11. 每次有实质进展都更新 `## Codex Workpad`，至少包括：复现/定位完成、代码改动完成、每条验证命令及结果、阻塞或剩余人工步骤。
12. 移动到 `In Review` 之前，重新打开并刷新 `## Codex Workpad`，确保 `Plan`、`Acceptance Criteria`、`Validation` 与实际完成状态一致。
13. 只有在仓库内工作完成、验证绿色，且剩余工作只需要人工验收时，才推进到 `In Review`。

Merging 收尾规则：

1. 只有 issue 当前状态是 `Merging` 时才进入本节。
2. 不要继续开发新功能；只整理当前 workspace 中已通过人工验收的改动。
3. 重新确认 `## Codex Workpad` 中的 validation、人工验收结论和剩余事项。
4. 检查 `git status` 与 diff，确认改动范围只属于当前 issue。
5. 如果仓库需要提交，commit message 必须遵守 Conventional Commits。
6. 不要直接 push 到 `main`；如需发布，使用 feature 分支或仓库既有 PR 流程。
7. 如果无法安全完成发布动作，在 `## Codex Workpad` 记录阻塞原因并停止；不要推进到 `Done`。
8. 发布/合并完成后，把 issue 推进到 `Done`。

完成标准：

- 代码修改范围与 issue 直接相关。
- 至少运行一条与改动匹配的自动验证命令，或明确说明为什么当前环境无法运行。
- `## Codex Workpad` 是唯一 proof-of-work 来源，且包含环境戳、计划、验收标准、验证命令、结果、阻塞或人工验收说明。
- 不发布零散完成总结评论；只更新同一个 `## Codex Workpad`。
- 只有在“仓库内工作完成，只差人工验收”时才推进到 `In Review`。

Workpad 模板：

````md
## Codex Workpad

```text
<hostname>:<abs-workdir>@<short-sha>
```

### Plan

- [ ] 1. Parent task
  - [ ] 1.1 Child task
  - [ ] 1.2 Child task

### Acceptance Criteria

- [ ] Criterion 1
- [ ] Criterion 2

### Validation

- [ ] `<command>` -> `<result>`

### Notes

- <timestamp> <short progress note>

### Confusions

- <only include when something was confusing during execution>
````
