import XCTest
@testable import Voily

@MainActor
final class UsageStoreTests: XCTestCase {
    func testEmptyTextIsNotRecorded() {
        let store = makeStore()
        let sessionID = store.recordSession(
            VoiceInputSessionDraft(
                startedAt: date("2026-04-03T09:00:00Z"),
                endedAt: date("2026-04-03T09:00:20Z"),
                languageCode: "zh-Hans",
                recognizedText: "   ",
                finalText: "   ",
                refinementApplied: false,
                asrProvider: ASRProvider.senseVoice.rawValue,
                asrSource: "local",
                recognitionTotalMs: 420,
                recognitionEngineMs: 390,
                recognitionFirstPartialMs: 120,
                recognitionPartialCount: 2
            ),
            now: date("2026-04-03T09:00:20Z")
        )

        XCTAssertNil(sessionID)
        XCTAssertEqual(store.recentSessions.count, 0)
        XCTAssertEqual(store.todaySummary, .empty)
    }

    func testCharacterCountUsesFinalText() {
        let store = makeStore()
        let now = date("2026-04-03T09:00:20Z")

        _ = store.recordSession(
            VoiceInputSessionDraft(
                startedAt: date("2026-04-03T09:00:00Z"),
                endedAt: now,
                languageCode: "zh-Hans",
                recognizedText: "hello",
                finalText: "你好世界",
                refinementApplied: true,
                asrProvider: ASRProvider.senseVoice.rawValue,
                asrSource: "local",
                recognitionTotalMs: 350,
                recognitionEngineMs: 320,
                recognitionFirstPartialMs: 110,
                recognitionPartialCount: 1
            ),
            now: now
        )

        XCTAssertEqual(store.todaySummary.totalCharacters, 4)
        XCTAssertEqual(store.recentSessions.first?.characterCount, 4)
    }

    func testRefinedSessionStoresFinalResultText() {
        let store = makeStore()
        let now = date("2026-04-03T09:00:20Z")

        let sessionID = store.recordSession(
            VoiceInputSessionDraft(
                startedAt: date("2026-04-03T09:00:00Z"),
                endedAt: now,
                languageCode: "zh-Hans",
                recognizedText: "原始识别",
                finalText: "润色后的最终结果",
                refinementApplied: true,
                asrProvider: ASRProvider.senseVoice.rawValue,
                asrSource: "local",
                recognitionTotalMs: 360,
                recognitionEngineMs: 330,
                recognitionFirstPartialMs: 140,
                recognitionPartialCount: 3
            ),
            now: now
        )

        XCTAssertEqual(store.recentSessions.first?.finalText, "润色后的最终结果")
        XCTAssertEqual(sessionID.flatMap(store.copyableText), "润色后的最终结果")
    }

    func testFailedInjectionKeepsHistoryRecord() throws {
        let store = makeStore()
        let now = date("2026-04-03T09:00:20Z")

        let sessionID = try XCTUnwrap(
            store.recordSession(
                VoiceInputSessionDraft(
                    startedAt: date("2026-04-03T09:00:00Z"),
                    endedAt: now,
                    languageCode: "zh-Hans",
                    recognizedText: "识别内容",
                    finalText: "最终文本",
                    refinementApplied: false,
                    asrProvider: ASRProvider.senseVoice.rawValue,
                    asrSource: "local",
                    recognitionTotalMs: 410,
                    recognitionEngineMs: 380,
                    recognitionFirstPartialMs: 125,
                    recognitionPartialCount: 2
                ),
                now: now
            )
        )

        store.markInjectionResult(sessionID: sessionID, succeeded: false, now: now)

        XCTAssertEqual(store.recentSessions.count, 1)
        XCTAssertEqual(store.recentSessions.first?.injectionSucceeded, false)
        XCTAssertEqual(store.copyableText(for: sessionID), "最终文本")
    }

