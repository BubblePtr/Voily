# Voily Pre-launch Roadmap

## Week 1 — 发布基础设施
- 基于现有 release 文档和设计稿，落地 GitHub Actions 自动发布流程
- tag 触发 → 构建 → 公证 → 发布 DMG 到 GitHub Releases
- 验收条件：self-hosted runner、tag/version 校验、beta/rc 预发布规则、已有 release 不覆盖而是失败
- 验证 macOS 14 / 15 安装包可用

## Week 2 — 本地模型下载体验
- 下载进度百分比（现在只有文字消息，无 %）
- 下载速度 / 剩余时间显示
- 失败自动重试 + 明确错误提示
- 首次启动引导：当用户选择本地 provider 且该 provider 未安装时，主动提示下载

## Week 3 — 识别稳定性
- 优先处理首包误识别问题（例如静音时首个字误显示为“嗯”）
- 评估 partial 展示稳定策略，减少过早显示的误识别文本
- 评估 speech enhancement / competing-speaker suppression，确认是否需要引入前端语音增强
- 本地 SenseVoice 推理参数调优（beam size、语言检测阈值）
- 云端 provider 测评对比，默认推荐最优配置

## Week 4 — 本地优先 Onboarding
- 首次启动弹出 onboarding，默认推荐本地 SenseVoice
- 麦克风权限继续走系统原生请求
- Accessibility 权限引导接入 PermissionFlow
- 本地模型下载允许跳过，不阻塞进入主界面
- 若用户跳过 Accessibility 授权或本地模型下载，则在后续每次启动时，于 dashboard 顶部显示非阻塞 reminder
- 完成首次本地体验后，再引导用户按需配置云端 provider

## Week 5 — 落地页
- 产品官网（功能介绍、截图/录屏 Demo、下载按钮）
- SEO 基础：macOS 语音输入法关键词
- 下载安装引导页

## Week 6 — 文档 & 社区准备
- 用户文档：安装、各 ASR provider 配置、FAQ
- 贡献指南（CONTRIBUTING.md）+ issue 模板
- README 更新（徽章、截图、快速上手）

## Week 7 — Launch 冲刺
- 内测 / Beta 收集反馈
- 覆盖高频 bug
- Product Hunt / 即刻 / 少数派发布准备
