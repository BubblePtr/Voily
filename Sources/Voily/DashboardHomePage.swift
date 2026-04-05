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

                TodayPerformanceSection(summary: usageStore.todayASRSummary)

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
private struct TodayPerformanceSection: View {
    let summary: TodayASRPerformanceSummary

    private let columns = [
        GridItem(.flexible(), spacing: 18),
        GridItem(.flexible(), spacing: 18),
    ]

    var body: some View {
        LazyVGrid(columns: columns, spacing: 18) {
            MetricCard(
                title: "今日平均首字延迟",
                value: formatted(summary.averageFirstPartialMs),
                footnote: summary.sessionCount == 0 ? "还没有 partial 数据" : "从开始录音到首次 partial",
                accent: .purple
            )

            MetricCard(
                title: "今日平均最终耗时",
                value: formatted(summary.averageRecognitionMs),
                footnote: summary.sessionCount == 0 ? "还没有识别性能数据" : "按完整转文字链路统计",
                accent: .pink
            )
        }
    }

    private func formatted(_ durationMs: Int) -> String {
        guard durationMs > 0 else { return "0 ms" }
        if durationMs >= 1000 {
            return String(format: "%.2f s", Double(durationMs) / 1000)
        }
        return "\(durationMs) ms"
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

    @State private var showCopyToast = false

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
                        Text(asrMetrics(session))
                    }
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                }

                Spacer()

                Button("复制文本") {
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
        .overlay(alignment: .topTrailing) {
            if showCopyToast {
                CopyToastView()
                    .padding(.top, 12)
                    .padding(.trailing, 12)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .animation(.easeInOut(duration: 0.18), value: showCopyToast)
    }

    private func copyText() {
        guard let text = usageStore.copyableText(for: session.id) else { return }
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
        showCopyToast = true

        Task { @MainActor in
            try? await Task.sleep(for: .seconds(1))
            showCopyToast = false
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

    private func asrMetrics(_ session: HistorySessionRow) -> String {
        let providerName = ASRProvider(rawValue: session.asrProvider)?.displayName ?? session.asrProvider
        var segments = [providerName, sourceLabel(session.asrSource)]
        if let firstPartialMs = session.recognitionFirstPartialMs, firstPartialMs > 0 {
            segments.append("首字 \(recognitionDuration(firstPartialMs))")
        }
        let total = session.recognitionTotalMs > 0 ? recognitionDuration(session.recognitionTotalMs) : "--"
        segments.append("最终 \(total)")
        return segments.joined(separator: " · ")
    }

    private func sourceLabel(_ source: String) -> String {
        switch source {
        case "local":
            return "本地"
        case "speech-fallback":
            return "回退"
        case "system-speech":
            return "系统"
        default:
            return source
        }
    }

    private func recognitionDuration(_ durationMs: Int) -> String {
        if durationMs >= 1000 {
            return String(format: "%.2f s", Double(durationMs) / 1000)
        }
        return "\(durationMs) ms"
    }
}

@available(macOS 26.0, *)
private struct CopyToastView: View {
    var body: some View {
        Text("复制成功")
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(.white)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(
                Capsule(style: .continuous)
                    .fill(Color.black.opacity(0.82))
            )
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
