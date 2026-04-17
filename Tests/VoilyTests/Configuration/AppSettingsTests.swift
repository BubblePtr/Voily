import XCTest
@testable import Voily

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

        settings.selectedASRProvider = .qwenASR
        settings.setASRConfig(
            ASRProviderConfig(
                executablePath: "",
                modelPath: "",
                additionalArguments: "",
                baseURL: "wss://dashscope.aliyuncs.com/api-ws/v1/realtime",
                apiKey: "dashscope-key",
                model: "qwen3-asr-flash-realtime"
            ),
            for: .qwenASR
        )
        settings.selectedTextProvider = .dashScope
        settings.setTextRefinementConfig(
            TextRefinementProviderConfig(
                baseURL: "https://dashscope.aliyuncs.com/compatible-mode/v1",
                apiKey: "dashscope-text-key",
                model: "qwen-plus"
            ),
            for: .dashScope
        )

        let reloaded = AppSettings(defaults: defaults)

        XCTAssertEqual(reloaded.selectedASRProvider, .qwenASR)
        XCTAssertEqual(reloaded.selectedTextProvider, .dashScope)
        XCTAssertEqual(reloaded.asrConfig(for: .qwenASR).apiKey, "dashscope-key")
        XCTAssertEqual(reloaded.textRefinementConfig(for: .dashScope).apiKey, "dashscope-text-key")
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
}

final class TriggerKeyMonitorCoreTests: XCTestCase {
    func testSingleTapStartsDictationOnRelease() {
        var core = TriggerKeyMonitorCore(longPressThreshold: 0.8)

        XCTAssertEqual(core.handleTriggerPressChange(true, at: 0.00), [])
        XCTAssertEqual(core.handleTriggerPressChange(false, at: 0.05), [.startDictation])
        XCTAssertFalse(core.stateMachine.hasPendingGesture)
    }

    func testTapWhileDictatingFinishesDictation() {
        var core = TriggerKeyMonitorCore(longPressThreshold: 0.8)
        core.setSessionMode(.dictating)

        XCTAssertEqual(core.handleTriggerPressChange(true, at: 1.00), [])
        XCTAssertEqual(core.handleTriggerPressChange(false, at: 1.05), [.finishDictation])
    }

    func testLongPressStartsQuickTranslation() {
        var core = TriggerKeyMonitorCore(longPressThreshold: 0.8)

        XCTAssertEqual(core.handleTriggerPressChange(true, at: 0.00), [])
        XCTAssertEqual(core.handleLongPressTimer(at: 0.81), [.startQuickTranslation])
    }

    func testLongPressReleaseDoesNotTriggerExtraAction() {
        var core = TriggerKeyMonitorCore(longPressThreshold: 0.8)

        XCTAssertEqual(core.handleTriggerPressChange(true, at: 0.00), [])
        XCTAssertEqual(core.handleLongPressTimer(at: 0.81), [.startQuickTranslation])
        XCTAssertEqual(core.handleTriggerPressChange(false, at: 0.90), [])
    }

    func testLongPressDuringDictationIsIgnored() {
        var core = TriggerKeyMonitorCore(longPressThreshold: 0.8)
        core.setSessionMode(.dictating)

        XCTAssertEqual(core.handleTriggerPressChange(true, at: 0.00), [])
        XCTAssertEqual(core.handleLongPressTimer(at: 0.81), [])
        XCTAssertEqual(core.handleTriggerPressChange(false, at: 0.90), [])
    }

    func testChordedRightCommandPressDoesNotTriggerActions() {
        var core = TriggerKeyMonitorCore(longPressThreshold: 0.8)

        XCTAssertEqual(core.handleTriggerPressChange(true, at: 0.00), [])
        core.handleNonTriggerKeyDown()
        XCTAssertEqual(core.handleTriggerPressChange(false, at: 0.05), [])
        XCTAssertEqual(core.handleLongPressTimer(at: 0.90), [])
    }

    func testTriggerIgnoredWhileTranslationActive() {
        var core = TriggerKeyMonitorCore(longPressThreshold: 0.8)
        core.setSessionMode(.translating)

        XCTAssertEqual(core.handleTriggerPressChange(true, at: 1.00), [])
        XCTAssertEqual(core.handleLongPressTimer(at: 1.90), [])
        XCTAssertEqual(core.handleTriggerPressChange(false, at: 2.00), [])
    }

    func testChordDuringDictationDoesNotFinishRecording() {
        var core = TriggerKeyMonitorCore(longPressThreshold: 0.8)
        core.setSessionMode(.dictating)

        XCTAssertEqual(core.handleTriggerPressChange(true, at: 1.00), [])
        core.handleNonTriggerKeyDown()
        XCTAssertEqual(core.handleTriggerPressChange(false, at: 1.05), [])
        XCTAssertEqual(core.sessionMode, .dictating)
    }

    func testResetClearsPendingGestureState() {
        var core = TriggerKeyMonitorCore(longPressThreshold: 0.8)

        XCTAssertEqual(core.handleTriggerPressChange(true, at: 0.00), [])
        core.reset()

        XCTAssertEqual(core.handleLongPressTimer(at: 0.90), [])
        XCTAssertFalse(core.stateMachine.hasPendingGesture)
        XCTAssertEqual(core.sessionMode, .idle)
    }
}
