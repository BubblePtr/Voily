import AppKit
import SwiftUI

@available(macOS 26.0, *)
struct DashboardHomePage: View {
    let usageStore: UsageStore

    private let historyColumns = [
        GridItem(.flexible(minimum: 420), spacing: 20, alignment: .top),
        GridItem(.flexible(minimum: 420), spacing: 20, alignment: .top),
    ]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                SettingsPageHeader(
                    title: "首页",
                    subtitle: "今天的语音输入情况、趋势变化和完整历史都集中放在这里。"
                )

                TodayMetricsSection(summary: usageStore.todaySummary)

                LazyVGrid(columns: historyColumns, spacing: 20) {
                    TrendChartsSection(
                        title: "近 7 天语音输入时长",
                        subtitle: "观察最近一周的活跃度变化",
                        summaries: usageStore.weeklySummaries,
                        value: \.totalDurationMs,
                        accentColor: .blue,
                        formatter: formatDuration
                    )

                    TrendChartsSection(
                        title: "近 7 天输出字数",
                        subtitle: "统计最终结果文本的累计字数",
                        summaries: usageStore.weeklySummaries,
                        value: \.totalCharacters,
                        accentColor: .green,
                        formatter: formatCharacters
                    )
                }

                ActivityHeatmapSection(summaries: usageStore.heatmapSummaries)

                HistoryListSection(usageStore: usageStore, sessions: usageStore.recentSessions)
            }
            .padding(28)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func formatDuration(_ value: Int) -> String {
        let totalSeconds = max(0, value / 1000)
        let minutes = totalSeconds / 60
        let seconds = totalSeconds % 60
        return minutes > 0 ? "\(minutes) 分 \(seconds) 秒" : "\(seconds) 秒"
    }

    private func formatCharacters(_ value: Int) -> String {
        "\(value) 字"
    }
}

@available(macOS 26.0, *)
private struct TodayMetricsSection: View {
    let summary: TodayUsageSummary

    private let columns = [
        GridItem(.flexible(), spacing: 18),
        GridItem(.flexible(), spacing: 18),
        GridItem(.flexible(), spacing: 18),
    ]

    var body: some View {
        LazyVGrid(columns: columns, spacing: 18) {
            MetricCard(
                title: "今日语音输入时长",
                value: formattedDuration(summary.totalDurationMs),
                footnote: summary.sessionCount == 0 ? "今天还没有记录" : "共 \(summary.sessionCount) 次语音输入",
                accent: .blue
            )

            MetricCard(
                title: "今日输出字数",
                value: "\(summary.totalCharacters)",
                footnote: summary.totalCharacters == 0 ? "当前没有最终文本产出" : "按最终结果文本统计",
                accent: .green
            )

            MetricCard(
                title: "平均每次输出字数",
                value: averageCharacters(summary: summary),
                footnote: "帮助判断单次输入的密度",
                accent: .orange
            )
        }
    }

    private func averageCharacters(summary: TodayUsageSummary) -> String {
        guard summary.sessionCount > 0 else { return "0" }
        return "\(summary.totalCharacters / summary.sessionCount)"
    }

    private func formattedDuration(_ durationMs: Int) -> String {
        let totalSeconds = max(0, durationMs / 1000)
        let hours = totalSeconds / 3600
        let minutes = (totalSeconds % 3600) / 60
        let seconds = totalSeconds % 60

        if hours > 0 {
            return "\(hours)h \(minutes)m"
        }
        if minutes > 0 {
            return "\(minutes)m \(seconds)s"
        }
        return "\(seconds)s"
    }
}

@available(macOS 26.0, *)
private struct MetricCard: View {
    let title: String
    let value: String
    let footnote: String
    let accent: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(accent.opacity(0.12))
                .frame(width: 42, height: 42)
                .overlay(
                    Circle()
                        .fill(accent)
                        .frame(width: 10, height: 10)
                )

            Text(title)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(.secondary)

            Text(value)
                .font(.system(size: 34, weight: .semibold))

            Text(footnote)
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
        }
        .padding(20)
        .frame(maxWidth: .infinity, minHeight: 176, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(Color(nsColor: .controlBackgroundColor))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(Color.primary.opacity(0.06), lineWidth: 1)
        )
    }
}

@available(macOS 26.0, *)
private struct TrendChartsSection: View {
    let title: String
    let subtitle: String
    let summaries: [DailyUsageSummary]
    let value: KeyPath<DailyUsageSummary, Int>
    let accentColor: Color
    let formatter: (Int) -> String

