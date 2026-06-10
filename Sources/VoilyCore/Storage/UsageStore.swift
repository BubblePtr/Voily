import Foundation
import Observation
import SQLite3

struct VoiceInputSession: Identifiable, Equatable, Sendable {
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

public struct HistorySessionRow: Identifiable, Equatable, Sendable {
    public let id: UUID
    public let endedAt: Date
    public let durationMs: Int
    public let languageCode: String
    public let finalText: String
    public let characterCount: Int
    public let refinementApplied: Bool
    public let injectionSucceeded: Bool?
    public let asrProvider: String
    public let asrSource: String
    public let recognitionTotalMs: Int
    public let recognitionEngineMs: Int?
    public let recognitionFirstPartialMs: Int?
    public let recognitionPartialCount: Int
}

public struct TodayUsageSummary: Equatable, Sendable {
    public let totalDurationMs: Int
    public let totalCharacters: Int
    public let sessionCount: Int

    public static let empty = TodayUsageSummary(totalDurationMs: 0, totalCharacters: 0, sessionCount: 0)
}

public struct LifetimeUsageSummary: Equatable, Sendable {
    public let totalDurationMs: Int
    public let totalCharacters: Int
    public let sessionCount: Int
    public let averageRecognitionMs: Int

    public var averageCharactersPerMinute: Int {
        guard totalDurationMs > 0, totalCharacters > 0 else { return 0 }
        let charactersPerMinute = (Double(totalCharacters) * 60_000.0) / Double(totalDurationMs)
        return Int(charactersPerMinute.rounded())
    }

    public static let empty = LifetimeUsageSummary(
        totalDurationMs: 0,
        totalCharacters: 0,
        sessionCount: 0,
        averageRecognitionMs: 0
    )
}

public struct TodayASRPerformanceSummary: Equatable, Sendable {
    public let averageFirstPartialMs: Int
    public let averageRecognitionMs: Int
    public let partialCount: Int
    public let localSessionCount: Int
    public let sessionCount: Int

    public static let empty = TodayASRPerformanceSummary(
        averageFirstPartialMs: 0,
        averageRecognitionMs: 0,
        partialCount: 0,
        localSessionCount: 0,
        sessionCount: 0
    )
}

public struct DailyUsageSummary: Identifiable, Equatable, Sendable {
    public let date: Date
    public let totalDurationMs: Int
    public let totalCharacters: Int
    public let sessionCount: Int

    public var id: Date { date }

    public init(date: Date, totalDurationMs: Int, totalCharacters: Int, sessionCount: Int) {
        self.date = date
        self.totalDurationMs = totalDurationMs
        self.totalCharacters = totalCharacters
        self.sessionCount = sessionCount
    }
}

public struct HourlyUsageSummary: Identifiable, Equatable, Sendable {
    public let hour: Int
    public let sessionCount: Int

    public var id: Int { hour }

    public init(hour: Int, sessionCount: Int) {
        self.hour = hour
        self.sessionCount = sessionCount
    }
}

public struct FrontApplicationUsageSummary: Identifiable, Equatable, Sendable {
    public let bundleID: String
    public let name: String
    public let sessionCount: Int

    public var id: String { bundleID }

    public init(bundleID: String, name: String, sessionCount: Int) {
        self.bundleID = bundleID
        self.name = name
        self.sessionCount = sessionCount
    }
}

public struct VoiceInputSessionDraft: Sendable {
    public let startedAt: Date
    public let endedAt: Date
    public let languageCode: String
    public let recognizedText: String
    public let finalText: String
    public let refinementApplied: Bool
    public let asrProvider: String
    public let asrSource: String
    public let recognitionTotalMs: Int
    public let recognitionEngineMs: Int?
    public let recognitionFirstPartialMs: Int?
    public let recognitionPartialCount: Int
    public let frontApplicationBundleID: String?
    public let frontApplicationName: String?

