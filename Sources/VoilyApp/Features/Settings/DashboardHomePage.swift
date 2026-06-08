import AppKit
import SwiftUI
import VoilyCore

private enum DashboardFormatters {
    static let shortDate: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "M/d"
        return formatter
    }()

    static let timestamp: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter
    }()
}

struct DashboardHomePage: View {
    let usageStore: UsageStore
    let permissionActions: SettingsPermissionActions
    let onOpenInputSettings: () -> Void

    @State private var showCopyToast = false
    @State private var copyToastTask: Task<Void, Never>?

    private let historyColumns = [
        GridItem(.flexible(minimum: 360), spacing: 20, alignment: .top),
        GridItem(.flexible(minimum: 360), spacing: 20, alignment: .top),
    ]

    init(
        usageStore: UsageStore,
        permissionActions: SettingsPermissionActions = .preview(),
        onOpenInputSettings: @escaping () -> Void = {}
    ) {
        self.usageStore = usageStore
        self.permissionActions = permissionActions
        self.onOpenInputSettings = onOpenInputSettings
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                DashboardPermissionStatusHeader(
                    actions: permissionActions,
                    onOpenInputSettings: onOpenInputSettings
                )

                TodayMetricsSection(
                    summary: usageStore.todaySummary,
                    asrSummary: usageStore.todayASRSummary
                )

                LazyVGrid(columns: historyColumns, spacing: 20) {
                    TrendChartsSection(
                        title: AppLocalization.localized("近 7 天语音输入时长"),
                        subtitle: AppLocalization.localized("观察最近一周的活跃度变化"),
                        summaries: usageStore.weeklySummaries,
                        value: \.totalDurationMs,
                        accentColor: .blue,
                        formatter: formatDuration
                    )

                    TrendChartsSection(
                        title: AppLocalization.localized("近 7 天输出字数"),
                        subtitle: AppLocalization.localized("统计最终结果文本的累计字数"),
                        summaries: usageStore.weeklySummaries,
                        value: \.totalCharacters,
                        accentColor: .green,
                        formatter: formatCharacters
                    )
                }

                HistoryListSection(
                    usageStore: usageStore,
                    sessions: usageStore.recentSessions,
                    onCopySuccess: {
                        copyToastTask?.cancel()
                        withAnimation(.easeInOut(duration: 0.18)) {
                            showCopyToast = true
                        }

                        copyToastTask = Task { @MainActor in
                            try? await Task.sleep(for: .seconds(1.2))
                            withAnimation(.easeInOut(duration: 0.18)) {
                                showCopyToast = false
                            }
                        }
                    }
                )
            }
            .padding(28)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .scrollIndicators(.hidden)
        .overlay(alignment: .bottom) {
            if showCopyToast {
                CopyToastView()
                    .padding(.bottom, 24)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.easeInOut(duration: 0.18), value: showCopyToast)
    }

    private func formatDuration(_ value: Int) -> String {
        let totalSeconds = max(0, value / 1000)
        let minutes = totalSeconds / 60
        let seconds = totalSeconds % 60
        if minutes > 0 {
            return String(
                format: AppLocalization.localized("%@ 分 %@ 秒"),
                "\(minutes)",
                "\(seconds)"
            )
        }
        return String(format: AppLocalization.localized("%@ 秒"), "\(seconds)")
    }

    private func formatCharacters(_ value: Int) -> String {
        String(format: AppLocalization.localized("%@ 字"), "\(value)")
    }
}

private struct DashboardPermissionStatusHeader: View {
    let actions: SettingsPermissionActions
    let onOpenInputSettings: () -> Void

    @Environment(\.scenePhase) private var scenePhase
    @State private var snapshot = SettingsPermissionSnapshot.unknown

    var body: some View {
        VStack(alignment: .trailing, spacing: snapshot.hasKnownMissingRequiredPermissions ? 12 : 0) {
            HStack {
                Spacer(minLength: 0)
                CompactSettingsPermissionStatusCapsules(snapshot: snapshot)
            }

            if snapshot.hasKnownMissingRequiredPermissions {
                DashboardPermissionReminderBanner(
                    snapshot: snapshot,
                    onOpenInputSettings: onOpenInputSettings
                )
            }
        }
        .frame(maxWidth: .infinity, alignment: .trailing)
        .onAppear(perform: refresh)
        .onChange(of: scenePhase) { _, phase in
            guard phase == .active else { return }
            refresh()
        }
        .task(id: scenePhase) {
            guard scenePhase == .active else { return }
            await refreshWhileVisible()
        }
    }

