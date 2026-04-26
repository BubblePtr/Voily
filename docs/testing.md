# Voily 测试指南

Voily 当前有两套测试入口：一套是 SwiftPM 纯逻辑测试，一套是 Xcode app/unit 测试。两者覆盖的构建边界不同，日常提交前建议跑完整 `make test`。

其中 `VoilyLogicTests` 的核心价值是提供 sandbox-safe 的验证入口：它只构建纯 SwiftPM 逻辑模块，不依赖完整 macOS app bundle、系统权限、AppKit 宿主进程或本机签名状态，适合在受限 workspace、CI 预检和 agent 安全联调环境中快速验证业务逻辑。

## 快速命令

```bash
# 跑完整测试套件：SwiftPM 逻辑测试 + Xcode app/unit 测试
make test

# 只跑 SwiftPM 纯逻辑测试
make test-logic

# 只跑 Xcode app/unit 测试
make test-app
```

## SwiftPM 纯逻辑测试

命令：

```bash
make test-logic
```

等价于：

```bash
swift test
```

这套测试由 `Package.swift` 声明，测试目录是 `Tests/VoilyLogicTests`，目标是在 sandbox-safe 的边界内快速验证不依赖完整 macOS app bundle 的核心逻辑。它覆盖 `VoilyLogic` 模块中的设置持久化、转写文本累积、Fun-ASR 消息构造、术语表同步计划、LLM prompt 组装和用量统计等逻辑。

适合在修改这些文件时优先运行：

- `Sources/Voily/Configuration/`
- `Sources/Voily/Services/Audio/FunASRRealtimeService.swift`
- `Sources/Voily/Services/Audio/FunASRVocabularyService.swift`
- `Sources/Voily/Services/Audio/TranscriptLogic.swift`
- `Sources/Voily/Services/Text/LLMRefinementService.swift`
- `Sources/Voily/Storage/`

这类测试不应引入麦克风、辅助功能、菜单栏、窗口生命周期、代码签名或真实 provider 网络连接等依赖；一旦测试需要这些边界，就应该放到 `VoilyTests` 或更高层的集成验证里。

## Xcode app/unit 测试

命令：

```bash
make test-app
```

等价于：

```bash
xcodebuild -project Voily.xcodeproj -scheme Voily -configuration Debug -derivedDataPath .xcodebuild test
```

这套测试由 `Voily.xcodeproj` 的 `Voily` scheme 驱动，测试 bundle 是 `VoilyTests`，测试目录是 `Tests/VoilyTests`。它会构建完整 `Voily.app`，再运行依赖 app target 的 unit tests。

适合在修改这些文件时运行：

- `Sources/Voily/App/`
- `Sources/Voily/Services/Audio/ASRCaptureSession.swift`
- `Sources/Voily/Services/Audio/ASRConnectionTester.swift`
- `Sources/Voily/Services/Audio/AudioCaptureService.swift`
- `Sources/Voily/Services/Audio/DoubaoStreamingASRService.swift`
- `Sources/Voily/Services/Media/SystemMediaPlaybackService.swift`
- app resource、brand icon、trigger key 相关代码

## 枚举测试用例

SwiftPM 逻辑测试：

```bash
swift test list
```

Xcode app/unit 测试：

```bash
xcodebuild test \
  -project Voily.xcodeproj \
  -scheme Voily \
  -configuration Debug \
  -derivedDataPath .xcodebuild \
  -enumerate-tests \
  -test-enumeration-style flat \
  -test-enumeration-format text \
  -only-testing:VoilyTests
```

当前 Xcode 已不支持 `xcodebuild -dry-run`，需要用 `-enumerate-tests` 枚举测试。

## 维护约定

- 新的纯逻辑测试优先放在 `Tests/VoilyLogicTests`，并在 `Package.swift` 的 `VoilyLogicTests` target 中登记。
- 需要完整 app target、AppKit/SwiftUI 集成、资源文件或系统服务边界的测试放在 `Tests/VoilyTests`，并接入 `Voily.xcodeproj` 的 `VoilyTests` target。
- `make test` 是提交前的完整测试入口；排查问题时可以先用 `make test-logic` 或 `make test-app` 缩小范围。
