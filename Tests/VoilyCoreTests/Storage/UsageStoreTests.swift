import XCTest
@testable import VoilyCore

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

    func testLifetimeSummaryAggregatesAllRecordedSessions() {
        let store = makeStore()
        let now = date("2026-04-03T09:00:20Z")

        _ = store.recordSession(
            VoiceInputSessionDraft(
                startedAt: date("2026-04-01T09:00:00Z"),
                endedAt: date("2026-04-01T09:01:00Z"),
                languageCode: "zh-Hans",
                recognizedText: "第一条",
                finalText: "第一条",
                refinementApplied: false,
                asrProvider: ASRProvider.senseVoice.rawValue,
                asrSource: "local",
                recognitionTotalMs: 500,
                recognitionEngineMs: 450,
                recognitionFirstPartialMs: 150,
                recognitionPartialCount: 2
            ),
            now: now
        )
        _ = store.recordSession(
            VoiceInputSessionDraft(
                startedAt: date("2026-04-03T09:00:00Z"),
                endedAt: date("2026-04-03T09:00:30Z"),
                languageCode: "zh-Hans",
                recognizedText: "second",
                finalText: "second",
                refinementApplied: false,
                asrProvider: ASRProvider.qwenASR.rawValue,
                asrSource: "cloud-realtime",
                recognitionTotalMs: 620,
                recognitionEngineMs: 590,
                recognitionFirstPartialMs: nil,
                recognitionPartialCount: 0
            ),
            now: now
        )

        XCTAssertEqual(store.lifetimeSummary.totalDurationMs, 90_000)
        XCTAssertEqual(store.lifetimeSummary.totalCharacters, 9)
        XCTAssertEqual(store.lifetimeSummary.sessionCount, 2)
        XCTAssertEqual(store.lifetimeSummary.averageCharactersPerMinute, 6)
        XCTAssertEqual(store.lifetimeSummary.averageRecognitionMs, 560)
    }

    func testRecentSessionsCanLoadMoreAfterInitialWindow() {
        let store = makeStore()
        let now = date("2026-04-03T12:00:00Z")
        let baseStart = date("2026-04-03T09:00:00Z")

        for index in 0..<105 {
            let startedAt = baseStart.addingTimeInterval(Double(index * 60))
            _ = store.recordSession(
                VoiceInputSessionDraft(
                    startedAt: startedAt,
                    endedAt: startedAt.addingTimeInterval(10),
                    languageCode: "zh-Hans",
                    recognizedText: "记录\(index)",
                    finalText: "记录\(index)",
                    refinementApplied: false,
                    asrProvider: ASRProvider.senseVoice.rawValue,
                    asrSource: "local",
                    recognitionTotalMs: 500,
                    recognitionEngineMs: 450,
                    recognitionFirstPartialMs: 150,
                    recognitionPartialCount: 2
                ),
                now: now
            )
        }

        XCTAssertEqual(store.recentSessions.count, 100)
        XCTAssertTrue(store.canLoadMoreRecentSessions)
        XCTAssertEqual(store.recentSessions.first?.finalText, "记录104")

        store.loadMoreRecentSessions()

        XCTAssertEqual(store.recentSessions.count, 105)
        XCTAssertFalse(store.canLoadMoreRecentSessions)
        XCTAssertEqual(store.recentSessions.last?.finalText, "记录0")
    }

    func testHourlyUsageSummariesGroupSessionsByStartHour() {
        let store = makeStore()
        let now = date("2026-04-03T12:00:00Z")

        for startedAt in [
            date("2026-04-03T08:10:00Z"),
            date("2026-04-03T08:40:00Z"),
            date("2026-04-03T13:20:00Z"),
        ] {
            _ = store.recordSession(
                VoiceInputSessionDraft(
                    startedAt: startedAt,
                    endedAt: startedAt.addingTimeInterval(10),
                    languageCode: "zh-Hans",
                    recognizedText: "小时分布",
                    finalText: "小时分布",
                    refinementApplied: false,
                    asrProvider: ASRProvider.senseVoice.rawValue,
                    asrSource: "local",
                    recognitionTotalMs: 500,
                    recognitionEngineMs: 450,
                    recognitionFirstPartialMs: 150,
                    recognitionPartialCount: 2
                ),
                now: now
            )
        }

        XCTAssertEqual(store.hourlyUsageSummaries.count, 24)
        XCTAssertEqual(store.hourlyUsageSummaries.first { $0.hour == 8 }?.sessionCount, 2)
        XCTAssertEqual(store.hourlyUsageSummaries.first { $0.hour == 13 }?.sessionCount, 1)
        XCTAssertEqual(store.hourlyUsageSummaries.first { $0.hour == 9 }?.sessionCount, 0)
    }

    func testFrontApplicationSummariesAreEmptyWhenSessionsHaveNoAppMetadata() {
        let store = makeStore()
        let now = date("2026-04-03T12:00:00Z")

        _ = store.recordSession(
            VoiceInputSessionDraft(
                startedAt: date("2026-04-03T08:10:00Z"),
                endedAt: date("2026-04-03T08:10:10Z"),
                languageCode: "zh-Hans",
                recognizedText: "场景数据",
                finalText: "场景数据",
                refinementApplied: false,
                asrProvider: ASRProvider.senseVoice.rawValue,
                asrSource: "local",
                recognitionTotalMs: 500,
                recognitionEngineMs: 450,
                recognitionFirstPartialMs: 150,
                recognitionPartialCount: 2
            ),
            now: now
        )

        XCTAssertEqual(store.frontApplicationSummaries, [])
    }

    func testFrontApplicationSummariesAggregateRecordedAppMetadata() {
        let store = makeStore()
        let now = date("2026-04-03T12:00:00Z")

        let sessions = [
            (bundleID: "com.apple.Terminal", name: "Terminal"),
            (bundleID: "com.apple.Terminal", name: "Terminal"),
            (bundleID: "com.todesktop.230313mzl4w4u92", name: "Cursor"),
        ]

        for (index, app) in sessions.enumerated() {
            let startedAt = date("2026-04-03T08:10:00Z").addingTimeInterval(Double(index * 60))
            _ = store.recordSession(
                VoiceInputSessionDraft(
                    startedAt: startedAt,
                    endedAt: startedAt.addingTimeInterval(10),
                    languageCode: "zh-Hans",
                    recognizedText: "场景数据",
                    finalText: "场景数据",
                    refinementApplied: false,
                    asrProvider: ASRProvider.senseVoice.rawValue,
                    asrSource: "local",
                    recognitionTotalMs: 500,
                    recognitionEngineMs: 450,
                    recognitionFirstPartialMs: 150,
                    recognitionPartialCount: 2,
                    frontApplicationBundleID: app.bundleID,
                    frontApplicationName: app.name
                ),
                now: now
            )
        }

        XCTAssertEqual(
            store.frontApplicationSummaries,
            [
                FrontApplicationUsageSummary(bundleID: "com.apple.Terminal", name: "Terminal", sessionCount: 2),
                FrontApplicationUsageSummary(bundleID: "com.todesktop.230313mzl4w4u92", name: "Cursor", sessionCount: 1),
            ]
        )
    }

    func testFrontApplicationSummariesLimitDashboardToTopFourApps() {
        let store = makeStore()
        let now = date("2026-04-03T12:00:00Z")

        for index in 0..<5 {
            let startedAt = date("2026-04-03T08:10:00Z").addingTimeInterval(Double(index * 60))
            let appName = "App \(UnicodeScalar(65 + index)!)"
            _ = store.recordSession(
                VoiceInputSessionDraft(
                    startedAt: startedAt,
                    endedAt: startedAt.addingTimeInterval(10),
                    languageCode: "zh-Hans",
                    recognizedText: "场景数据",
                    finalText: "场景数据",
                    refinementApplied: false,
                    asrProvider: ASRProvider.senseVoice.rawValue,
                    asrSource: "local",
                    recognitionTotalMs: 500,
                    recognitionEngineMs: 450,
                    recognitionFirstPartialMs: 150,
                    recognitionPartialCount: 2,
                    frontApplicationBundleID: "com.example.app\(index)",
                    frontApplicationName: appName
                ),
                now: now
            )
        }

        XCTAssertEqual(store.frontApplicationSessionCount, 5)
        XCTAssertEqual(
            store.frontApplicationSummaries,
            [
                FrontApplicationUsageSummary(bundleID: "com.example.app0", name: "App A", sessionCount: 1),
                FrontApplicationUsageSummary(bundleID: "com.example.app1", name: "App B", sessionCount: 1),
                FrontApplicationUsageSummary(bundleID: "com.example.app2", name: "App C", sessionCount: 1),
                FrontApplicationUsageSummary(bundleID: "com.example.app3", name: "App D", sessionCount: 1),
            ]
        )
    }

    func testFrontApplicationSessionCountIgnoresSessionsWithoutAppMetadata() {
        let store = makeStore()
        let now = date("2026-04-03T12:00:00Z")

        _ = store.recordSession(
            VoiceInputSessionDraft(
                startedAt: date("2026-04-03T08:10:00Z"),
                endedAt: date("2026-04-03T08:10:10Z"),
                languageCode: "zh-Hans",
                recognizedText: "旧记录",
                finalText: "旧记录",
                refinementApplied: false,
                asrProvider: ASRProvider.senseVoice.rawValue,
                asrSource: "local",
                recognitionTotalMs: 500,
                recognitionEngineMs: 450,
                recognitionFirstPartialMs: 150,
                recognitionPartialCount: 2
            ),
            now: now
        )
        _ = store.recordSession(
            VoiceInputSessionDraft(
                startedAt: date("2026-04-03T08:20:00Z"),
                endedAt: date("2026-04-03T08:20:10Z"),
                languageCode: "zh-Hans",
                recognizedText: "新记录",
                finalText: "新记录",
                refinementApplied: false,
                asrProvider: ASRProvider.senseVoice.rawValue,
                asrSource: "local",
                recognitionTotalMs: 500,
                recognitionEngineMs: 450,
                recognitionFirstPartialMs: 150,
                recognitionPartialCount: 2,
                frontApplicationBundleID: "com.openai.chatgpt",
                frontApplicationName: "Codex"
            ),
            now: now
        )

        XCTAssertEqual(store.lifetimeSummary.sessionCount, 2)
        XCTAssertEqual(store.frontApplicationSessionCount, 1)
    }

    func testHourlyUsageSummariesUseStoreCalendarTimeZone() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 8 * 3600)!
        let store = UsageStore(databasePath: ":memory:", calendar: calendar)
        let now = date("2026-04-04T00:30:00Z")

        _ = store.recordSession(
            VoiceInputSessionDraft(
                startedAt: date("2026-04-03T16:30:00Z"),
                endedAt: date("2026-04-03T16:30:10Z"),
                languageCode: "zh-Hans",
                recognizedText: "本地时区",
                finalText: "本地时区",
                refinementApplied: false,
                asrProvider: ASRProvider.senseVoice.rawValue,
                asrSource: "local",
                recognitionTotalMs: 500,
                recognitionEngineMs: 450,
                recognitionFirstPartialMs: 150,
                recognitionPartialCount: 2
            ),
            now: now
        )

        XCTAssertEqual(store.hourlyUsageSummaries.first { $0.hour == 0 }?.sessionCount, 1)
        XCTAssertEqual(store.hourlyUsageSummaries.first { $0.hour == 16 }?.sessionCount, 0)
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