    @MainActor
    private func refresh() {
        snapshot = actions.loadSnapshot()
    }

    @MainActor
    private func refreshWhileVisible() async {
        while !Task.isCancelled {
            refresh()

            do {
                try await Task.sleep(for: .seconds(2))
            } catch {
                return
            }
        }
    }
}

private struct DashboardPermissionReminderBanner: View {
    let snapshot: SettingsPermissionSnapshot
    let onOpenInputSettings: () -> Void

    var body: some View {
        HStack(alignment: .center, spacing: 14) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(.orange)
                .frame(width: 34, height: 34)
                .background(
                    Circle()
                        .fill(Color.orange.opacity(0.12))
                )

            VStack(alignment: .leading, spacing: 4) {
                Text(AppLocalization.localized("需要完成系统权限授权"))
                    .font(.system(size: 14, weight: .semibold))

                Text(bannerDetail)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 16)

            Button(AppLocalization.localized("去输入设置"), action: onOpenInputSettings)
                .controlSize(.small)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color.orange.opacity(0.08))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(Color.orange.opacity(0.24), lineWidth: 1)
        )
    }

    private var bannerDetail: String {
        switch (snapshot.microphone.isGranted, snapshot.accessibility.isGranted) {
        case (false, false):
            return AppLocalization.localized("麦克风和辅助功能权限未就绪，请到输入设置页处理。")
        case (false, true):
            return AppLocalization.localized("麦克风权限未就绪，请到输入设置页处理。")
        case (true, false):
            return AppLocalization.localized("辅助功能权限未就绪，请到输入设置页处理。")
        case (true, true):
            return ""
        }
    }
}

private struct TodayMetricsSection: View {
    let summary: TodayUsageSummary
    let asrSummary: TodayASRPerformanceSummary

    private let columns = [
        GridItem(.flexible(), spacing: 16),
        GridItem(.flexible(), spacing: 16),
        GridItem(.flexible(), spacing: 16),
        GridItem(.flexible(), spacing: 16),
    ]

    var body: some View {
        LazyVGrid(columns: columns, spacing: 16) {
            MetricCard(
                title: AppLocalization.localized("今日语音输入时长"),
                value: formattedDuration(summary.totalDurationMs),
                footnote: summary.sessionCount == 0
                    ? AppLocalization.localized("今天还没有记录")
                    : String(
                        format: AppLocalization.localized("共 %@ 次语音输入"),
                        "\(summary.sessionCount)"
                    ),
                accent: .blue
            )

            MetricCard(
                title: AppLocalization.localized("今日输出字数"),
                value: "\(summary.totalCharacters)",
                footnote: summary.totalCharacters == 0
                    ? AppLocalization.localized("当前没有最终文本产出")
                    : AppLocalization.localized("按最终结果文本统计"),
                accent: .green
            )

            MetricCard(
                title: AppLocalization.localized("平均每分钟字数"),
                value: averageCharactersPerMinute(summary: summary),
                footnote: summary.totalDurationMs == 0
                    ? AppLocalization.localized("还没有足够的语音输入数据")
                    : AppLocalization.localized("按今日语音输入时长折算"),
                accent: .orange
            )
            MetricCard(
                title: AppLocalization.localized("今日平均延时"),
                value: formattedRecognitionDuration(asrSummary.averageRecognitionMs),
                footnote: asrSummary.sessionCount == 0
                    ? AppLocalization.localized("还没有识别性能数据")
                    : AppLocalization.localized("从结束录音到转文字完成"),
                accent: .pink
            )
        }
    }

    private func averageCharactersPerMinute(summary: TodayUsageSummary) -> String {
        guard summary.totalDurationMs > 0, summary.totalCharacters > 0 else { return "0" }
        let charactersPerMinute = (Double(summary.totalCharacters) * 60_000.0) / Double(summary.totalDurationMs)
        return "\(Int(charactersPerMinute.rounded()))"
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
        return String(format: AppLocalization.localized("%@ 秒"), "\(seconds)")
    }

    private func formattedRecognitionDuration(_ durationMs: Int) -> String {
        guard durationMs > 0 else { return "0 ms" }
        if durationMs >= 1000 {
            return String(format: "%.2f s", Double(durationMs) / 1000)
        }
        return "\(durationMs) ms"
    }
}

