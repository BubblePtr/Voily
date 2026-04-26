import XCTest
@testable import VoilyLogic

@MainActor
final class AppSettingsTests: XCTestCase {
    func testLegacyGlossaryEntriesMigrateToStructuredCustomTerms() {
        let defaults = makeDefaults()
        defaults.set("OpenAI\n JSON \n\nOpenAI\nVoily", forKey: "glossaryEntries")

        let settings = AppSettings(defaults: defaults)

        XCTAssertEqual(settings.enabledGlossaryPresetIDs, [])
        XCTAssertEqual(settings.customGlossaryTerms, ["OpenAI", "JSON", "Voily"])
        XCTAssertEqual(settings.glossaryEntries, "OpenAI\nJSON\nVoily")
    }

    func testPreferredMicrophoneUIDDefaultsToSystemDefault() {
        let settings = AppSettings(defaults: makeDefaults())

        XCTAssertNil(settings.preferredMicrophoneUID)
    }

    func testEffectiveGlossaryItemsDeduplicateAcrossCustomTermsAndPresets() {
        let settings = AppSettings(defaults: makeDefaults())
        settings.setGlossaryState(
            enabledPresetIDs: [.internetDevelopment, .medical],
            customTerms: ["Voily", "Python", "CT", "Voily"]
        )

        XCTAssertEqual(Array(settings.effectiveGlossaryItems.prefix(3)), ["Voily", "Python", "CT"])
        XCTAssertEqual(settings.effectiveGlossaryItems.filter { $0 == "Python" }.count, 1)
        XCTAssertEqual(settings.effectiveGlossaryItems.filter { $0 == "CT" }.count, 1)
        XCTAssertTrue(settings.effectiveGlossaryItems.contains("OpenAI"))
        XCTAssertTrue(settings.effectiveGlossaryItems.contains("病历"))
    }

    func testEnabledPresetsExposePresetTerms() {
        let settings = AppSettings(defaults: makeDefaults())
        settings.setGlossaryState(
            enabledPresetIDs: [.internetDevelopment, .medical],
            customTerms: []
        )

        XCTAssertEqual(
            settings.effectiveGlossarySections.map(\.title),
            ["互联网-开发", "医疗"]
        )
        XCTAssertTrue(settings.effectiveGlossaryItems.contains("SwiftUI"))
        XCTAssertTrue(settings.effectiveGlossaryItems.contains("门诊"))
    }

    func testLegacyModelSnapshotWithoutDictationSkillsMigratesToEmptySkillList() throws {
        let defaults = makeDefaults()
        defaults.set(try legacyModelSnapshotData(), forKey: "modelSettingsSnapshot")

        let settings = AppSettings(defaults: defaults)

        XCTAssertEqual(settings.selectedASRProvider, .senseVoice)
        XCTAssertEqual(settings.selectedTextProvider, .deepSeek)
        XCTAssertEqual(settings.enabledDictationSkills, [])
    }

    func testEnabledDictationSkillsPersistInStableOrder() {
        let defaults = makeDefaults()
        let settings = AppSettings(defaults: defaults)

        settings.setEnabledDictationSkills([.orderedList, .formalize, .removeFillers, .formalize])

        XCTAssertEqual(settings.enabledDictationSkills, [.removeFillers, .formalize, .orderedList])

        let reloaded = AppSettings(defaults: defaults)
        XCTAssertEqual(reloaded.enabledDictationSkills, [.removeFillers, .formalize, .orderedList])
    }

    func testSelectedLanguagePersistsAcrossReload() {
        let defaults = makeDefaults()
        let settings = AppSettings(defaults: defaults)

        settings.selectedLanguage = .english

        let reloaded = AppSettings(defaults: defaults)
        XCTAssertEqual(reloaded.selectedLanguage, .english)
    }

    func testLegacyModelSnapshotWithoutTriggerKeyDefaultsToFn() throws {
        let defaults = makeDefaults()
        defaults.set(try legacyModelSnapshotData(), forKey: "modelSettingsSnapshot")

        let settings = AppSettings(defaults: defaults)

        XCTAssertEqual(settings.triggerKey, .fn)
    }

    func testLegacyModelSnapshotWithoutMediaInterruptionDefaultsToDisabled() throws {
        let defaults = makeDefaults()
        defaults.set(try legacyModelSnapshotData(), forKey: "modelSettingsSnapshot")

        let settings = AppSettings(defaults: defaults)

        XCTAssertFalse(settings.interruptSystemMediaPlayback)
    }

