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

    static let integer: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        return formatter
    }()
}

struct DashboardUsageTimingCurve {
    let controlPoint1X: Double
    let controlPoint1Y: Double
    let controlPoint2X: Double
    let controlPoint2Y: Double
}

/// Matches the website dashboard timing so both surfaces share the same closing slowdown.
enum DashboardUsageMotion {
    static let closingEaseCurve = DashboardUsageTimingCurve(
        controlPoint1X: 0.24,
        controlPoint1Y: 0.72,
        controlPoint2X: 0.22,
        controlPoint2Y: 1
    )
    static let donutRevealStartProgress = 0.02
    static let donutRevealDuration: TimeInterval = 0.96
    static let hourlyBarGrowDuration: TimeInterval = 0.58
    static let hourlyBarDelayStep: TimeInterval = 0.045

    static var donutRevealAnimation: Animation {
        closingEaseAnimation(duration: donutRevealDuration)
    }

    static func closingEaseAnimation(duration: TimeInterval, delay: TimeInterval = 0) -> Animation {
        let curve = closingEaseCurve
        return Animation
            .timingCurve(
                curve.controlPoint1X,
                curve.controlPoint1Y,
                curve.controlPoint2X,
                curve.controlPoint2Y,
                duration: duration
            )
            .delay(delay)
    }

    static func shouldStartDonutReveal(currentProgress: Double) -> Bool {
        currentProgress <= donutRevealStartProgress
    }

    static func shouldStartHourlyBars(isVisible: Bool) -> Bool {
        !isVisible
    }
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

                OverviewMetricsSection(summary: usageStore.lifetimeSummary)

                BehaviorInsightsSection(
                    frontApplications: usageStore.frontApplicationSummaries,
                    hourlySummaries: usageStore.hourlyUsageSummaries,
                    frontApplicationSessionCount: usageStore.frontApplicationSessionCount
                )

                HistoryListSection(
                    usageStore: usageStore,
                    sessions: usageStore.recentSessions,
                    canLoadMore: usageStore.canLoadMoreRecentSessions,
                    onLoadMore: {
                        usageStore.loadMoreRecentSessions()
                    },
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

private struct OverviewMetricsSection: View {
    let summary: LifetimeUsageSummary

    private let columns = [
        GridItem(.flexible(), spacing: 16),
        GridItem(.flexible(), spacing: 16),
        GridItem(.flexible(), spacing: 16),
        GridItem(.flexible(), spacing: 16),
    ]

    var body: some View {
        LazyVGrid(columns: columns, spacing: 16) {
            OverviewMetricCard(
                title: AppLocalization.localized("累计语音时长"),
                value: formattedDuration(summary.totalDurationMs),
                footnote: summary.sessionCount == 0
                    ? AppLocalization.localized("还没有记录")
                    : String(
                        format: AppLocalization.localized("共 %@ 次"),
                        formattedInteger(summary.sessionCount)
                    ),
                accent: .blue
            )

            OverviewMetricCard(
                title: AppLocalization.localized("累计输出字数"),
                value: formattedInteger(summary.totalCharacters),
                footnote: summary.totalCharacters == 0
                    ? AppLocalization.localized("当前没有最终文本产出")
                    : AppLocalization.localized("最终结果文本"),
                accent: .green
            )

            OverviewMetricCard(
                title: AppLocalization.localized("平均每分钟字数"),
                value: formattedInteger(summary.averageCharactersPerMinute),
                footnote: summary.totalDurationMs == 0
                    ? AppLocalization.localized("还没有足够的语音输入数据")
                    : AppLocalization.localized("全部时长折算"),
                accent: .orange
            )

            OverviewMetricCard(
                title: AppLocalization.localized("平均延时"),
                value: formattedRecognitionDuration(summary.averageRecognitionMs),
                footnote: summary.sessionCount == 0
                    ? AppLocalization.localized("还没有识别性能数据")
                    : AppLocalization.localized("录音 -> 转文字"),
                accent: .blue,
                highlighted: true
            )
        }
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

    private func formattedInteger(_ value: Int) -> String {
        DashboardFormatters.integer.string(from: NSNumber(value: value)) ?? "\(value)"
    }
}

private struct OverviewMetricCard: View {
    let title: String
    let value: String
    let footnote: String
    let accent: Color
    var highlighted = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.secondary)

            Text(value)
                .font(.system(size: 28, weight: .semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.75)

            Text(footnote)
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 18)
        .frame(maxWidth: .infinity, minHeight: 128, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(highlighted ? accent.opacity(0.07) : Color(nsColor: .controlBackgroundColor))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(highlighted ? accent.opacity(0.20) : Color.primary.opacity(0.06), lineWidth: 1)
        )
    }
}

private struct BehaviorInsightsSection: View {
    let frontApplications: [FrontApplicationUsageSummary]
    let hourlySummaries: [HourlyUsageSummary]
    let frontApplicationSessionCount: Int

