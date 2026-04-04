import Foundation
import Observation
import SQLite3

struct VoiceInputSession: Identifiable, Equatable {
    let id: UUID
    let startedAt: Date
    let endedAt: Date
    let durationMs: Int
    let languageCode: String
    let recognizedText: String
    let finalText: String
    let characterCount: Int
    let refinementApplied: Bool
    let injectionSucceeded: Bool?
}

struct HistorySessionRow: Identifiable, Equatable {
    let id: UUID
    let endedAt: Date
    let durationMs: Int
    let languageCode: String
    let finalText: String
    let characterCount: Int
    let refinementApplied: Bool
    let injectionSucceeded: Bool?
}

struct TodayUsageSummary: Equatable {
    let totalDurationMs: Int
    let totalCharacters: Int
    let sessionCount: Int

    static let empty = TodayUsageSummary(totalDurationMs: 0, totalCharacters: 0, sessionCount: 0)
}

struct DailyUsageSummary: Identifiable, Equatable {
    let date: Date
    let totalDurationMs: Int
    let totalCharacters: Int
    let sessionCount: Int

    var id: Date { date }
}

struct VoiceInputSessionDraft {
    let startedAt: Date
    let endedAt: Date
    let languageCode: String
    let recognizedText: String
    let finalText: String
    let refinementApplied: Bool
}

@MainActor
@Observable
final class UsageStore {
    enum UsageStoreError: Error {
        case databaseOpenFailed(String)
        case statementPrepareFailed(String)
        case statementExecutionFailed(String)
    }

    private enum Constants {
        static let recentSessionLimit = 500
        static let trendDayCount = 7
        static let heatmapDayCount = 84
    }

    private let calendar: Calendar
    @ObservationIgnored
    nonisolated(unsafe) private var database: OpaquePointer?

    private(set) var todaySummary: TodayUsageSummary = .empty
    private(set) var weeklySummaries: [DailyUsageSummary] = []
    private(set) var heatmapSummaries: [DailyUsageSummary] = []
    private(set) var recentSessions: [HistorySessionRow] = []

    init(databasePath: String? = nil, calendar: Calendar = .autoupdatingCurrent) {
        self.calendar = calendar

        do {
            try openDatabase(at: databasePath ?? Self.defaultDatabasePath())
            try createTablesIfNeeded()
            refresh()
        } catch {
            fatalError("UsageStore initialization failed: \(error)")
        }
    }

    deinit {
        sqlite3_close(database)
    }

    func refresh(now: Date = Date()) {
        todaySummary = fetchTodaySummary(now: now)
        weeklySummaries = fetchLastDays(count: Constants.trendDayCount, now: now)
        heatmapSummaries = fetchLastDays(count: Constants.heatmapDayCount, now: now)
        recentSessions = fetchRecentSessions(limit: Constants.recentSessionLimit, offset: 0)
    }

    func fetchTodaySummary(now: Date = Date()) -> TodayUsageSummary {
        let dayKey = Self.dayKey(for: now, calendar: calendar)
        let sql = """
        SELECT
            COALESCE(SUM(duration_ms), 0),
            COALESCE(SUM(character_count), 0),
            COUNT(*)
        FROM voice_input_sessions
        WHERE day_key = ?1;
        """

        guard let statement = try? prepareStatement(sql: sql) else {
            return .empty
        }
        defer { sqlite3_finalize(statement) }

        sqlite3_bind_text(statement, 1, dayKey, -1, transientDestructor)

        guard sqlite3_step(statement) == SQLITE_ROW else {
            return .empty
        }

        return TodayUsageSummary(
            totalDurationMs: Int(sqlite3_column_int64(statement, 0)),
            totalCharacters: Int(sqlite3_column_int64(statement, 1)),
            sessionCount: Int(sqlite3_column_int64(statement, 2))
        )
    }

    func fetchDailySummaries(range: DateInterval) -> [DailyUsageSummary] {
        let start = calendar.startOfDay(for: range.start)
        let end = range.end
        let sql = """
        SELECT
            day_key,
            COALESCE(SUM(duration_ms), 0),
            COALESCE(SUM(character_count), 0),
            COUNT(*)
        FROM voice_input_sessions
        WHERE ended_at >= ?1 AND ended_at < ?2
        GROUP BY day_key
        ORDER BY day_key ASC;
        """

        guard let statement = try? prepareStatement(sql: sql) else {
            return []
        }
        defer { sqlite3_finalize(statement) }

        sqlite3_bind_double(statement, 1, start.timeIntervalSince1970)
        sqlite3_bind_double(statement, 2, end.timeIntervalSince1970)

        var grouped: [String: DailyUsageSummary] = [:]

        while sqlite3_step(statement) == SQLITE_ROW {
            guard
                let rawDayKey = sqlite3_column_text(statement, 0).map({ String(cString: $0) }),
                let date = Self.date(from: rawDayKey, calendar: calendar)
            else {
                continue
            }

            grouped[rawDayKey] = DailyUsageSummary(
                date: date,
                totalDurationMs: Int(sqlite3_column_int64(statement, 1)),
                totalCharacters: Int(sqlite3_column_int64(statement, 2)),
                sessionCount: Int(sqlite3_column_int64(statement, 3))
            )
        }

        return grouped.values.sorted { $0.date < $1.date }
    }