    public init(
        startedAt: Date,
        endedAt: Date,
        languageCode: String,
        recognizedText: String,
        finalText: String,
        refinementApplied: Bool,
        asrProvider: String,
        asrSource: String,
        recognitionTotalMs: Int,
        recognitionEngineMs: Int?,
        recognitionFirstPartialMs: Int?,
        recognitionPartialCount: Int,
        frontApplicationBundleID: String? = nil,
        frontApplicationName: String? = nil
    ) {
        self.startedAt = startedAt
        self.endedAt = endedAt
        self.languageCode = languageCode
        self.recognizedText = recognizedText
        self.finalText = finalText
        self.refinementApplied = refinementApplied
        self.asrProvider = asrProvider
        self.asrSource = asrSource
        self.recognitionTotalMs = recognitionTotalMs
        self.recognitionEngineMs = recognitionEngineMs
        self.recognitionFirstPartialMs = recognitionFirstPartialMs
        self.recognitionPartialCount = recognitionPartialCount
        self.frontApplicationBundleID = frontApplicationBundleID
        self.frontApplicationName = frontApplicationName
    }
}

@MainActor
@Observable
public final class UsageStore {
    enum UsageStoreError: Error {
        case databaseOpenFailed(String)
        case statementPrepareFailed(String)
        case statementExecutionFailed(String)
    }

    private enum Constants {
        static let recentSessionLimit = 100
        static let trendDayCount = 7
        static let heatmapDayCount = 84
        static let frontApplicationLimit = 4
    }

    private struct FrontApplicationDistributionSnapshot {
        let summaries: [FrontApplicationUsageSummary]
        let totalSessionCount: Int

        static let empty = FrontApplicationDistributionSnapshot(summaries: [], totalSessionCount: 0)
    }

    private let calendar: Calendar
    @ObservationIgnored
    nonisolated(unsafe) private var database: OpaquePointer?

    public private(set) var todaySummary: TodayUsageSummary = .empty
    public private(set) var lifetimeSummary: LifetimeUsageSummary = .empty
    public private(set) var todayASRSummary: TodayASRPerformanceSummary = .empty
    public private(set) var weeklySummaries: [DailyUsageSummary] = []
    public private(set) var heatmapSummaries: [DailyUsageSummary] = []
    public private(set) var hourlyUsageSummaries: [HourlyUsageSummary] = []
    public private(set) var frontApplicationSummaries: [FrontApplicationUsageSummary] = []
    public private(set) var frontApplicationSessionCount = 0
    public private(set) var recentSessions: [HistorySessionRow] = []
    public private(set) var canLoadMoreRecentSessions = false