    private let columns = [
        GridItem(.flexible(minimum: 360), spacing: 20, alignment: .top),
        GridItem(.flexible(minimum: 360), spacing: 20, alignment: .top),
    ]

    var body: some View {
        LazyVGrid(columns: columns, spacing: 20) {
            FrontApplicationDistributionSection(
                summaries: frontApplications,
                totalSessionCount: frontApplicationSessionCount
            )

            TimeOfDayDistributionSection(summaries: hourlySummaries)
        }
    }
}

private struct FrontApplicationDistributionSection: View {
    let summaries: [FrontApplicationUsageSummary]
    let totalSessionCount: Int

    var body: some View {
        SettingsCard(
            title: AppLocalization.localized("语音输入场景"),
            subtitle: AppLocalization.localized("按前台 App 统计")
        ) {
            if summaries.isEmpty {
                EmptyApplicationDistributionView()
                    .frame(height: 180)
            } else {
                let displaySummaries = FrontApplicationDistributionDisplay.summaries(
                    from: summaries,
                    totalSessionCount: totalSessionCount,
                    otherName: AppLocalization.localized("其他")
                )
                let displayedTotal = max(totalSessionCount, displaySummaries.reduce(0) { $0 + $1.sessionCount })
                HStack(alignment: .center, spacing: 24) {
                    ApplicationDonutChart(
                        summaries: displaySummaries,
                        totalSessionCount: displayedTotal
                    )
                    .frame(width: 180, height: 180)

                    ApplicationLegendView(
                        summaries: displaySummaries,
                        totalSessionCount: displayedTotal
                    )
                }
                .frame(maxWidth: .infinity, minHeight: 180, alignment: .leading)
            }
        }
    }
}

enum FrontApplicationDistributionDisplay {
    static let otherBundleID = "__other__"
    private static let majorApplicationLimit = 4

