// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "VoilyLogic",
    platforms: [
        .macOS(.v14),
    ],
    products: [
        .library(name: "VoilyLogic", targets: ["VoilyLogic"]),
    ],
    targets: [
        .target(
            name: "VoilyLogic",
            path: "Sources/Voily",
            exclude: [
                "App",
                "Features",
                "Resources",
                "Services/Media",
                "Services/Text/TextInjectionService.swift",
                "Services/Audio/ASRCaptureSession.swift",
                "Services/Audio/ASRConnectionTester.swift",
                "Services/Audio/AudioCaptureService.swift",
                "Services/Audio/DoubaoStreamingASRService.swift",
                "Services/Audio/ManagedASRModelStore.swift",
                "Services/Audio/QwenRealtimeASRService.swift",
                "Services/Audio/SenseVoiceResidentService.swift",
                "Services/Audio/StepRealtimeASRService.swift",
            ],
            sources: [
                "Configuration/AppSettings.swift",
                "Configuration/SupportedLanguage.swift",
                "Services/Audio/FunASRRealtimeService.swift",
                "Services/Audio/FunASRVocabularyService.swift",
                "Services/Audio/TranscriptLogic.swift",
                "Services/Text/LLMRefinementService.swift",
                "Storage/UsageStore.swift",
                "Support/DebugLog.swift",
            ],
            linkerSettings: [
                .linkedLibrary("sqlite3"),
            ]
        ),
        .testTarget(
            name: "VoilyLogicTests",
            dependencies: ["VoilyLogic"],
            path: "Tests/VoilyLogicTests",
            sources: [
                "Audio/FunASRRealtimeServiceTests.swift",
                "Audio/FunASRVocabularyServiceTests.swift",
                "Audio/TranscriptLogicTests.swift",
                "Configuration/AppSettingsTests.swift",
                "Configuration/AppSettingsPersistenceIntegrationTests.swift",
                "Services/LLMRefinementServiceTests.swift",
                "Storage/UsageStoreTests.swift",
            ]
        ),
    ]
)