    var body: some View {
        SettingsCard(title: title, subtitle: subtitle) {
            VStack(alignment: .leading, spacing: 18) {
                SparklineChart(summaries: summaries, value: value, accentColor: accentColor)
                    .frame(height: 120)

                HStack(alignment: .bottom) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("最近一天")
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                        Text(formatter(summaries.last?[keyPath: value] ?? 0))
                            .font(.system(size: 18, weight: .semibold))
                    }

                    Spacer()

                    VStack(alignment: .trailing, spacing: 4) {
                        Text("近 7 天累计")
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                        Text(formatter(summaries.reduce(0) { $0 + $1[keyPath: value] }))
                            .font(.system(size: 18, weight: .semibold))
                    }
                }
            }
        }
    }
}

@available(macOS 26.0, *)
private struct SparklineChart: View {
    let summaries: [DailyUsageSummary]
    let value: KeyPath<DailyUsageSummary, Int>
    let accentColor: Color

    var body: some View {
        GeometryReader { geometry in
            let maxValue = max(summaries.map { $0[keyPath: value] }.max() ?? 0, 1)
            let count = max(summaries.count, 1)
            let stepX = count > 1 ? geometry.size.width / CGFloat(count - 1) : geometry.size.width

            ZStack(alignment: .bottomLeading) {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(accentColor.opacity(0.05))

                ForEach(0..<4, id: \.self) { index in
                    Rectangle()
                        .fill(Color.primary.opacity(0.05))
                        .frame(height: 1)
                        .offset(y: -CGFloat(index) * geometry.size.height / 4)
                }

                Path { path in
                    guard !summaries.isEmpty else { return }
                    for (index, summary) in summaries.enumerated() {
                        let normalized = CGFloat(summary[keyPath: value]) / CGFloat(maxValue)
                        let point = CGPoint(
                            x: CGFloat(index) * stepX,
                            y: geometry.size.height - (normalized * (geometry.size.height - 18)) - 9
                        )

                        if index == 0 {
                            path.move(to: point)
                        } else {
                            path.addLine(to: point)
                        }
                    }
                }
                .stroke(accentColor, style: StrokeStyle(lineWidth: 3, lineCap: .round, lineJoin: .round))

                HStack(alignment: .bottom, spacing: 0) {
                    ForEach(summaries) { summary in
                        Text(shortDate(summary.date))
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                .padding(.top, geometry.size.height + 6)
            }
        }
        .padding(.bottom, 18)
    }

    private func shortDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "M/d"
        return formatter.string(from: date)
    }
}

@available(macOS 26.0, *)
private struct ActivityHeatmapSection: View {
    let summaries: [DailyUsageSummary]

    private let columnCount = 12