    func testTriggerKeyPersistsAcrossReload() {
        let defaults = makeDefaults()
        let settings = AppSettings(defaults: defaults)

        settings.triggerKey = .rightCommand

        let reloaded = AppSettings(defaults: defaults)
        XCTAssertEqual(reloaded.triggerKey, .rightCommand)
    }

    func testMediaInterruptionPreferencePersistsAcrossReload() {
        let defaults = makeDefaults()
        let settings = AppSettings(defaults: defaults)

        settings.interruptSystemMediaPlayback = true

        let reloaded = AppSettings(defaults: defaults)
        XCTAssertTrue(reloaded.interruptSystemMediaPlayback)
    }

    func testDockIconVisibilityDefaultsToVisibleForLegacySnapshots() throws {
        let defaults = makeDefaults()
        defaults.set(try legacyModelSnapshotData(), forKey: "modelSettingsSnapshot")

        let settings = AppSettings(defaults: defaults)

        XCTAssertTrue(settings.dockIconVisible)
    }

    func testLegacyModelSnapshotWithoutPreferredMicrophoneUIDDefaultsToSystemDefault() throws {
        let defaults = makeDefaults()
        defaults.set(try legacyModelSnapshotData(), forKey: "modelSettingsSnapshot")

        let settings = AppSettings(defaults: defaults)

        XCTAssertNil(settings.preferredMicrophoneUID)
    }

    func testDockIconVisibilityPersistsAcrossReload() {
        let defaults = makeDefaults()
        let settings = AppSettings(defaults: defaults)

        settings.dockIconVisible = false

        let reloaded = AppSettings(defaults: defaults)
        XCTAssertFalse(reloaded.dockIconVisible)
    }

    func testPreferredMicrophoneUIDPersistsAcrossReload() {
        let defaults = makeDefaults()
        let settings = AppSettings(defaults: defaults)

        settings.preferredMicrophoneUID = "usb-mic"

        let reloaded = AppSettings(defaults: defaults)
        XCTAssertEqual(reloaded.preferredMicrophoneUID, "usb-mic")
    }

    func testGlossaryStatePersistsAcrossReload() {
        let defaults = makeDefaults()
        let settings = AppSettings(defaults: defaults)

        settings.setGlossaryState(
            enabledPresetIDs: [.internetDevelopment, .medical],
            customTerms: ["Voily", "Qwen"]
        )

        let reloaded = AppSettings(defaults: defaults)

        XCTAssertEqual(reloaded.enabledGlossaryPresetIDs, [.internetDevelopment, .medical])
        XCTAssertEqual(reloaded.customGlossaryTerms, ["Voily", "Qwen"])
        XCTAssertTrue(reloaded.effectiveGlossaryItems.contains("SwiftUI"))
        XCTAssertTrue(reloaded.effectiveGlossaryItems.contains("门诊"))
    }

    func testModelProviderSelectionsAndConfigsPersistAcrossReload() {
        let defaults = makeDefaults()
        let settings = AppSettings(defaults: defaults)

        settings.selectedASRProvider = .doubaoStreaming
        settings.setASRConfig(
            ASRProviderConfig(
                executablePath: "",
                modelPath: "",
                additionalArguments: "",
                baseURL: "wss://openspeech.bytedance.com/api/v3/sauc/bigmodel_async",
                apiKey: "volc-token",
                model: "volc.seedasr.sauc.duration",
                appID: "doubao-app-id"
            ),
            for: .doubaoStreaming
        )
        settings.selectedTextProvider = .kimi
        settings.setTextRefinementConfig(
            TextRefinementProviderConfig(
                baseURL: "https://api.moonshot.cn/v1",
                apiKey: "moonshot-key",
                model: "kimi-k2.5"
            ),
            for: .kimi
        )

        let reloaded = AppSettings(defaults: defaults)

        XCTAssertEqual(reloaded.selectedASRProvider, .doubaoStreaming)
        XCTAssertEqual(reloaded.selectedTextProvider, .kimi)
        XCTAssertEqual(reloaded.asrConfig(for: .doubaoStreaming).apiKey, "volc-token")
        XCTAssertEqual(reloaded.asrConfig(for: .doubaoStreaming).appID, "doubao-app-id")
        XCTAssertEqual(reloaded.textRefinementConfig(for: .kimi).apiKey, "moonshot-key")
    }