    public init(databasePath: String? = nil, calendar: Calendar = .autoupdatingCurrent) {
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

    public func refresh(now: Date = Date()) {
        todaySummary = fetchTodaySummary(now: now)
        lifetimeSummary = fetchLifetimeSummary()
        todayASRSummary = fetchTodayASRSummary(now: now)
        weeklySummaries = fetchLastDays(count: Constants.trendDayCount, now: now)
        heatmapSummaries = fetchLastDays(count: Constants.heatmapDayCount, now: now)
        hourlyUsageSummaries = fetchHourlyUsageSummaries()
        let frontApplicationDistribution = fetchFrontApplicationDistribution(limit: Constants.frontApplicationLimit)
        frontApplicationSummaries = frontApplicationDistribution.summaries
        frontApplicationSessionCount = frontApplicationDistribution.totalSessionCount
        refreshRecentSessions(limit: max(Constants.recentSessionLimit, recentSessions.count))
    }

    public func fetchTodaySummary(now: Date = Date()) -> TodayUsageSummary {
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

    public func fetchLifetimeSummary() -> LifetimeUsageSummary {
        let sql = """
        SELECT
            total_duration_ms,
            total_characters,
            session_count,
            total_recognition_ms
        FROM usage_lifetime_summary
        WHERE id = 1
        LIMIT 1;
        """

        guard let statement = try? prepareStatement(sql: sql) else {
            return .empty
        }
        defer { sqlite3_finalize(statement) }

        guard sqlite3_step(statement) == SQLITE_ROW else {
            return .empty
        }

        let sessionCount = Int(sqlite3_column_int64(statement, 2))
        let totalRecognitionMs = Int(sqlite3_column_int64(statement, 3))
        return LifetimeUsageSummary(
            totalDurationMs: Int(sqlite3_column_int64(statement, 0)),
            totalCharacters: Int(sqlite3_column_int64(statement, 1)),
            sessionCount: sessionCount,
            averageRecognitionMs: sessionCount > 0 ? totalRecognitionMs / sessionCount : 0
        )
    }

    public func fetchDailySummaries(range: DateInterval) -> [DailyUsageSummary] {
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

    public func fetchHourlyUsageSummaries() -> [HourlyUsageSummary] {
        let sql = """
        SELECT
            started_hour,
            COUNT(*)
        FROM voice_input_sessions
        WHERE started_hour >= 0 AND started_hour < 24
        GROUP BY started_hour
        ORDER BY started_hour ASC;
        """

        guard let statement = try? prepareStatement(sql: sql) else {
            return (0..<24).map { HourlyUsageSummary(hour: $0, sessionCount: 0) }
        }
        defer { sqlite3_finalize(statement) }

        var counts = Array(repeating: 0, count: 24)
        while sqlite3_step(statement) == SQLITE_ROW {
            let hour = Int(sqlite3_column_int64(statement, 0))
            guard counts.indices.contains(hour) else { continue }
            counts[hour] = Int(sqlite3_column_int64(statement, 1))
        }

        return counts.enumerated().map { hour, count in
            HourlyUsageSummary(hour: hour, sessionCount: count)
        }
    }

    public func fetchFrontApplicationSummaries(limit: Int) -> [FrontApplicationUsageSummary] {
        fetchFrontApplicationDistribution(limit: limit).summaries
    }

    private func fetchFrontApplicationDistribution(limit: Int) -> FrontApplicationDistributionSnapshot {
        guard limit > 0 else { return .empty }
        let sql = """
        WITH grouped AS (
            SELECT
                front_application_bundle_id,
                front_application_name,
                COUNT(*) AS session_count
            FROM voice_input_sessions
            WHERE
                front_application_bundle_id IS NOT NULL
                AND front_application_bundle_id != ''
                AND front_application_name IS NOT NULL
                AND front_application_name != ''
            GROUP BY front_application_bundle_id, front_application_name
        ),
        ranked AS (
            SELECT
                front_application_bundle_id,
                front_application_name,
                session_count,
                SUM(session_count) OVER () AS total_session_count
            FROM grouped
        )
        SELECT
            front_application_bundle_id,
            front_application_name,
            session_count,
            total_session_count
        FROM ranked
        ORDER BY session_count DESC, front_application_name ASC
        LIMIT ?1;
        """

        guard let statement = try? prepareStatement(sql: sql) else {
            return .empty
        }
        defer { sqlite3_finalize(statement) }

        sqlite3_bind_int(statement, 1, Int32(limit))

        var summaries: [FrontApplicationUsageSummary] = []
        var totalSessionCount = 0
        while sqlite3_step(statement) == SQLITE_ROW {
            guard
                let rawBundleID = sqlite3_column_text(statement, 0).map({ String(cString: $0) }),
                let rawName = sqlite3_column_text(statement, 1).map({ String(cString: $0) })
            else {
                continue
            }

            summaries.append(
                FrontApplicationUsageSummary(
                    bundleID: rawBundleID,
                    name: rawName,
                    sessionCount: Int(sqlite3_column_int64(statement, 2))
                )
            )
            totalSessionCount = Int(sqlite3_column_int64(statement, 3))
        }

        return FrontApplicationDistributionSnapshot(summaries: summaries, totalSessionCount: totalSessionCount)
    }

    public func fetchFrontApplicationSessionCount() -> Int {
        let sql = """
        SELECT COUNT(*)
        FROM voice_input_sessions
        WHERE
            front_application_bundle_id IS NOT NULL
            AND front_application_bundle_id != ''
            AND front_application_name IS NOT NULL
            AND front_application_name != '';
        """

        guard let statement = try? prepareStatement(sql: sql) else {
            return 0
        }
        defer { sqlite3_finalize(statement) }

        guard sqlite3_step(statement) == SQLITE_ROW else {
            return 0
        }

        return Int(sqlite3_column_int64(statement, 0))
    }

    public func fetchTodayASRSummary(now: Date = Date()) -> TodayASRPerformanceSummary {
        let dayKey = Self.dayKey(for: now, calendar: calendar)
        let sql = """
        SELECT
            COALESCE(AVG(CASE
                WHEN recognition_first_partial_ms IS NOT NULL AND recognition_first_partial_ms > 0 THEN recognition_first_partial_ms
                ELSE NULL
            END), 0),
            COALESCE(AVG(recognition_total_ms), 0),
            COALESCE(SUM(CASE
                WHEN recognition_partial_count IS NOT NULL AND recognition_partial_count > 0 THEN recognition_partial_count
                ELSE 0
            END), 0),
            COALESCE(SUM(CASE WHEN asr_source = 'local' THEN 1 ELSE 0 END), 0),
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

        return TodayASRPerformanceSummary(
            averageFirstPartialMs: Int(sqlite3_column_int64(statement, 0)),
            averageRecognitionMs: Int(sqlite3_column_int64(statement, 1)),
            partialCount: Int(sqlite3_column_int64(statement, 2)),
            localSessionCount: Int(sqlite3_column_int64(statement, 3)),
            sessionCount: Int(sqlite3_column_int64(statement, 4))
        )
    }

    public func fetchRecentSessions(limit: Int, offset: Int = 0) -> [HistorySessionRow] {
        let sql = """
        SELECT
            id,
            ended_at,
            duration_ms,
            language_code,
            final_text,
            character_count,
            refinement_applied,
            injection_succeeded,
            asr_provider,
            asr_source,
            recognition_total_ms,
            recognition_engine_ms,
            recognition_first_partial_ms,
            recognition_partial_count
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

    public func loadMoreRecentSessions() {
        guard canLoadMoreRecentSessions else { return }
        refreshRecentSessions(limit: recentSessions.count + Constants.recentSessionLimit)
    }

    public func copyableText(for sessionID: UUID) -> String? {
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
    public func recordSession(_ draft: VoiceInputSessionDraft, now: Date = Date()) -> UUID? {
        let trimmedText = draft.finalText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedText.isEmpty else {
            return nil
        }

        let sessionID = UUID()
        let durationMs = max(0, Int(draft.endedAt.timeIntervalSince(draft.startedAt) * 1000))
        let characterCount = trimmedText.count
        let recognitionTotalMs = max(0, draft.recognitionTotalMs)
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
            injection_succeeded,
            asr_provider,
            asr_source,
            recognition_total_ms,
            recognition_engine_ms,
            recognition_first_partial_ms,
            recognition_partial_count,
            front_application_bundle_id,
            front_application_name,
            started_hour
        ) VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7, ?8, ?9, ?10, NULL, ?11, ?12, ?13, ?14, ?15, ?16, ?17, ?18, ?19);
        """

        guard let statement = try? prepareStatement(sql: sql) else {
            return nil
        }
        defer { sqlite3_finalize(statement) }

        sqlite3_bind_text(statement, 1, sessionID.uuidString, -1, transientDestructor)
        sqlite3_bind_text(statement, 2, Self.dayKey(for: draft.endedAt, calendar: calendar), -1, transientDestructor)
        sqlite3_bind_double(statement, 3, draft.startedAt.timeIntervalSince1970)
        sqlite3_bind_double(statement, 4, draft.endedAt.timeIntervalSince1970)
        sqlite3_bind_int64(statement, 5, sqlite3_int64(durationMs))
        sqlite3_bind_text(statement, 6, draft.languageCode, -1, transientDestructor)
        sqlite3_bind_text(statement, 7, draft.recognizedText, -1, transientDestructor)
        sqlite3_bind_text(statement, 8, trimmedText, -1, transientDestructor)
        sqlite3_bind_int(statement, 9, Int32(characterCount))
        sqlite3_bind_int(statement, 10, draft.refinementApplied ? 1 : 0)
        sqlite3_bind_text(statement, 11, draft.asrProvider, -1, transientDestructor)
        sqlite3_bind_text(statement, 12, draft.asrSource, -1, transientDestructor)
        sqlite3_bind_int64(statement, 13, sqlite3_int64(recognitionTotalMs))
        if let recognitionEngineMs = draft.recognitionEngineMs {
            sqlite3_bind_int64(statement, 14, sqlite3_int64(max(0, recognitionEngineMs)))
        } else {
            sqlite3_bind_null(statement, 14)
        }
        if let recognitionFirstPartialMs = draft.recognitionFirstPartialMs {
            sqlite3_bind_int64(statement, 15, sqlite3_int64(max(0, recognitionFirstPartialMs)))
        } else {
            sqlite3_bind_null(statement, 15)
        }
        sqlite3_bind_int64(statement, 16, sqlite3_int64(max(0, draft.recognitionPartialCount)))
        if let frontApplicationBundleID = draft.frontApplicationBundleID?.trimmingCharacters(in: .whitespacesAndNewlines),
           !frontApplicationBundleID.isEmpty {
            sqlite3_bind_text(statement, 17, frontApplicationBundleID, -1, transientDestructor)
        } else {
            sqlite3_bind_null(statement, 17)
        }
        if let frontApplicationName = draft.frontApplicationName?.trimmingCharacters(in: .whitespacesAndNewlines),
           !frontApplicationName.isEmpty {
            sqlite3_bind_text(statement, 18, frontApplicationName, -1, transientDestructor)
        } else {
            sqlite3_bind_null(statement, 18)
        }
        sqlite3_bind_int(statement, 19, Int32(localHour(for: draft.startedAt)))

        guard sqlite3_step(statement) == SQLITE_DONE else {
            return nil
        }

        if !incrementLifetimeSummaryCache(
            durationMs: durationMs,
            characterCount: characterCount,
            recognitionTotalMs: recognitionTotalMs
        ) {
            try? rebuildLifetimeSummaryCache()
        }

        refresh(now: now)
        return sessionID
    }

    private func refreshRecentSessions(limit: Int) {
        let requestedLimit = max(Constants.recentSessionLimit, limit)
        let rows = fetchRecentSessions(limit: requestedLimit + 1, offset: 0)
        canLoadMoreRecentSessions = rows.count > requestedLimit
        recentSessions = Array(rows.prefix(requestedLimit))
    }

    public func markInjectionResult(sessionID: UUID, succeeded: Bool, now: Date = Date()) {
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

        let recognitionEngineMs: Int?
        if sqlite3_column_type(statement, 11) == SQLITE_NULL {
            recognitionEngineMs = nil
        } else {
            recognitionEngineMs = Int(sqlite3_column_int64(statement, 11))
        }
        let recognitionFirstPartialMs: Int?
        if sqlite3_column_type(statement, 12) == SQLITE_NULL {
            recognitionFirstPartialMs = nil
        } else {
            recognitionFirstPartialMs = Int(sqlite3_column_int64(statement, 12))
        }

        return HistorySessionRow(
            id: id,
            endedAt: Date(timeIntervalSince1970: sqlite3_column_double(statement, 1)),
            durationMs: Int(sqlite3_column_int64(statement, 2)),
            languageCode: sqlite3_column_text(statement, 3).map { String(cString: $0) } ?? "",
            finalText: finalText,
            characterCount: Int(sqlite3_column_int64(statement, 5)),
            refinementApplied: sqlite3_column_int(statement, 6) == 1,
            injectionSucceeded: injectionSucceeded,
            asrProvider: sqlite3_column_text(statement, 8).map { String(cString: $0) } ?? "",
            asrSource: sqlite3_column_text(statement, 9).map { String(cString: $0) } ?? "",
            recognitionTotalMs: Int(sqlite3_column_int64(statement, 10)),
            recognitionEngineMs: recognitionEngineMs,
            recognitionFirstPartialMs: recognitionFirstPartialMs,
            recognitionPartialCount: Int(sqlite3_column_int64(statement, 13))
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
            started_hour INTEGER NULL,
            duration_ms INTEGER NOT NULL,
            language_code TEXT NOT NULL,
            recognized_text TEXT NOT NULL,
            final_text TEXT NOT NULL,
            character_count INTEGER NOT NULL,
            refinement_applied INTEGER NOT NULL,
            injection_succeeded INTEGER NULL,
            asr_provider TEXT NOT NULL DEFAULT '',
            asr_source TEXT NOT NULL DEFAULT '',
            recognition_total_ms INTEGER NOT NULL DEFAULT 0,
            recognition_engine_ms INTEGER NULL,
            recognition_first_partial_ms INTEGER NULL,
            recognition_partial_count INTEGER NOT NULL DEFAULT 0,
            front_application_bundle_id TEXT NULL,
            front_application_name TEXT NULL
        );

        CREATE INDEX IF NOT EXISTS idx_voice_input_sessions_day_key
            ON voice_input_sessions(day_key);
        CREATE INDEX IF NOT EXISTS idx_voice_input_sessions_ended_at
            ON voice_input_sessions(ended_at DESC);
        """

        guard sqlite3_exec(database, sql, nil, nil, nil) == SQLITE_OK else {
            throw UsageStoreError.statementExecutionFailed(lastSQLiteErrorMessage())
        }

        try addColumnIfNeeded(name: "asr_provider", definition: "TEXT NOT NULL DEFAULT ''")
        try addColumnIfNeeded(name: "asr_source", definition: "TEXT NOT NULL DEFAULT ''")
        try addColumnIfNeeded(name: "recognition_total_ms", definition: "INTEGER NOT NULL DEFAULT 0")
        try addColumnIfNeeded(name: "recognition_engine_ms", definition: "INTEGER NULL")
        try addColumnIfNeeded(name: "recognition_first_partial_ms", definition: "INTEGER NULL")
        try addColumnIfNeeded(name: "recognition_partial_count", definition: "INTEGER NOT NULL DEFAULT 0")
        try addColumnIfNeeded(name: "front_application_bundle_id", definition: "TEXT NULL")
        try addColumnIfNeeded(name: "front_application_name", definition: "TEXT NULL")
        try addColumnIfNeeded(name: "started_hour", definition: "INTEGER NULL")
        try createLifetimeSummaryCacheIfNeeded()
        try createIndexIfNeeded(
            sql: """
            CREATE INDEX IF NOT EXISTS idx_voice_input_sessions_started_hour
                ON voice_input_sessions(started_hour);
            """
        )
        try createIndexIfNeeded(
            sql: """
            CREATE INDEX IF NOT EXISTS idx_voice_input_sessions_front_application
                ON voice_input_sessions(front_application_bundle_id, front_application_name);
            """
        )
        try backfillStartedHourIfNeeded()
        try rebuildLifetimeSummaryCache()
    }

    private func addColumnIfNeeded(name: String, definition: String) throws {
        let sql = "PRAGMA table_info(voice_input_sessions);"
        guard let statement = try? prepareStatement(sql: sql) else {
            throw UsageStoreError.statementPrepareFailed(lastSQLiteErrorMessage())
        }
        defer { sqlite3_finalize(statement) }

        while sqlite3_step(statement) == SQLITE_ROW {
            if let rawName = sqlite3_column_text(statement, 1).map({ String(cString: $0) }), rawName == name {
                return
            }
        }

        let alterSQL = "ALTER TABLE voice_input_sessions ADD COLUMN \(name) \(definition);"
        guard sqlite3_exec(database, alterSQL, nil, nil, nil) == SQLITE_OK else {
            throw UsageStoreError.statementExecutionFailed(lastSQLiteErrorMessage())
        }
    }

    private func createIndexIfNeeded(sql: String) throws {
        guard sqlite3_exec(database, sql, nil, nil, nil) == SQLITE_OK else {
            throw UsageStoreError.statementExecutionFailed(lastSQLiteErrorMessage())
        }
    }

    private func createLifetimeSummaryCacheIfNeeded() throws {
        let sql = """
        CREATE TABLE IF NOT EXISTS usage_lifetime_summary (
            id INTEGER PRIMARY KEY CHECK (id = 1),
            session_count INTEGER NOT NULL,
            total_duration_ms INTEGER NOT NULL,
            total_characters INTEGER NOT NULL,
            total_recognition_ms INTEGER NOT NULL
        );
        """

        guard sqlite3_exec(database, sql, nil, nil, nil) == SQLITE_OK else {
            throw UsageStoreError.statementExecutionFailed(lastSQLiteErrorMessage())
        }
    }

    private func rebuildLifetimeSummaryCache() throws {
        let sql = """
        INSERT OR REPLACE INTO usage_lifetime_summary (
            id,
            session_count,
            total_duration_ms,
            total_characters,
            total_recognition_ms
        )
        SELECT
            1,
            COUNT(*),
            COALESCE(SUM(duration_ms), 0),
            COALESCE(SUM(character_count), 0),
            COALESCE(SUM(recognition_total_ms), 0)
        FROM voice_input_sessions;
        """

        guard sqlite3_exec(database, sql, nil, nil, nil) == SQLITE_OK else {
            throw UsageStoreError.statementExecutionFailed(lastSQLiteErrorMessage())
        }
    }

    private func incrementLifetimeSummaryCache(durationMs: Int, characterCount: Int, recognitionTotalMs: Int) -> Bool {
        let sql = """
        INSERT INTO usage_lifetime_summary (
            id,
            session_count,
            total_duration_ms,
            total_characters,
            total_recognition_ms
        ) VALUES (1, 1, ?1, ?2, ?3)
        ON CONFLICT(id) DO UPDATE SET
            session_count = session_count + 1,
            total_duration_ms = total_duration_ms + excluded.total_duration_ms,
            total_characters = total_characters + excluded.total_characters,
            total_recognition_ms = total_recognition_ms + excluded.total_recognition_ms;
        """

        guard let statement = try? prepareStatement(sql: sql) else {
            return false
        }
        defer { sqlite3_finalize(statement) }

        sqlite3_bind_int64(statement, 1, sqlite3_int64(durationMs))
        sqlite3_bind_int64(statement, 2, sqlite3_int64(characterCount))
        sqlite3_bind_int64(statement, 3, sqlite3_int64(recognitionTotalMs))

        return sqlite3_step(statement) == SQLITE_DONE
    }

    private func backfillStartedHourIfNeeded() throws {
        let selectSQL = """
        SELECT id, started_at
        FROM voice_input_sessions
        WHERE started_hour IS NULL;
        """

        var pendingUpdates: [(id: String, hour: Int)] = []
        do {
            guard let selectStatement = try? prepareStatement(sql: selectSQL) else {
                throw UsageStoreError.statementPrepareFailed(lastSQLiteErrorMessage())
            }
            defer { sqlite3_finalize(selectStatement) }

            while sqlite3_step(selectStatement) == SQLITE_ROW {
                guard let rawID = sqlite3_column_text(selectStatement, 0).map({ String(cString: $0) }) else {
                    continue
                }
                let startedAt = Date(timeIntervalSince1970: sqlite3_column_double(selectStatement, 1))
                pendingUpdates.append((id: rawID, hour: localHour(for: startedAt)))
            }
        }

        guard !pendingUpdates.isEmpty else { return }

        guard sqlite3_exec(database, "BEGIN TRANSACTION;", nil, nil, nil) == SQLITE_OK else {
            throw UsageStoreError.statementExecutionFailed(lastSQLiteErrorMessage())
        }

        let updateSQL = """
        UPDATE voice_input_sessions
        SET started_hour = ?1
        WHERE id = ?2;
        """

        guard let updateStatement = try? prepareStatement(sql: updateSQL) else {
            _ = sqlite3_exec(database, "ROLLBACK;", nil, nil, nil)
            throw UsageStoreError.statementPrepareFailed(lastSQLiteErrorMessage())
        }
        defer { sqlite3_finalize(updateStatement) }

        for update in pendingUpdates {
            sqlite3_reset(updateStatement)
            sqlite3_clear_bindings(updateStatement)
            sqlite3_bind_int(updateStatement, 1, Int32(update.hour))
            sqlite3_bind_text(updateStatement, 2, update.id, -1, transientDestructor)

            guard sqlite3_step(updateStatement) == SQLITE_DONE else {
                _ = sqlite3_exec(database, "ROLLBACK;", nil, nil, nil)
                throw UsageStoreError.statementExecutionFailed(lastSQLiteErrorMessage())
            }
        }

        guard sqlite3_exec(database, "COMMIT;", nil, nil, nil) == SQLITE_OK else {
            _ = sqlite3_exec(database, "ROLLBACK;", nil, nil, nil)
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

    private func localHour(for date: Date) -> Int {
        calendar.component(.hour, from: date)
    }
}

private let transientDestructor = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