    func fetchRecentSessions(limit: Int, offset: Int = 0) -> [HistorySessionRow] {
        let sql = """
        SELECT
            id,
            ended_at,
            duration_ms,
            language_code,
            final_text,
            character_count,
            refinement_applied,
            injection_succeeded
        FROM voice_input_sessions
        ORDER BY ended_at DESC
        LIMIT ?1 OFFSET ?2;
        """

        guard let statement = try? prepareStatement(sql: sql) else {
            return []
        }
        defer { sqlite3_finalize(statement) }

        sqlite3_bind_int(statement, 1, Int32(limit))
        sqlite3_bind_int(statement, 2, Int32(offset))

        var rows: [HistorySessionRow] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            guard let session = historyRow(from: statement) else {
                continue
            }
            rows.append(session)
        }

        return rows
    }

    func copyableText(for sessionID: UUID) -> String? {
        let sql = """
        SELECT final_text
        FROM voice_input_sessions
        WHERE id = ?1
        LIMIT 1;
        """

        guard let statement = try? prepareStatement(sql: sql) else {
            return nil
        }
        defer { sqlite3_finalize(statement) }

        sqlite3_bind_text(statement, 1, sessionID.uuidString, -1, transientDestructor)

        guard sqlite3_step(statement) == SQLITE_ROW else {
            return nil
        }

        return sqlite3_column_text(statement, 0).map { String(cString: $0) }
    }

    @discardableResult
    func recordSession(_ draft: VoiceInputSessionDraft, now: Date = Date()) -> UUID? {
        let trimmedText = draft.finalText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedText.isEmpty else {
            return nil
        }

        let sessionID = UUID()
        let sql = """
        INSERT INTO voice_input_sessions (
            id,
            day_key,
            started_at,
            ended_at,
            duration_ms,
            language_code,
            recognized_text,
            final_text,
            character_count,
            refinement_applied,
            injection_succeeded
        ) VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7, ?8, ?9, ?10, NULL);
        """

        guard let statement = try? prepareStatement(sql: sql) else {
            return nil
        }
        defer { sqlite3_finalize(statement) }

        sqlite3_bind_text(statement, 1, sessionID.uuidString, -1, transientDestructor)
        sqlite3_bind_text(statement, 2, Self.dayKey(for: draft.endedAt, calendar: calendar), -1, transientDestructor)
        sqlite3_bind_double(statement, 3, draft.startedAt.timeIntervalSince1970)
        sqlite3_bind_double(statement, 4, draft.endedAt.timeIntervalSince1970)
        sqlite3_bind_int64(statement, 5, sqlite3_int64(max(0, Int(draft.endedAt.timeIntervalSince(draft.startedAt) * 1000))))
        sqlite3_bind_text(statement, 6, draft.languageCode, -1, transientDestructor)
        sqlite3_bind_text(statement, 7, draft.recognizedText, -1, transientDestructor)
        sqlite3_bind_text(statement, 8, trimmedText, -1, transientDestructor)
        sqlite3_bind_int(statement, 9, Int32(trimmedText.count))
        sqlite3_bind_int(statement, 10, draft.refinementApplied ? 1 : 0)

        guard sqlite3_step(statement) == SQLITE_DONE else {
            return nil
        }

        refresh(now: now)
        return sessionID
    }

    func markInjectionResult(sessionID: UUID, succeeded: Bool, now: Date = Date()) {
        let sql = """
        UPDATE voice_input_sessions
        SET injection_succeeded = ?2
        WHERE id = ?1;
        """

        guard let statement = try? prepareStatement(sql: sql) else {
            return
        }
        defer { sqlite3_finalize(statement) }

        sqlite3_bind_text(statement, 1, sessionID.uuidString, -1, transientDestructor)
        sqlite3_bind_int(statement, 2, succeeded ? 1 : 0)
        _ = sqlite3_step(statement)
        refresh(now: now)
    }

    private func fetchLastDays(count: Int, now: Date) -> [DailyUsageSummary] {
        guard count > 0 else { return [] }

        let today = calendar.startOfDay(for: now)
        guard let start = calendar.date(byAdding: .day, value: -(count - 1), to: today) else {
            return []
        }

        let end = calendar.date(byAdding: .day, value: 1, to: today) ?? now
        let summaries = fetchDailySummaries(range: DateInterval(start: start, end: end))
        let summaryMap = Dictionary(uniqueKeysWithValues: summaries.map { ($0.date, $0) })

        return (0..<count).compactMap { offset in
            guard let date = calendar.date(byAdding: .day, value: offset, to: start) else {
                return nil
            }

            return summaryMap[date] ?? DailyUsageSummary(date: date, totalDurationMs: 0, totalCharacters: 0, sessionCount: 0)
        }
    }

    private func historyRow(from statement: OpaquePointer?) -> HistorySessionRow? {
        guard
            let rawID = sqlite3_column_text(statement, 0).map({ String(cString: $0) }),
            let id = UUID(uuidString: rawID),
            let finalText = sqlite3_column_text(statement, 4).map({ String(cString: $0) })
        else {
            return nil
        }

        let injectionSucceeded: Bool?
        if sqlite3_column_type(statement, 7) == SQLITE_NULL {
            injectionSucceeded = nil
        } else {
            injectionSucceeded = sqlite3_column_int(statement, 7) == 1
        }

        return HistorySessionRow(
            id: id,
            endedAt: Date(timeIntervalSince1970: sqlite3_column_double(statement, 1)),
            durationMs: Int(sqlite3_column_int64(statement, 2)),
            languageCode: sqlite3_column_text(statement, 3).map { String(cString: $0) } ?? "",
            finalText: finalText,
            characterCount: Int(sqlite3_column_int64(statement, 5)),
            refinementApplied: sqlite3_column_int(statement, 6) == 1,
            injectionSucceeded: injectionSucceeded
        )
    }

    private func openDatabase(at path: String) throws {
        if path != ":memory:" {
            let directoryURL = URL(fileURLWithPath: path).deletingLastPathComponent()
            try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        }

        var handle: OpaquePointer?
        guard sqlite3_open(path, &handle) == SQLITE_OK else {
            let message = handle.flatMap { sqlite3_errmsg($0) }.map { String(cString: $0) } ?? "unknown error"
            sqlite3_close(handle)
            throw UsageStoreError.databaseOpenFailed(message)
        }

        database = handle
    }

    private func createTablesIfNeeded() throws {
        let sql = """
        CREATE TABLE IF NOT EXISTS voice_input_sessions (
            id TEXT PRIMARY KEY,
            day_key TEXT NOT NULL,
            started_at DOUBLE NOT NULL,
            ended_at DOUBLE NOT NULL,
            duration_ms INTEGER NOT NULL,
            language_code TEXT NOT NULL,
            recognized_text TEXT NOT NULL,
            final_text TEXT NOT NULL,
            character_count INTEGER NOT NULL,
            refinement_applied INTEGER NOT NULL,
            injection_succeeded INTEGER NULL
        );

        CREATE INDEX IF NOT EXISTS idx_voice_input_sessions_day_key
            ON voice_input_sessions(day_key);
        CREATE INDEX IF NOT EXISTS idx_voice_input_sessions_ended_at
            ON voice_input_sessions(ended_at DESC);
        """

        guard sqlite3_exec(database, sql, nil, nil, nil) == SQLITE_OK else {
            throw UsageStoreError.statementExecutionFailed(lastSQLiteErrorMessage())
        }
    }

    private func prepareStatement(sql: String) throws -> OpaquePointer? {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK else {
            throw UsageStoreError.statementPrepareFailed(lastSQLiteErrorMessage())
        }
        return statement
    }

    private func lastSQLiteErrorMessage() -> String {
        sqlite3_errmsg(database).map { String(cString: $0) } ?? "unknown error"
    }

    private static func defaultDatabasePath() -> String {
        let baseURL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory())
        return baseURL
            .appendingPathComponent("Voily", isDirectory: true)
            .appendingPathComponent("usage.sqlite", isDirectory: false)
            .path
    }

    private static func dayKey(for date: Date, calendar: Calendar) -> String {
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = calendar.timeZone
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: calendar.startOfDay(for: date))
    }

    private static func date(from dayKey: String, calendar: Calendar) -> Date? {
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = calendar.timeZone
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.date(from: dayKey)
    }
}

private let transientDestructor = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