private struct MetricCard: View {
    let title: String
    let value: String
    let footnote: String
    let accent: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(accent.opacity(0.12))
                .frame(width: 40, height: 40)
                .overlay(
                    Circle()
                        .fill(accent)
                        .frame(width: 10, height: 10)
                )

            Text(title)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(.secondary)

            Text(value)
                .font(.system(size: 30, weight: .semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.75)

            Text(footnote)
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
        }
        .padding(18)
        .frame(maxWidth: .infinity, minHeight: 152, alignment: .leading)
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
                        Text(AppLocalization.localized("最近一天"))
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                        Text(formatter(summaries.last?[keyPath: value] ?? 0))
                            .font(.system(size: 18, weight: .semibold))
                    }

                    Spacer()

                    VStack(alignment: .trailing, spacing: 4) {
                        Text(AppLocalization.localized("近 7 天累计"))
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
        DashboardFormatters.shortDate.string(from: date)
    }
}

private struct HistoryListSection: View {
    let usageStore: UsageStore
    let sessions: [HistorySessionRow]
    let onCopySuccess: () -> Void

    var body: some View {
        SettingsCard(title: AppLocalization.localized("历史记录"), subtitle: AppLocalization.localized("按时间倒序展示，支持复制最终结果文本")) {
            if sessions.isEmpty {
                Text(AppLocalization.localized("还没有历史记录。完成一次语音输入后，这里会自动出现。"))
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
            } else {
                LazyVStack(spacing: 12) {
                    ForEach(sessions) { session in
                        HistorySessionRowView(
                            usageStore: usageStore,
                            session: session,
                            onCopySuccess: onCopySuccess
                        )
                    }
                }
            }
        }
    }
}

private struct HistorySessionRowView: View {
    let usageStore: UsageStore
    let session: HistorySessionRow
    let onCopySuccess: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 8) {
                        Text(timestamp(session.endedAt))
                            .font(.system(size: 13, weight: .semibold))

                        StatusPill(session: session)

                        if session.refinementApplied {
                            SmallPill(text: AppLocalization.localized("已润色"))
                        }
                    }

                    HStack(spacing: 12) {
                        Text(duration(session.durationMs))
                        Text(String(format: AppLocalization.localized("%@ 字"), "\(session.characterCount)"))
                        Text(languageName(for: session.languageCode))
                        Text(asrMetrics(session))
                    }
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                }

                Spacer()

                Button(AppLocalization.localized("复制文本")) {
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
        onCopySuccess()
    }

    private func timestamp(_ date: Date) -> String {
        DashboardFormatters.timestamp.string(from: date)
    }

    private func duration(_ durationMs: Int) -> String {
        String(format: AppLocalization.localized("%@ 秒"), "\(max(0, durationMs / 1000))")
    }

    private func languageName(for code: String) -> String {
        SupportedLanguage(rawValue: code)?.displayName ?? code
    }

    private func asrMetrics(_ session: HistorySessionRow) -> String {
        let providerName = ASRProvider(rawValue: session.asrProvider)?.displayName ?? session.asrProvider
        var segments = [providerName, sourceLabel(session.asrSource)]
        let total = session.recognitionTotalMs > 0 ? recognitionDuration(session.recognitionTotalMs) : "--"
        segments.append(String(format: AppLocalization.localized("延时 %@"), total))
        return segments.joined(separator: " · ")
    }

    private func sourceLabel(_ source: String) -> String {
        switch source {
        case "local":
            return AppLocalization.localized("本地")
        case "speech-fallback":
            return AppLocalization.localized("回退")
        case "system-speech":
            return AppLocalization.localized("系统")
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

private struct CopyToastView: View {
    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(.green)

            Text(AppLocalization.localized("复制成功"))
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.white)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(
            Capsule(style: .continuous)
                .fill(Color.black.opacity(0.86))
        )
        .shadow(color: Color.black.opacity(0.18), radius: 14, x: 0, y: 8)
    }
}

private struct StatusPill: View {
    let session: HistorySessionRow

    var body: some View {
        SmallPill(text: label, tint: tint)
    }

    private var label: String {
        switch session.injectionSucceeded {
        case .some(true):
            return AppLocalization.localized("已注入")
        case .some(false):
            return AppLocalization.localized("注入失败")
        case .none:
            return AppLocalization.localized("处理中")
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
