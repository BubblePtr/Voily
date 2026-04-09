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
                model: "qwen3-asr-flash-realtime"
            ),
            for: .qwenASR
        )
        first.selectedTextProvider = .dashScope
        first.textRefinementEnabled = true
        first.dockIconVisible = false
        first.setEnabledDictationSkills([.removeFillers, .formalize])
        first.setTextRefinementConfig(
            TextRefinementProviderConfig(
                baseURL: "https://dashscope.aliyuncs.com/compatible-mode/v1",
                apiKey: "dashscope-text-key",
                model: "qwen-plus"
            ),
            for: .dashScope
        )

        let second = AppSettings(defaults: defaults)

        XCTAssertEqual(second.selectedLanguage, .english)
        XCTAssertEqual(second.enabledGlossaryPresetIDs, [.internetDevelopment])
        XCTAssertEqual(second.customGlossaryTerms, ["Voily", "DeepSeek"])
        XCTAssertEqual(second.selectedASRProvider, .qwenASR)
        XCTAssertEqual(second.asrConfig(for: .qwenASR).apiKey, "dashscope-key")
        XCTAssertEqual(second.selectedTextProvider, .dashScope)
        XCTAssertTrue(second.textRefinementEnabled)
        XCTAssertFalse(second.dockIconVisible)
        XCTAssertEqual(second.enabledDictationSkills, [.removeFillers, .formalize])
        XCTAssertEqual(second.textRefinementConfig(for: .dashScope).apiKey, "dashscope-text-key")
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

        let data = try XCTUnwrap(defaults.data(forKey: "modelSettingsSnapshot"))
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let asrConfigs = try XCTUnwrap(object["asrConfigsByProvider"] as? [String: Any])
        let textConfigs = try XCTUnwrap(object["textConfigsByProvider"] as? [String: Any])

        XCTAssertNotNil(asrConfigs["qwenASR"])
        XCTAssertNotNil(textConfigs["dashScope"])
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