    func testArrayEncodedProviderSnapshotMigratesAcrossReload() throws {
        let defaults = makeDefaults()
        defaults.set(try arrayEncodedModelSnapshotData(), forKey: "modelSettingsSnapshot")

        let settings = AppSettings(defaults: defaults)

        XCTAssertEqual(settings.selectedASRProvider, .qwenASR)
        XCTAssertEqual(settings.selectedTextProvider, .dashScope)
        XCTAssertEqual(settings.asrConfig(for: .qwenASR).apiKey, "dashscope-old-key")
        XCTAssertEqual(settings.textRefinementConfig(for: .dashScope).apiKey, "dashscope-text-old-key")

        let reloaded = AppSettings(defaults: defaults)

        XCTAssertEqual(reloaded.selectedASRProvider, .qwenASR)
        XCTAssertEqual(reloaded.selectedTextProvider, .dashScope)
        XCTAssertEqual(reloaded.asrConfig(for: .qwenASR).model, "qwen3-asr-flash-realtime")
        XCTAssertEqual(reloaded.textRefinementConfig(for: .dashScope).model, "qwen-plus")
    }

    func testArrayEncodedSnapshotBackfillsFunASRDefaultsForUpgradedUsers() throws {
        let defaults = makeDefaults()
        defaults.set(try arrayEncodedModelSnapshotData(), forKey: "modelSettingsSnapshot")

        let settings = AppSettings(defaults: defaults)

        XCTAssertEqual(settings.asrConfig(for: .funASR).baseURL, "wss://dashscope.aliyuncs.com/api-ws/v1/inference")
        XCTAssertEqual(settings.asrConfig(for: .funASR).model, "fun-asr-realtime")

        let reloaded = AppSettings(defaults: defaults)

        XCTAssertEqual(reloaded.asrConfig(for: .funASR).baseURL, "wss://dashscope.aliyuncs.com/api-ws/v1/inference")
        XCTAssertEqual(reloaded.asrConfig(for: .funASR).model, "fun-asr-realtime")
    }

    func testLegacyASRConfigWithoutAppIDMigratesWithEmptyAppID() throws {
        let defaults = makeDefaults()
        defaults.set(try legacyDoubaoSnapshotData(), forKey: "modelSettingsSnapshot")

        let settings = AppSettings(defaults: defaults)

        XCTAssertEqual(settings.selectedASRProvider, .doubaoStreaming)
        XCTAssertEqual(settings.asrConfig(for: .doubaoStreaming).baseURL, "wss://openspeech.bytedance.com/api/v2/asr")
        XCTAssertEqual(settings.asrConfig(for: .doubaoStreaming).apiKey, "legacy-volc-token")
        XCTAssertEqual(settings.asrConfig(for: .doubaoStreaming).model, "volcengine_streaming_common")
        XCTAssertEqual(settings.asrConfig(for: .doubaoStreaming).appID, "")
    }

    func testStepFunASRConfigPersistsAcrossReload() {
        let defaults = makeDefaults()
        let settings = AppSettings(defaults: defaults)

        settings.selectedASRProvider = .stepfunASR
        settings.setASRConfig(
            ASRProviderConfig(
                executablePath: "",
                modelPath: "",
                additionalArguments: "",
                baseURL: "wss://api.stepfun.com/v1/realtime/asr/stream",
                apiKey: "step-key",
                model: "step-asr-1.1-stream",
                appID: ""
            ),
            for: .stepfunASR
        )

        let reloaded = AppSettings(defaults: defaults)

        XCTAssertEqual(reloaded.selectedASRProvider, .stepfunASR)
        XCTAssertEqual(reloaded.asrConfig(for: .stepfunASR).baseURL, "wss://api.stepfun.com/v1/realtime/asr/stream")
        XCTAssertEqual(reloaded.asrConfig(for: .stepfunASR).apiKey, "step-key")
        XCTAssertEqual(reloaded.asrConfig(for: .stepfunASR).model, "step-asr-1.1-stream")
    }

