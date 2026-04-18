import Foundation
import XCTest
@testable import Voily

@MainActor
final class AppSettingsPersistenceIntegrationTests: XCTestCase {
    func testAppSettingsRoundTripPreservesMultipleSectionsTogether() {
        let defaults = makeDefaults()
        let first = AppSettings(defaults: defaults)

        first.selectedLanguage = .english
        first.setGlossaryState(
            enabledPresetIDs: [.internetDevelopment],
            customTerms: ["Voily", "DeepSeek"]
        )
        first.selectedASRProvider = .qwenASR
        first.setASRConfig(
            ASRProviderConfig(
                executablePath: "",
                modelPath: "",
                additionalArguments: "",
                baseURL: "wss://dashscope.aliyuncs.com/api-ws/v1/realtime",
                apiKey: "dashscope-key",
                model: "qwen3-asr-flash-realtime",
                appID: ""
            ),
            for: .qwenASR
        )
        first.selectedTextProvider = .zhipu
        first.textRefinementEnabled = true
        first.triggerKey = .rightCommand
        first.interruptSystemMediaPlayback = true
        first.dockIconVisible = false
        first.preferredMicrophoneUID = "usb-mic"
        first.setEnabledDictationSkills([.removeFillers, .formalize])
        first.setTextRefinementConfig(
            TextRefinementProviderConfig(
                baseURL: "https://open.bigmodel.cn/api/paas/v4",
                apiKey: "zhipu-text-key",
                model: "glm-4.7-flash"
            ),
            for: .zhipu
        )

        let second = AppSettings(defaults: defaults)

        XCTAssertEqual(second.selectedLanguage, .english)
        XCTAssertEqual(second.enabledGlossaryPresetIDs, [.internetDevelopment])
        XCTAssertEqual(second.customGlossaryTerms, ["Voily", "DeepSeek"])
        XCTAssertEqual(second.selectedASRProvider, .qwenASR)
        XCTAssertEqual(second.asrConfig(for: .qwenASR).apiKey, "dashscope-key")
        XCTAssertEqual(second.selectedTextProvider, .zhipu)
        XCTAssertTrue(second.textRefinementEnabled)
        XCTAssertEqual(second.triggerKey, .rightCommand)
        XCTAssertTrue(second.interruptSystemMediaPlayback)
        XCTAssertFalse(second.dockIconVisible)
        XCTAssertEqual(second.preferredMicrophoneUID, "usb-mic")
        XCTAssertEqual(second.enabledDictationSkills, [.removeFillers, .formalize])
        XCTAssertEqual(second.textRefinementConfig(for: .zhipu).apiKey, "zhipu-text-key")
    }

    func testPersistedModelSnapshotUsesKeyedProviderMaps() throws {
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
                model: "qwen3-asr-flash-realtime",
                appID: ""
            ),
            for: .qwenASR
        )
        settings.selectedTextProvider = .minimax
        settings.triggerKey = .rightCommand
        settings.interruptSystemMediaPlayback = true
        settings.preferredMicrophoneUID = "usb-mic"
        settings.setTextRefinementConfig(
            TextRefinementProviderConfig(
                baseURL: "https://api.minimax.io/v1",
                apiKey: "minimax-text-key",
                model: "MiniMax-M2.5"
            ),
            for: .minimax
        )

        let data = try XCTUnwrap(defaults.data(forKey: "modelSettingsSnapshot"))
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let asrConfigs = try XCTUnwrap(object["asrConfigsByProvider"] as? [String: Any])
        let textConfigs = try XCTUnwrap(object["textConfigsByProvider"] as? [String: Any])

        XCTAssertNotNil(asrConfigs["qwenASR"])
        XCTAssertNotNil(textConfigs["minimax"])
        XCTAssertEqual(object["triggerKey"] as? String, "rightCommand")
        XCTAssertEqual(object["interruptSystemMediaPlayback"] as? Bool, true)
        XCTAssertEqual(object["preferredMicrophoneUID"] as? String, "usb-mic")
        XCTAssertFalse(object["asrConfigsByProvider"] is [Any])
        XCTAssertFalse(object["textConfigsByProvider"] is [Any])
    }

    private func makeDefaults() -> UserDefaults {
        let suiteName = "Voily.AppSettingsPersistenceIntegrationTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        return defaults
    }
}