    var body: some View {
        SettingsCard(title: "活跃热力图", subtitle: "最近 12 周按每天总输入时长着色") {
            VStack(alignment: .leading, spacing: 16) {
                if summaries.isEmpty {
                    Text("还没有历史记录，后续语音输入会自动出现在这里。")
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                } else {
                    let columns = chunkedSummaries
                    let maxDuration = max(summaries.map(\.totalDurationMs).max() ?? 0, 1)

                    HStack(alignment: .top, spacing: 6) {
                        VStack(alignment: .leading, spacing: 8) {
                            ForEach(["一", "二", "三", "四", "五", "六", "日"], id: \.self) { label in
                                Text(label)
                                    .font(.system(size: 11, weight: .medium))
                                    .foregroundStyle(.secondary)
                                    .frame(height: 14)
                            }
                        }
                        .padding(.top, 2)

                        HStack(alignment: .top, spacing: 6) {
                            ForEach(Array(columns.enumerated()), id: \.offset) { _, week in
                                VStack(spacing: 6) {
                                    ForEach(week.indices, id: \.self) { index in
                                        let summary = week[index]
                                        HeatmapCell(
                                            intensity: Double(summary.totalDurationMs) / Double(maxDuration),
                                            tooltip: tooltip(for: summary)
                                        )
                                    }
                                }
                            }
                        }
                    }

                    Text("颜色越深表示当天语音输入时长越高。")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private var chunkedSummaries: [[DailyUsageSummary]] {
        let padded = summaries.paddedToWeekday()
        return stride(from: 0, to: padded.count, by: 7).map { start in
            Array(padded[start..<min(start + 7, padded.count)])
        }
    }

    private func tooltip(for summary: DailyUsageSummary) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        return "\(formatter.string(from: summary.date)) · \(summary.totalDurationMs / 1000) 秒 · \(summary.totalCharacters) 字"
    }
}

@available(macOS 26.0, *)
private struct HeatmapCell: View {
    let intensity: Double
    let tooltip: String

    var body: some View {
        RoundedRectangle(cornerRadius: 4, style: .continuous)
            .fill(Color.accentColor.opacity(max(0.08, min(0.95, intensity * 0.9))))
            .frame(width: 14, height: 14)
            .help(tooltip)
    }
}

@available(macOS 26.0, *)
private struct HistoryListSection: View {
    let usageStore: UsageStore
    let sessions: [HistorySessionRow]

    var body: some View {
        SettingsCard(title: "历史记录", subtitle: "按时间倒序展示，支持复制最终结果文本") {
            if sessions.isEmpty {
                Text("还没有历史记录。完成一次语音输入后，这里会自动出现。")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
            } else {
                VStack(spacing: 12) {
                    ForEach(sessions) { session in
                        HistorySessionRowView(usageStore: usageStore, session: session)
                    }
                }
            }
        }
    }
}

@available(macOS 26.0, *)
private struct HistorySessionRowView: View {
    let usageStore: UsageStore
    let session: HistorySessionRow

    @State private var copied = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 8) {
                        Text(timestamp(session.endedAt))
                            .font(.system(size: 13, weight: .semibold))

                        StatusPill(session: session)

                        if session.refinementApplied {
                            SmallPill(text: "已润色")
                        }
                    }

                    HStack(spacing: 12) {
                        Text(duration(session.durationMs))
                        Text("\(session.characterCount) 字")
                        Text(languageName(for: session.languageCode))
                    }
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                }

                Spacer()

                Button(copied ? "已复制" : "复制文本") {
                    copyText()
                }
                .buttonStyle(.bordered)
            }

            Text(session.finalText)
                .font(.system(size: 13))
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(12)
                .background(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(Color(nsColor: .textBackgroundColor))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(Color.primary.opacity(0.05), lineWidth: 1)
                )
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color.primary.opacity(0.03))
        )
    }

    private func copyText() {
        guard let text = usageStore.copyableText(for: session.id) else { return }
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
        copied = true

        Task { @MainActor in
            try? await Task.sleep(for: .seconds(1))
            copied = false
        }
    }

    private func timestamp(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }

    private func duration(_ durationMs: Int) -> String {
        "\(max(0, durationMs / 1000)) 秒"
    }

    private func languageName(for code: String) -> String {
        SupportedLanguage(rawValue: code)?.displayName ?? code
    }
}

@available(macOS 26.0, *)
private struct StatusPill: View {
    let session: HistorySessionRow

    var body: some View {
        SmallPill(text: label, tint: tint)
    }

    private var label: String {
        switch session.injectionSucceeded {
        case .some(true):
            return "已注入"
        case .some(false):
            return "注入失败"
        case .none:
            return "处理中"
        }
    }

    private var tint: Color {
        switch session.injectionSucceeded {
        case .some(true):
            return .green
        case .some(false):
            return .red
        case .none:
            return .orange
        }
    }
}

@available(macOS 26.0, *)
private struct SmallPill: View {
    let text: String
    var tint: Color = .secondary

    var body: some View {
        Text(text)
            .font(.system(size: 11, weight: .medium))
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(
                Capsule()
                    .fill(tint.opacity(0.12))
            )
            .foregroundStyle(tint)
    }
}

private extension Array where Element == DailyUsageSummary {
    func paddedToWeekday() -> [DailyUsageSummary] {
        guard let firstDate = first?.date else { return self }

        let calendar = Calendar.autoupdatingCurrent
        let weekday = calendar.component(.weekday, from: firstDate)
        let mondayAlignedOffset = (weekday + 5) % 7

        guard mondayAlignedOffset > 0 else { return self }

        let prefixDays = (1...mondayAlignedOffset).reversed().compactMap { offset -> DailyUsageSummary? in
            guard let date = calendar.date(byAdding: .day, value: -offset, to: firstDate) else {
                return nil
            }

            return DailyUsageSummary(date: date, totalDurationMs: 0, totalCharacters: 0, sessionCount: 0)
        }

        return prefixDays + self
    }
}
