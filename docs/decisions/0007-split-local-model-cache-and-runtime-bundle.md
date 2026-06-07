---
date: 2026-06-06
status: superseded-by:0008
tracks: []
---

# 本地 ASR 拆分模型缓存与应用内运行时

> 本 ADR 保留 bundled Python runtime 方案的历史上下文。当前实现已由 [0008 本地 SenseVoice 改用原生 MLX Swift 推理](0008-native-mlx-swift-sensevoice-runtime.md) 取代：模型缓存仍放在用户目录，但应用不再打包 Python runtime。

## 背景

SenseVoice Small 的模型权重大约 900 MB，不适合塞进 app bundle，也不适合跟随应用更新一起分发。现有方案由 `ManagedASRModelStore` 直接从 Hugging Face 下载模型文件，但运行时路径仍依赖 `~/Library/Application Support/Voily/LocalModels/senseVoice/runtime/python/bin/python3`。这导致两个问题：

- 新用户下载模型后，可能只有权重文件，没有可用的 Python / MLX 运行时。
- 开发机上残留的本地 venv 会掩盖真实发布路径；这个 venv 还可能链接到 Homebrew Python，不能作为可分发运行时。

本地 ASR 的责任边界需要重新拆开：App 负责提供可运行的稳定 runtime，用户只处理体积较大的模型权重缓存。

## 决策

- SenseVoice runtime 随 app bundle 分发，放在 `Voily.app/Contents/Library/SenseVoiceRuntime/`。Python runtime 包含 native extension、动态库和大量普通 Python 数据文件；不能作为普通 Resource 复制，否则 signed app bundle 内的 native extension 加载可能卡住，也不能整体放进 Frameworks，否则 `codesign --deep --strict` 会把普通脚本、pkgconfig、Tcl/Tk 等文件按 nested code 规则处理。
- Runtime 包含启动常驻服务需要的 Python 解释器、MLX 依赖、FastAPI / Uvicorn / Pydantic、native 动态库，以及 `sensevoice_resident_server.py`。
- Runtime payload 由 `make prepare-sensevoice-runtime` 在本地生成到 `Resources/VoilyApp/SenseVoiceRuntime/`；`python/` 和 `manifest.json` 不提交到 git，构建 / 发布时由 `scripts/embed_sensevoice_runtime.sh` 复制进 app bundle，清理不需要的开发入口和 Tcl/Tk 文件，并签名 runtime 内的 Mach-O 文件。
- Release 验证必须检查 `SenseVoiceRuntime/python/bin/python3` 可执行、`server/sensevoice_resident_server.py` 存在，并且 bundled Python 能导入 `fastapi`、`pydantic`、`uvicorn`、`mlx`、`mlx_audio.stt`。
- 当前 release 路线继续使用 Python MLX 常驻服务，不在本轮改动中切到 MLX Swift。原因是现有 SenseVoice 路线依赖 `mlx_audio.stt.load` 提供的完整 ASR pipeline；切到 MLX Swift 需要额外移植模型结构、config 解析、tokenizer / BPE、音频前处理、decode、语言选项和 ITN。
- MLX Swift 只作为后续 spike 评估：验证能否加载 `mlx-community/SenseVoiceSmall` 文件集、转写结果是否一致、包体和延迟是否明显优于 bundled Python runtime 后再决策。
- 模型权重继续放在用户目录：`~/Library/Application Support/Voily/LocalModels/senseVoice/model/`。
- 用户可在设置页选择模型源；源卡片只负责选择下载来源，不跳转到外部网站。
- App 负责托管大模型下载。设置页提供「下载模型」主操作，下载完成后自动落到 Voily 的模型缓存目录并校验。
- ModelScope 源使用 `modelscope.cn/models/mlx-community/SenseVoiceSmall/resolve/master/` 下的 MLX 文件集；Hugging Face 源使用 `huggingface.co/mlx-community/SenseVoiceSmall/resolve/main/` 下的同名文件集。
- 手动选择模型目录只作为高级兜底入口，不作为普通用户的主流程。
- 清除缓存只删除模型权重目录，不删除 runtime、不删除用户设置、不删除云端 provider credentials。
- `SenseVoiceResidentService` 启动时优先使用 app bundle 内 runtime；`VOILY_SENSEVOICE_PYTHON` 只作为开发和排障 fallback。
- 使用 bundled Python 时，App 会设置隔离的 `PYTHONHOME`、`PYTHONNOUSERSITE`、`PYTHONDONTWRITEBYTECODE` 和 `DYLD_LIBRARY_PATH`，避免用户机器上的 Python site-packages 或 Homebrew 路径影响本地 ASR。
- 模型可用性不能只靠文件存在判断。至少校验必需文件列表和大小；发布版本应使用 manifest 固定文件名、来源、revision、字节数和 SHA256。
- 清除模型缓存前必须先停止 SenseVoice 常驻服务，避免运行中进程继续读写被删除的模型目录。