    func testDailySummariesAggregateCorrectly() {
        let store = makeStore()
        let now = date("2026-04-03T09:00:20Z")

        let sessions = [
            (
                start: date("2026-04-03T09:00:00Z"),
                end: date("2026-04-03T09:00:20Z"),
                finalText: "你好",
                now: now
            ),
            (
                start: date("2026-04-03T12:00:00Z"),
                end: date("2026-04-03T12:00:45Z"),
                finalText: "这是第二条",
                now: now
            ),
            (
                start: date("2026-04-02T08:00:00Z"),
                end: date("2026-04-02T08:01:00Z"),
                finalText: "昨天的记录",
                now: now
            ),
        ]

        for session in sessions {
            _ = store.recordSession(
                VoiceInputSessionDraft(
                    startedAt: session.start,
                    endedAt: session.end,
                    languageCode: "zh-Hans",
                    recognizedText: session.finalText,
                    finalText: session.finalText,
                    refinementApplied: false,
                    asrProvider: ASRProvider.senseVoice.rawValue,
                    asrSource: "local",
                    recognitionTotalMs: 500,
                    recognitionEngineMs: 450,
                    recognitionFirstPartialMs: 150,
                    recognitionPartialCount: 2
                ),
                now: session.now
            )
        }

        let summary = store.fetchTodaySummary(now: now)
        XCTAssertEqual(summary.totalDurationMs, 65000)
        XCTAssertEqual(summary.totalCharacters, 7)
        XCTAssertEqual(summary.sessionCount, 2)

        let range = DateInterval(start: date("2026-04-01T00:00:00Z"), end: date("2026-04-04T00:00:00Z"))
        let daily = store.fetchDailySummaries(range: range)

        XCTAssertEqual(daily.count, 2)
        XCTAssertEqual(daily.last?.totalDurationMs, 65000)
        XCTAssertEqual(daily.last?.totalCharacters, 7)
    }

    func testTodayASRSummaryAggregatesCorrectly() {
        let store = makeStore()
        let now = date("2026-04-03T09:00:20Z")

        _ = store.recordSession(
            VoiceInputSessionDraft(
                startedAt: date("2026-04-03T09:00:00Z"),
                endedAt: date("2026-04-03T09:00:10Z"),
                languageCode: "zh-Hans",
                recognizedText: "你好",
                finalText: "你好",
                refinementApplied: false,
                asrProvider: ASRProvider.senseVoice.rawValue,
                asrSource: "local",
                recognitionTotalMs: 420,
                recognitionEngineMs: 390,
                recognitionFirstPartialMs: 120,
                recognitionPartialCount: 2
            ),
            now: now
        )

        _ = store.recordSession(
            VoiceInputSessionDraft(
                startedAt: date("2026-04-03T09:01:00Z"),
                endedAt: date("2026-04-03T09:01:08Z"),
                languageCode: "zh-Hans",
                recognizedText: "hello",
                finalText: "hello",
                refinementApplied: false,
                asrProvider: ASRProvider.qwenASR.rawValue,
                asrSource: "system-speech",
                recognitionTotalMs: 810,
                recognitionEngineMs: 790,
                recognitionFirstPartialMs: nil,
                recognitionPartialCount: 0
            ),
            now: now
        )

        let summary = store.fetchTodayASRSummary(now: now)
        XCTAssertEqual(summary.averageFirstPartialMs, 120)
        XCTAssertEqual(summary.averageRecognitionMs, 615)
        XCTAssertEqual(summary.partialCount, 2)
        XCTAssertEqual(summary.localSessionCount, 1)
        XCTAssertEqual(summary.sessionCount, 2)
    }

    private func makeStore() -> UsageStore {
        UsageStore(databasePath: ":memory:", calendar: utcCalendar)
    }

    private func date(_ value: String) -> Date {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: value)!
    }

    private var utcCalendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar
    }
}

