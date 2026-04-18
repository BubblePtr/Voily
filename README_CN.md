<h1 align="center">Voily</h1>

<p align="center">语言: <a href="./README.md">EN</a> | 简中</p>

<p align="center">
  <img src="https://img.shields.io/badge/macOS_26.0+-black?style=flat-square&logo=apple&logoColor=white" alt="macOS 26.0+">
  <img src="https://img.shields.io/badge/Swift-orange?style=flat-square&logo=swift&logoColor=white" alt="Swift">
  <img src="https://img.shields.io/badge/License-Apache_2.0-blue?style=flat-square" alt="Apache 2.0">
  <img src="https://img.shields.io/badge/Open_Source-green?style=flat-square" alt="开源">
</p>

**按下 Fn，说话，文字出现在光标处。**

Voily 是一款开源的 macOS 语音听写应用。按住 Fn 键录音，松开即转写，识别结果自动粘贴到当前光标位置——适用于任何应用。支持本地和云端 ASR 引擎、可选的 LLM 文本润色，以及实时浮窗显示转写进度。

## ✨ 功能特性

- **Fn 键触发听写** — 按住 Fn 录音，松开后转写并粘贴。双击 Fn 可快速中译英。
- **多种 ASR 引擎** — 可选本地（SenseVoice）或云端（豆包流式语音识别、通义 Qwen ASR）语音识别。
- **实时部分结果** — 说话时浮窗实时显示转写文字。
- **LLM 文本润色** — 可选用 LLM（DeepSeek、阿里云百炼、火山引擎、MiniMax、Kimi、智谱）对转写结果进行后处理：去语气词、正式化、整理成列表。
- **术语表支持** — 自定义术语和内置术语预设，提升专业词汇的识别准确率。
- **快速翻译** — 双击 Fn 键，用中文口述，输出英文。
- **菜单栏仪表盘** — 在菜单栏查看今日用量（时长、次数、字数）及近一周趋势图。
- **原生轻量** — 使用 SwiftUI 和 AppKit 构建，常驻菜单栏，可选显示 Dock 图标。

## 📋 系统要求

- macOS 26.0 (Tahoe) 或更高版本
- Xcode 26+
- 麦克风权限
- 辅助功能权限（用于通过粘贴注入文字）

## 🚀 快速开始

### 构建与运行

```bash
# 克隆仓库
git clone https://github.com/BubblePtr/Voily.git
cd Voily

# 构建
make build

# 运行
make run
```

### 安装到 ~/Applications

```bash
make install
```

### 配置

首次启动时，Voily 会请求**麦克风**和**辅助功能**权限。然后打开设置进行配置：

1. **ASR 提供方** — 选择语音识别引擎：
   - **SenseVoice Small**（本地）— 需下载 ONNX 模型，无需 API Key。
- **豆包流式语音识别**（云端）— 需配置 WebSocket URL、App ID、Token 和 Resource ID。
   - **Qwen ASR**（云端）— 需配置 API Key，已预设默认端点和模型。

2. **文本润色**（可选）— 开启 LLM 后处理并配置提供方（DeepSeek / 阿里云百炼 / 火山引擎 / MiniMax / Kimi / 智谱）。

3. **听写技能** — 开关处理技能，如去语气词、更正式、整理成有序列表。

4. **术语表** — 添加自定义术语或启用内置预设，提升专业词汇识别。

## 🎯 使用方式

| 操作 | 手势 |
|---|---|
| 开始听写 | 按住 **Fn** 键 |
| 完成并粘贴 | 松开 **Fn** 键 |
| 快速翻译（中 → 英） | 双击 **Fn** 键 |

浮窗实时显示状态：
- 🎙️ **录音中** — 波形动画 + 实时部分文字
- ⏳ **转写中** — 最终识别进行中
- ✨ **润色中** — LLM 后处理
- 📋 **注入中** — 粘贴结果到光标

## 🏗️ 项目结构

```
Sources/Voily/
├── App/                    # 应用入口、代理、Fn 键监听
├── Configuration/          # 设置、语言定义
├── Features/
│   ├── Overlay/            # 浮窗转写覆盖层
│   └── Settings/           # 设置窗口
├── Services/
│   ├── Audio/              # ASR 引擎、音频采集、模型管理
│   └── Text/               # 文字注入、LLM 润色
└── Storage/                # 用量统计持久化
```

## 📄 许可证

本项目基于 [Apache License 2.0](LICENSE) 开源。