## 设置页状态机

本地模型区域至少暴露以下状态：

- `runtimeUnavailable`：App 内 runtime 缺失或不可执行。这是发布包问题，不要求用户修复。
- `modelMissing`：未找到模型权重，展示推荐源和下载入口。
- `modelDownloading`：正在从选定模型源下载权重文件，完成后进入校验。
- `modelIncomplete`：找到部分文件，但必需文件缺失或大小不对，提示重新导入或清除缓存。
- `modelValidating`：正在校验已选择的模型目录。
- `modelReady`：模型通过校验，可用于本地识别。
- `modelInvalid`：模型存在但校验失败，展示失败原因。

用户动作：

- 选择 ModelScope / Hugging Face 模型源。
- 点击「下载模型」，由 App 下载、安装并校验模型文件。
- 手动导入已下载的模型目录（高级兜底）。
- 重新校验模型。
- 清除本地模型缓存。

## 目录结构

App bundle 内 runtime：

```text
Voily.app/
  Contents/
      Library/
        SenseVoiceRuntime/
          python/
            bin/python3
            lib/...
          server/
            sensevoice_resident_server.py
          manifest.json
```

用户模型缓存：

```text
~/Library/Application Support/Voily/
  LocalModels/
    senseVoice/
      model/
        model.safetensors
        config.json
        am.mvn
        chn_jpn_yue_eng_ko_spectok.bpe.model
      model-manifest.json
```

## 放弃的方案

- **把模型权重塞进 app bundle**：会显著放大发布包体积，拖慢下载、签名、公证和更新。
- **要求用户去网站下载再选择目录**：把模型仓库、文件名、目录结构暴露给普通用户，门槛过高。
- **把本地 venv 直接打包**：venv 可能包含绝对路径和 Homebrew symlink，不能保证在用户机器上可重定位。
- **要求用户配置 Python runtime**：把实现细节暴露给用户，和“本地引擎开箱可用”的产品目标冲突。
- **本轮直接改用 MLX Swift**：MLX Swift 是更原生的长期方向，但不是现有 SenseVoice MLX 文件集的完整 drop-in ASR runtime。直接切换会把本轮下载、缓存和 runtime 打包问题扩大成模型移植项目；需要先独立 spike 验证加载、tokenizer、音频前处理、decode、ITN、准确率、包体和延迟。

## 后果

- 正面：新用户只需要处理模型权重；运行时由发布包保证，故障边界更清楚。
- 正面：普通用户只需要点一次下载，不需要理解模型仓库和目录结构。
- 正面：模型缓存可以安全清除、重新下载或手动导入，不影响 app 自身运行时。
- 正面：ModelScope / Hugging Face 可以作为用户可见的模型源选择，下载器只依赖每个源声明的文件 URL 清单。
- 正面：当前问题被限定在 runtime packaging 和模型缓存 UX，不阻塞本地 ASR 的产品链路。
- 负面：发布包会变大，需要在 release 验证里加入 runtime bundle 的签名、可执行性和启动检查。
- 负面：需要新增 runtime 打包流程，不能复用开发机上的 venv。
- 负面：Settings 需要承担模型下载、导入、校验和清缓存的完整状态机。

## 迁移策略

- 如果旧目录中存在 `LocalModels/senseVoice/runtime/`，新版本不再使用它。
- 迁移时只保留 `LocalModels/senseVoice/model/` 下通过校验的模型权重。
- 设置页可在检测到旧 runtime 目录时提示“旧运行时不再使用”，但清除模型缓存不应删除旧 runtime；旧 runtime 清理应作为单独维护动作，避免误删用户模型。
- 旧的 `ManagedASRModelStore` 应收敛为模型缓存管理器，职责限定为下载、导入、校验、状态暴露和清除模型权重。
