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
                refinementApplied: false
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
                refinementApplied: true
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
                refinementApplied: true
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
                    refinementApplied: false
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
                    refinementApplied: false
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
