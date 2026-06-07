---
date: 2026-06-07
status: accepted
tracks: []
---

# 本地 SenseVoice 改用原生 MLX Swift 推理

## 背景

ADR 0007 曾决定把 SenseVoice 的 Python / MLX runtime 随 app bundle 分发，只让用户下载约 900 MB 的模型权重。实测后 bundled runtime 约 436 MB，已经足够显著影响安装包体积、签名、公证、下载和更新体验。

同时，SenseVoice Small 的 MLX 文件集本身已经包含 Voily 需要的推理资产：`model.safetensors`、`config.json`、`am.mvn` 和 `chn_jpn_yue_eng_ko_spectok.bpe.model`。SenseVoice 的非自回归 CTC decode 路径也比 Whisper 类自回归模型简单：音频特征进入 encoder，CTC projection 后做 greedy decode，不需要 beam search 或逐 token autoregressive loop。

因此，当前问题不再是“如何把 Python runtime 打包得足够小”，而是“是否可以直接把 SenseVoice 推理层移到 Swift / MLX Swift，彻底移除 Python runtime 体积”。

## 决策

- 本地 SenseVoice 默认使用 `SenseVoiceNativeService`，通过 MLX Swift 在 app 进程内完成推理。
- App 依赖 `mlx-swift`，不再默认下载、准备、嵌入或发布 Python runtime。
- 模型权重继续由 `ManagedASRModelStore` 管理，放在 `~/Library/Application Support/Voily/LocalModels/senseVoice/model/`。
- 设置页的源卡片只用于选择下载来源。用户点击「下载模型」后，App 直接下载并校验模型文件；不要求用户访问 Hugging Face / ModelScope 或手动放置目录。
- 清除缓存只删除模型权重目录，不删除用户设置或云端 provider credentials；清除前要释放 native 已加载模型，避免继续持有旧权重。
- `make run`、`make install-debug`、`make release` 不再依赖 `prepare-sensevoice-runtime`。旧 runtime make target 保留为兼容 no-op，避免已有脚本立即失效。
- `SenseVoiceResidentService` 和 `SenseVoiceRuntimeResolver` 暂时保留为开发 fallback 和历史测试对象，但不再是默认本地 ASR 热路径。
- 原生实现必须覆盖以下能力：config 解析、safetensors 权重加载、CMVN、fbank + LFR 音频前处理、encoder forward、CTC greedy decode、SentencePiece piece 解码、语言选项和 ITN 选项。
- 原生实现需要有 opt-in smoke test，使用本机模型缓存实际加载权重并跑一次 forward；普通测试默认不加载 900 MB 模型。

## 放弃的方案

- **继续 bundled Python runtime**：实现风险低，但 runtime 约 436 MB，和“本地模型权重可下载、应用安装包尽量轻”的产品目标冲突。
- **要求用户自己安装 Python 或 mlx-audio**：把实现细节暴露给用户，会让本地引擎不可控，也会受到 Homebrew、venv、site-packages 和系统环境影响。
- **把模型权重塞进 app bundle**：模型约 900 MB，会让安装包、签名、公证和 Sparkle 更新都变重。
- **等待上游提供 SenseVoice 的 Swift drop-in runtime**：不确定性高，而且 Voily 当前只需要一个受控的 SenseVoice Small 路径。

## 后果

- 正面：安装包不再增加约 436 MB 的 Python runtime payload。
- 正面：本地 ASR 热路径在 app 进程内，少了 Python 进程启动、HTTP 服务、端口占用和 runtime 签名问题。
- 正面：用户模型 UX 保持简单：选择模型源、点击下载、必要时清除缓存。
- 负面：Voily 需要自己维护 SenseVoice Swift 推理层；模型结构、权重命名或上游文件格式变化时需要回归。
- 负面：需要补齐准确率和延迟对比测试，尤其是和 Python `mlx_audio.stt.load` 的中文、英文、粤语、日语、韩语样本结果对齐。
- 负面：MLX Swift 依赖需要 Xcode Metal Toolchain；开发机或 CI 缺失该组件时，需要先执行 `xcodebuild -downloadComponent MetalToolchain`。