    static func summaries(
        from summaries: [FrontApplicationUsageSummary],
        totalSessionCount: Int,
        otherName: String
    ) -> [FrontApplicationUsageSummary] {
        let majorSummaries = Array(summaries.prefix(majorApplicationLimit))
        let majorCount = majorSummaries.reduce(0) { $0 + $1.sessionCount }
        let knownCount = summaries.reduce(0) { $0 + $1.sessionCount }
        let effectiveTotalCount = max(totalSessionCount, knownCount)
        let otherCount = max(0, effectiveTotalCount - majorCount)

        guard otherCount > 0 else { return majorSummaries }
        return majorSummaries + [
            FrontApplicationUsageSummary(
                bundleID: otherBundleID,
                name: otherName,
                sessionCount: otherCount
            ),
        ]
    }
}

private struct EmptyApplicationDistributionView: View {
    var body: some View {
        VStack(alignment: .center, spacing: 8) {
            Image(systemName: "chart.pie")
                .font(.system(size: 28, weight: .semibold))
                .foregroundStyle(.secondary)

            Text(AppLocalization.localized("暂无场景数据"))
                .font(.system(size: 14, weight: .semibold))

            Text(AppLocalization.localized("完成新的语音输入后开始统计"))
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private enum ApplicationDistributionPalette {
    static let colors: [Color] = [
        Color(red: 0.27, green: 0.66, blue: 0.96),
        Color(red: 0.04, green: 0.52, blue: 0.96),
        Color(red: 0.00, green: 0.40, blue: 0.82),
        Color(red: 0.02, green: 0.28, blue: 0.64),
        Color(red: 0.02, green: 0.20, blue: 0.48),
    ]
}

private struct ApplicationDonutChart: View {
    let summaries: [FrontApplicationUsageSummary]
    let totalSessionCount: Int

    private let colors = ApplicationDistributionPalette.colors
    private let ringLineWidth: CGFloat = 15

    @State private var revealProgress = DashboardUsageMotion.donutRevealStartProgress

    var body: some View {
        ZStack {
            Circle()
                .stroke(Color.primary.opacity(0.06), lineWidth: ringLineWidth)

            ZStack {
                ForEach(Array(segments.enumerated()), id: \.offset) { index, segment in
                    DonutSegmentShape(startAngle: segment.startAngle, endAngle: segment.endAngle)
                        .stroke(
                            colors[index % colors.count],
                            style: StrokeStyle(lineWidth: ringLineWidth, lineCap: .round)
                        )
                }
            }
            .mask {
                let revealLineWidth = ringLineWidth + 3
                ZStack {
                    DonutRevealMaskShape(progress: revealProgress)
                        .stroke(
                            Color.white,
                            style: DonutRevealMaskStroke.arcStyle(lineWidth: revealLineWidth)
                        )

                    DonutRevealMovingHeadShape(
                        progress: revealProgress,
                        lineWidth: revealLineWidth
                    )
                    .fill(Color.white)
                }
            }

            if let terminalCapColor = terminalCapColor {
                DonutRevealTerminalCapShape(
                    progress: revealProgress,
                    lineWidth: ringLineWidth
                )
                .fill(terminalCapColor)
            }

            VStack(spacing: 2) {
                Text(formattedInteger(totalSessionCount))
                    .font(.system(size: 24, weight: .semibold))
                Text(AppLocalization.localized("次"))
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(18)
        .onAppear(perform: animateReveal)
        .onChange(of: animationToken) { _, _ in
            animateReveal()
        }
    }

    private var segments: [DonutSegment] {
        guard !summaries.isEmpty else { return [] }
        let total = max(1, totalSessionCount)
        let gap = summaries.count > 1 ? 3.0 : 0.0
        let availableSweep = max(0.0, 360.0 - (Double(summaries.count) * gap))
        var cursor = -90.0
        return summaries.map { summary in
            let sweep = (Double(summary.sessionCount) / Double(total)) * availableSweep
            let segment = DonutSegment(startDegrees: cursor, endDegrees: cursor + sweep)
            cursor += sweep + gap
            return segment
        }
    }

    private var terminalCapColor: Color? {
        guard let colorIndex = DonutTerminalCapStyle.colorIndex(
            forSegmentCount: segments.count,
            paletteCount: colors.count
        ) else {
            return nil
        }

        return colors[colorIndex]
    }

    private var animationToken: String {
        summaries
            .map { "\($0.bundleID):\($0.sessionCount)" }
            .joined(separator: "|") + "|\(totalSessionCount)"
    }

    private func animateReveal() {
        guard DashboardUsageMotion.shouldStartDonutReveal(currentProgress: revealProgress) else { return }

        revealProgress = DashboardUsageMotion.donutRevealStartProgress
        DispatchQueue.main.async {
            withAnimation(DashboardUsageMotion.donutRevealAnimation) {
                revealProgress = 1
            }
        }
    }

    private func formattedInteger(_ value: Int) -> String {
        DashboardFormatters.integer.string(from: NSNumber(value: value)) ?? "\(value)"
    }
}

private struct DonutSegment {
    let startDegrees: Double
    let endDegrees: Double

    var startAngle: Angle {
        .degrees(startDegrees)
    }

    var endAngle: Angle {
        .degrees(endDegrees)
    }
}

struct DonutRevealArc {
    let progress: Double

    var startDegrees: Double {
        -90
    }

    var endDegrees: Double {
        startDegrees - (360 * normalizedProgress)
    }

    var startAngle: Angle {
        .degrees(startDegrees)
    }

    var endAngle: Angle {
        .degrees(endDegrees)
    }

    var drawsClockwise: Bool {
        true
    }

    private var normalizedProgress: Double {
        max(0, min(1, progress))
    }
}

enum DonutRevealMaskStroke {
    static func arcStyle(lineWidth: CGFloat) -> StrokeStyle {
        StrokeStyle(lineWidth: lineWidth, lineCap: .butt)
    }
}

enum DonutTerminalCapStyle {
    static func colorIndex(forSegmentCount segmentCount: Int, paletteCount: Int) -> Int? {
        guard segmentCount > 0, paletteCount > 0 else { return nil }
        return (segmentCount - 1) % paletteCount
    }
}

struct DonutRevealMovingHead {
    let progress: Double
    let lineWidth: CGFloat

    private static let fadeStartProgress = 0.96

    var radius: CGFloat {
        (lineWidth / 2) * radiusScale
    }

    func center(in rect: CGRect) -> CGPoint {
        let arc = DonutRevealArc(progress: progress)
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let radius = min(rect.width, rect.height) / 2
        let radians = arc.endDegrees * .pi / 180

        return CGPoint(
            x: center.x + (cos(radians) * radius),
            y: center.y + (sin(radians) * radius)
        )
    }

    private var radiusScale: CGFloat {
        guard normalizedProgress < 1 else { return 0 }
        guard normalizedProgress > Self.fadeStartProgress else { return 1 }

        let remaining = (1 - normalizedProgress) / (1 - Self.fadeStartProgress)
        return CGFloat(max(0, min(1, remaining)))
    }

    private var normalizedProgress: Double {
        max(0, min(1, progress))
    }
}

struct DonutRevealTerminalCap {
    let progress: Double
    let lineWidth: CGFloat

    private static let appearanceEndProgress = 0.08

    var radius: CGFloat {
        (lineWidth / 2) * radiusScale
    }

    func center(in rect: CGRect) -> CGPoint {
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let radius = min(rect.width, rect.height) / 2
        let radians = DonutRevealArc(progress: 0).startDegrees * .pi / 180

        return CGPoint(
            x: center.x + (cos(radians) * radius),
            y: center.y + (sin(radians) * radius)
        )
    }

    private var radiusScale: CGFloat {
        guard normalizedProgress > 0 else { return 0 }
        guard normalizedProgress < Self.appearanceEndProgress else { return 1 }

        let completed = normalizedProgress / Self.appearanceEndProgress
        return CGFloat(max(0, min(1, completed)))
    }

    private var normalizedProgress: Double {
        max(0, min(1, progress))
    }
}

private struct DonutRevealMaskShape: Shape {
    var progress: Double

    var animatableData: Double {
        get { progress }
        set { progress = newValue }
    }

    func path(in rect: CGRect) -> Path {
        let arc = DonutRevealArc(progress: progress)
        var path = Path()
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let radius = min(rect.width, rect.height) / 2
        path.addArc(
            center: center,
            radius: radius,
            startAngle: arc.startAngle,
            endAngle: arc.endAngle,
            clockwise: arc.drawsClockwise
        )
        return path
    }
}

private struct DonutRevealMovingHeadShape: Shape {
    var progress: Double
    let lineWidth: CGFloat

    var animatableData: Double {
        get { progress }
        set { progress = newValue }
    }

    func path(in rect: CGRect) -> Path {
        let head = DonutRevealMovingHead(progress: progress, lineWidth: lineWidth)
        let radius = head.radius
        guard radius > 0 else { return Path() }

        let center = head.center(in: rect)
        var path = Path()
        path.addEllipse(
            in: CGRect(
                x: center.x - radius,
                y: center.y - radius,
                width: radius * 2,
                height: radius * 2
            )
        )
        return path
    }
}

private struct DonutRevealTerminalCapShape: Shape {
    var progress: Double
    let lineWidth: CGFloat

    var animatableData: Double {
        get { progress }
        set { progress = newValue }
    }

    func path(in rect: CGRect) -> Path {
        let cap = DonutRevealTerminalCap(progress: progress, lineWidth: lineWidth)
        let radius = cap.radius
        guard radius > 0 else { return Path() }

        let center = cap.center(in: rect)
        var path = Path()
        path.addEllipse(
            in: CGRect(
                x: center.x - radius,
                y: center.y - radius,
                width: radius * 2,
                height: radius * 2
            )
        )
        return path
    }
}

private struct DonutSegmentShape: Shape {
    let startAngle: Angle
    let endAngle: Angle

    func path(in rect: CGRect) -> Path {
        var path = Path()
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let radius = min(rect.width, rect.height) / 2
        path.addArc(center: center, radius: radius, startAngle: startAngle, endAngle: endAngle, clockwise: false)
        return path
    }
}

private struct ApplicationLegendView: View {
    let summaries: [FrontApplicationUsageSummary]
    let totalSessionCount: Int

    private let colors = ApplicationDistributionPalette.colors

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(Array(summaries.enumerated()), id: \.element.id) { index, summary in
                HStack(spacing: 10) {
                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                        .fill(colors[index % colors.count])
                        .frame(width: 10, height: 10)

                    Text(summary.name)
                        .font(.system(size: 13))
                        .lineLimit(1)

                    Spacer(minLength: 12)

                    Text(percentText(for: summary.sessionCount))
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(.secondary)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func percentText(for count: Int) -> String {
        let total = max(1, totalSessionCount)
        return "\(Int((Double(count) / Double(total) * 100.0).rounded()))%"
    }
}

private struct TimeOfDayDistributionSection: View {
    let summaries: [HourlyUsageSummary]

    var body: some View {
        SettingsCard(
            title: AppLocalization.localized("使用时段分布"),
            subtitle: AppLocalization.localized("你在什么时段开口")
        ) {
            HourlyUsageBarChart(summaries: summaries)
                .frame(height: 180)
        }
    }
}

private struct HourlyUsageBarChart: View {
    let summaries: [HourlyUsageSummary]

    @State private var barsVisible = false

    var body: some View {
        VStack(spacing: 8) {
            GeometryReader { geometry in
                let buckets = bucketedSummaries
                let maxValue = max(buckets.map(\.sessionCount).max() ?? 0, 1)

                ZStack(alignment: .bottomLeading) {
                    Rectangle()
                        .fill(Color.primary.opacity(0.07))
                        .frame(height: 1)
                        .offset(y: -18)

                    HStack(alignment: .bottom, spacing: 10) {
                        ForEach(Array(buckets.enumerated()), id: \.element.id) { index, bucket in
                            let ratio = CGFloat(bucket.sessionCount) / CGFloat(maxValue)
                            HourlyUsageBar(
                                bucket: bucket,
                                ratio: ratio,
                                availableHeight: geometry.size.height - 32,
                                isVisible: barsVisible,
                                animationDelay: Double(index) * DashboardUsageMotion.hourlyBarDelayStep
                            )
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
                    .padding(.horizontal, 8)
                    .padding(.bottom, 20)
                }
            }

            HStack {
                Text("0")
                Spacer()
                Text("12")
                Spacer()
                Text("24")
            }
            .font(.system(size: 11, weight: .medium))
            .foregroundStyle(.secondary)
        }
        .onAppear(perform: animateBars)
        .onChange(of: summaries) { _, _ in
            animateBars()
        }
    }

    private var bucketedSummaries: [HourlyUsageBucket] {
        stride(from: 0, to: 24, by: 2).map { startHour in
            let sessionCount = summaries
                .filter { $0.hour >= startHour && $0.hour < startHour + 2 }
                .reduce(0) { $0 + $1.sessionCount }
            return HourlyUsageBucket(startHour: startHour, sessionCount: sessionCount)
        }
    }

    private func animateBars() {
        guard DashboardUsageMotion.shouldStartHourlyBars(isVisible: barsVisible) else { return }

        DispatchQueue.main.async {
            barsVisible = true
        }
    }
}

private struct HourlyUsageBar: View {
    let bucket: HourlyUsageBucket
    let ratio: CGFloat
    let availableHeight: CGFloat
    let isVisible: Bool
    let animationDelay: Double

    var body: some View {
        RoundedRectangle(cornerRadius: 4, style: .continuous)
            .fill(Color.blue.opacity(bucket.sessionCount == 0 ? 0.18 : 0.82))
            .frame(height: targetHeight)
            .scaleEffect(x: 1, y: isVisible ? 1 : 0.06, anchor: .bottom)
            .opacity(isVisible ? 1 : 0.35)
            .frame(maxWidth: .infinity, alignment: .bottom)
            .animation(
                DashboardUsageMotion.closingEaseAnimation(
                    duration: DashboardUsageMotion.hourlyBarGrowDuration,
                    delay: animationDelay
                ),
                value: isVisible
            )
            .accessibilityLabel(Text("\(bucket.startHour):00"))
            .accessibilityValue(Text("\(bucket.sessionCount)"))
    }

    private var targetHeight: CGFloat {
        max(8, availableHeight * ratio)
    }
}

private struct HourlyUsageBucket: Identifiable {
    let startHour: Int
    let sessionCount: Int

    var id: Int { startHour }
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
    let canLoadMore: Bool
    let onLoadMore: () -> Void
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

                    if canLoadMore {
                        Button(action: onLoadMore) {
                            Label(AppLocalization.localized("加载更多历史记录"), systemImage: "chevron.down.circle")
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                        .padding(.top, 4)
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