    func testFunASRConfigPersistsAcrossReload() {
        let defaults = makeDefaults()
        let settings = AppSettings(defaults: defaults)

        settings.selectedASRProvider = .funASR
        settings.setASRConfig(
            ASRProviderConfig(
                executablePath: "",
                modelPath: "",
                additionalArguments: "",
                baseURL: "wss://dashscope.aliyuncs.com/api-ws/v1/inference",
                apiKey: "dashscope-key",
                model: "fun-asr-realtime",
                appID: "",
                vocabularyID: "vocab-voily-123",
                vocabularyTargetModel: "fun-asr-realtime",
                vocabularyRevision: "rev-123"
            ),
            for: .funASR
        )

        let reloaded = AppSettings(defaults: defaults)

        XCTAssertEqual(reloaded.selectedASRProvider, .funASR)
        XCTAssertEqual(reloaded.asrConfig(for: .funASR).baseURL, "wss://dashscope.aliyuncs.com/api-ws/v1/inference")
        XCTAssertEqual(reloaded.asrConfig(for: .funASR).apiKey, "dashscope-key")
        XCTAssertEqual(reloaded.asrConfig(for: .funASR).model, "fun-asr-realtime")
        XCTAssertEqual(reloaded.asrConfig(for: .funASR).vocabularyID, "vocab-voily-123")
        XCTAssertEqual(reloaded.asrConfig(for: .funASR).vocabularyTargetModel, "fun-asr-realtime")
        XCTAssertEqual(reloaded.asrConfig(for: .funASR).vocabularyRevision, "rev-123")
    }

    private func makeDefaults() -> UserDefaults {
        let suiteName = "Voily.AppSettingsTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        return defaults
    }

    private func legacyModelSnapshotData() throws -> Data {
        let json = """
        {
          "selectedASRProvider": "whisperCpp",
          "selectedTextProvider": "deepSeek",
          "textRefinementEnabled": true,
          "asrConfigsByProvider": {
            "whisperCpp": {
              "executablePath": "",
              "modelPath": "",
              "additionalArguments": "",
              "baseURL": "",
              "apiKey": "",
              "model": ""
            }
          },
          "textConfigsByProvider": {
            "deepSeek": {
              "baseURL": "https://api.deepseek.com/v1",
              "apiKey": "sk-legacy",
              "model": "deepseek-chat"
            }
          }
        }
        """
        return try XCTUnwrap(json.data(using: .utf8))
    }

    private func arrayEncodedModelSnapshotData() throws -> Data {
        let json = """
        {
          "selectedASRProvider": "qwenASR",
          "selectedTextProvider": "dashScope",
          "textRefinementEnabled": true,
          "enabledDictationSkills": ["removeFillers", "orderedList"],
          "asrConfigsByProvider": [
            "qwenASR",
            {
              "executablePath": "",
              "modelPath": "",
              "additionalArguments": "",
              "baseURL": "wss://dashscope.aliyuncs.com/api-ws/v1/realtime",
              "apiKey": "dashscope-old-key",
              "model": "qwen3-asr-flash-realtime"
            },
            "senseVoice",
            {
              "executablePath": "/tmp/sensevoice",
              "modelPath": "/tmp/sensevoice.bin",
              "additionalArguments": "--vad true",
              "baseURL": "",
              "apiKey": "",
              "model": ""
            }
          ],
          "textConfigsByProvider": [
            "dashScope",
            {
              "baseURL": "https://dashscope.aliyuncs.com/compatible-mode/v1",
              "apiKey": "dashscope-text-old-key",
              "model": "qwen-plus"
            }
          ]
        }
        """
        return try XCTUnwrap(json.data(using: .utf8))
    }

    private func legacyDoubaoSnapshotData() throws -> Data {
        let json = """
        {
          "selectedASRProvider": "doubaoStreaming",
          "selectedTextProvider": "deepSeek",
          "textRefinementEnabled": false,
          "asrConfigsByProvider": {
            "doubaoStreaming": {
              "executablePath": "",
              "modelPath": "",
              "additionalArguments": "",
              "baseURL": "wss://openspeech.bytedance.com/api/v2/asr",
              "apiKey": "legacy-volc-token",
              "model": "volcengine_streaming_common"
            }
          },
          "textConfigsByProvider": {
            "deepSeek": {
              "baseURL": "https://api.deepseek.com/v1",
              "apiKey": "sk-legacy",
              "model": "deepseek-chat"
            }
          }
        }
        """
        return try XCTUnwrap(json.data(using: .utf8))
    }
}
