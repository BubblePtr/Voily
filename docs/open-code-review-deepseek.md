# Open Code Review 接入 DeepSeek 试用手册

本文记录在 Voily 仓库中用 DeepSeek 作为 Open Code Review 后端模型的本地试用命令。目标是让 OCR 专门承担 review，不自动修改代码。

更新时间：2026-06-08。

## 前提

- 已有 DeepSeek API key。
- 本机有 Node.js / npm。
- 不把 API key 写进仓库、文档、commit message 或 PR 描述。
- 当前命令使用 Open Code Review `1.2.4`。

DeepSeek 官方当前推荐的 OpenAI-compatible base URL 是：

```text
https://api.deepseek.com
```

但 Open Code Review 的 `OCR_LLM_URL` 需要填写完整 LLM API endpoint，因此这里使用：

```text
https://api.deepseek.com/chat/completions
```

优先使用当前模型名：

- `deepseek-v4-flash`：日常 review 优先使用，成本和延迟更可控。
- `deepseek-v4-pro`：重要 PR 或需要更强推理时使用。

不要再新配置 `deepseek-chat` / `deepseek-reasoner`。DeepSeek 官方已标注
这两个旧模型名会在 2026-07-24 15:59 UTC 退役。

## 临时试用

推荐先用临时 shell function，不全局安装 `ocr`：

```bash
ocrx() {
  npx --yes @alibaba-group/open-code-review@1.2.4 "$@"
}
```

设置 DeepSeek 环境变量：

```bash
export DEEPSEEK_API_KEY="替换成你的 DeepSeek API key"

export OCR_LLM_URL="https://api.deepseek.com/chat/completions"
export OCR_LLM_TOKEN="$DEEPSEEK_API_KEY"
export OCR_LLM_MODEL="deepseek-v4-flash"
export OCR_USE_ANTHROPIC=false
```

如果要用更强模型，把模型改成：

```bash
export OCR_LLM_MODEL="deepseek-v4-pro"
```

先检查 CLI 和 LLM 连通性：

```bash
ocrx version
ocrx llm test
```

## Review 当前工作区改动

当前工作区模式会 review staged、unstaged 和 untracked changes。

先预览会审哪些文件，不调用 LLM：

```bash
ocrx review --preview
```

准备 Voily 专用背景信息：

```bash
VOILY_OCR_BACKGROUND="$(cat <<'EOF'
Voily 是 macOS 14+ SwiftUI/AppKit 听写应用。请重点检查：
- 不要使用 macOS 15/26-only API。
- 不要引入 Combine。
- ASR provider 必须走 SpeechTranscriptionService 抽象。
- 录音期间系统输出静音逻辑必须留在 SystemMediaPlaybackService。
- 文本注入只能走 Accessibility 粘贴路径。
- Fn/触发键监听必须保留 IOKit 路线，不要改成 NSEvent global monitor。
EOF
)"
```

确认范围后再执行 review：

```bash
ocrx review \
  --audience agent \
  --background "$VOILY_OCR_BACKGROUND"
```

## Review 当前分支相对 main 的改动

先更新远端引用：

```bash
git fetch origin main
```

预览 diff 范围：

```bash
ocrx review --preview --from origin/main --to HEAD
```

执行 review：

```bash
ocrx review \
  --audience agent \
  --from origin/main \
  --to HEAD \
  --background "$VOILY_OCR_BACKGROUND"
```

## Review 单个 commit

```bash
ocrx review \
  --audience agent \
  --commit abc1234 \
  --background "$VOILY_OCR_BACKGROUND"
```

## 输出 JSON

需要给其他脚本或 agent 消费时，使用 JSON 输出：

```bash
ocrx review \
  --audience agent \
  --format json \
  --from origin/main \
  --to HEAD \
  --background "Voily 是 macOS 14+ SwiftUI/AppKit 听写应用。请按项目约束检查改动。"
```

## GitHub Actions CI

仓库提供 `.github/workflows/open-code-review.yml`，用于在 PR 上运行
Open Code Review。当前 CI 版本只做 review，不自动修改代码，也不直接向 PR
发布 inline comments；结果会写入 GitHub Actions job summary，并上传
`ocr-result` artifact。

### 配置 secret

在 GitHub 仓库设置中添加 Actions secret：

```text
DEEPSEEK_API_KEY
```

这个 secret 会映射到 OCR 的 `OCR_LLM_TOKEN` 环境变量。不要把 API key
写入 workflow、文档、commit message 或 PR 描述。

如果需要切换模型，可以添加 Actions variable：

```text
OCR_LLM_MODEL=deepseek-v4-pro
```

未设置时，CI 默认使用：

```text
deepseek-v4-flash
```

### 触发范围

CI 会在这些 PR 事件运行：

- opened
- synchronize
- reopened
- ready_for_review

如果 PR 仍是 draft，workflow 会跳过。`pull_request` 事件不会把仓库
secret 暴露给来自 fork 的 PR，所以外部 fork PR 在没有 secret 的情况下会
安全跳过 OCR。

### 设计取舍

Open Code Review 官方示例使用 `pull_request_target` 来让 fork PR 也能访问
secret，并通过 GitHub API 发布 PR review comments。Voily 当前先采用更保守
的 `pull_request` 接入：

- 不在 fork PR 上暴露 DeepSeek API key。
- 不执行 PR 代码，只安装固定版本 OCR CLI 并分析 Git diff。
- 不向 PR 自动发布大量 bot comment，先通过 Actions summary/artifact 观察质量。

确认质量稳定后，可以再评估是否切换到官方 PR comment 工作流。

## 持久安装

如果确认质量可以接受，再全局安装：

```bash
npm install -g @alibaba-group/open-code-review@1.2.4
```

之后命令里的 `ocrx` 可以换成 `ocr`：

```bash
ocr version
ocr llm test
ocr review --preview
```

也可以写入 OCR 的用户级配置：

```bash
ocr config set llm.url https://api.deepseek.com/chat/completions
ocr config set llm.auth_token "$DEEPSEEK_API_KEY"
ocr config set llm.model deepseek-v4-flash
ocr config set llm.use_anthropic false
```

配置文件会写入：

```text
~/.opencodereview/config.json
```

如果只想本次 shell 临时使用，优先用环境变量，不写持久配置。

## 清理本次 shell 凭据

```bash
unset DEEPSEEK_API_KEY
unset OCR_LLM_URL
unset OCR_LLM_TOKEN
unset OCR_LLM_MODEL
unset OCR_USE_ANTHROPIC
```

## 使用建议

- 先用 `ocrx review --preview` 看范围，再跑正式 review。
- 默认只把 OCR 当 reviewer，不让它自动修改代码。
- 对 Voily 的 Swift/macOS 约束，必须通过 `--background` 明确喂给 OCR。
- OCR 的发现需要人工分级：优先处理明显 bug、权限边界、macOS 14 兼容性和测试缺口；低置信度风格建议不要直接照单全收。
- 如果 DeepSeek 触发 rate limit，先把 OCR 并发降下来：

```bash
ocrx review \
  --audience agent \
  --concurrency 2 \
  --from origin/main \
  --to HEAD \
  --background "Voily 是 macOS 14+ SwiftUI/AppKit 听写应用。请按项目约束检查改动。"
```

## 参考

- DeepSeek API Docs: <https://api-docs.deepseek.com/>
- Open Code Review: <https://github.com/alibaba/open-code-review>