@MainActor
final class AppSettingsGlossaryTests: XCTestCase {
    func testLegacyGlossaryEntriesMigrateToStructuredCustomTerms() {
        let defaults = makeDefaults()
        defaults.set("OpenAI\n JSON \n\nOpenAI\nVoily", forKey: "glossaryEntries")

        let settings = AppSettings(defaults: defaults)

        XCTAssertEqual(settings.enabledGlossaryPresetIDs, [])
        XCTAssertEqual(settings.customGlossaryTerms, ["OpenAI", "JSON", "Voily"])
        XCTAssertEqual(settings.glossaryEntries, "OpenAI\nJSON\nVoily")
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
}

@MainActor
final class LLMRefinementServiceTests: XCTestCase {
    func testSystemPromptIncludesGlossarySectionsWhenAvailable() {
        let settings = AppSettings(defaults: makeDefaults())
        settings.setGlossaryState(
            enabledPresetIDs: [.internetDevelopment],
            customTerms: ["Voily", "DeepSeek"]
        )

        let prompt = LLMRefinementService.systemPrompt(
            for: TextProcessingRequest(
                text: "测试 JSON 和 Python",
                languageCode: "zh-Hans",
                mode: .dictation(skills: [])
            ),
            glossarySections: settings.effectiveGlossarySections
        )

        XCTAssertTrue(prompt.contains("词库参考"))
        XCTAssertTrue(prompt.contains("自定义词条"))
        XCTAssertTrue(prompt.contains("互联网-开发"))
        XCTAssertTrue(prompt.contains("Voily"))
        XCTAssertTrue(prompt.contains("OpenAI"))
    }

    func testSystemPromptOmitsGlossarySectionWhenNoGlossaryItemsExist() {
        let prompt = LLMRefinementService.systemPrompt(
            for: TextProcessingRequest(
                text: "测试 JSON 和 Python",
                languageCode: "zh-Hans",
                mode: .dictation(skills: [])
            ),
            glossarySections: []
        )

        XCTAssertFalse(prompt.contains("词库参考"))
        XCTAssertFalse(prompt.contains("自定义词条"))
        XCTAssertFalse(prompt.contains("互联网-开发"))
        XCTAssertFalse(prompt.contains("仅在启用下列技能时"))
    }

    func testDictationPromptIncludesSkillsInStableExecutionOrder() throws {
        let prompt = LLMRefinementService.systemPrompt(
            for: TextProcessingRequest(
                text: "嗯这个就是我们先做登录，然后那个支付后面再补",
                languageCode: "zh-Hans",
                mode: .dictation(skills: [.orderedList, .removeFillers, .formalize, .removeFillers])
            ),
            glossarySections: []
        )

        let removeRange = try XCTUnwrap(prompt.range(of: "第 2 步：去掉明显语气词"))
        let formalizeRange = try XCTUnwrap(prompt.range(of: "第 3 步：把口述表达整理为中性、简洁、正式的书面语"))
        let orderedListRange = try XCTUnwrap(prompt.range(of: "第 4 步：如果内容中存在 2 个及以上清晰的事项、观点或步骤"))

        XCTAssertLessThan(removeRange.lowerBound, formalizeRange.lowerBound)
        XCTAssertLessThan(formalizeRange.lowerBound, orderedListRange.lowerBound)
        XCTAssertTrue(prompt.contains("如果只有一个清晰事项或不适合拆项，则保持段落文本"))
        XCTAssertFalse(prompt.contains("第 5 步"))
    }

    func testTranslationPromptForcesEnglishOnlyOutput() {
        let prompt = LLMRefinementService.systemPrompt(
            for: TextProcessingRequest(
                text: "把这个版本今天发给客户",
                languageCode: "zh-CN",
                mode: .translateZhToEn(style: .natural)
            ),
            glossarySections: [GlossarySection(title: "自定义词条", items: ["Voily"])]
        )

        XCTAssertTrue(prompt.contains("只输出英文最终结果"))
        XCTAssertTrue(prompt.contains("不要输出中文"))
        XCTAssertFalse(prompt.contains("词库参考"))
        XCTAssertFalse(prompt.contains("Voily"))
        XCTAssertFalse(prompt.contains("第 1 步：基础纠错"))
    }

    private func makeDefaults() -> UserDefaults {
        let suiteName = "Voily.LLMRefinementServiceTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        return defaults
    }
}
