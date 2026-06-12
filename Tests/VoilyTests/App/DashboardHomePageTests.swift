import XCTest
import SwiftUI
import VoilyCore
@testable import Voily

@MainActor
final class DashboardHomePageTests: XCTestCase {
    func testFrontApplicationDisplaySummariesKeepFourMajorAppsAndCollapseTheRestIntoOther() {
        let summaries = [
            FrontApplicationUsageSummary(bundleID: "com.example.a", name: "Alpha", sessionCount: 8),
            FrontApplicationUsageSummary(bundleID: "com.example.b", name: "Beta", sessionCount: 6),
            FrontApplicationUsageSummary(bundleID: "com.example.c", name: "Gamma", sessionCount: 4),
            FrontApplicationUsageSummary(bundleID: "com.example.d", name: "Delta", sessionCount: 3),
            FrontApplicationUsageSummary(bundleID: "com.example.e", name: "Epsilon", sessionCount: 2),
            FrontApplicationUsageSummary(bundleID: "com.example.f", name: "Zeta", sessionCount: 1),
        ]

        let displaySummaries = FrontApplicationDistributionDisplay.summaries(
            from: summaries,
            totalSessionCount: 27,
            otherName: "Other"
        )

        XCTAssertEqual(
            displaySummaries,
            [
                FrontApplicationUsageSummary(bundleID: "com.example.a", name: "Alpha", sessionCount: 8),
                FrontApplicationUsageSummary(bundleID: "com.example.b", name: "Beta", sessionCount: 6),
                FrontApplicationUsageSummary(bundleID: "com.example.c", name: "Gamma", sessionCount: 4),
                FrontApplicationUsageSummary(bundleID: "com.example.d", name: "Delta", sessionCount: 3),
                FrontApplicationUsageSummary(bundleID: "__other__", name: "Other", sessionCount: 6),
            ]
        )
    }

    func testFrontApplicationDisplaySummariesUseHiddenTotalForOtherWhenStoreAlreadyLimitsInput() {
        let summaries = [
            FrontApplicationUsageSummary(bundleID: "com.example.a", name: "Alpha", sessionCount: 5),
            FrontApplicationUsageSummary(bundleID: "com.example.b", name: "Beta", sessionCount: 4),
            FrontApplicationUsageSummary(bundleID: "com.example.c", name: "Gamma", sessionCount: 3),
            FrontApplicationUsageSummary(bundleID: "com.example.d", name: "Delta", sessionCount: 2),
        ]

        let displaySummaries = FrontApplicationDistributionDisplay.summaries(
            from: summaries,
            totalSessionCount: 17,
            otherName: "Other"
        )

        XCTAssertEqual(
            displaySummaries,
            [
                FrontApplicationUsageSummary(bundleID: "com.example.a", name: "Alpha", sessionCount: 5),
                FrontApplicationUsageSummary(bundleID: "com.example.b", name: "Beta", sessionCount: 4),
                FrontApplicationUsageSummary(bundleID: "com.example.c", name: "Gamma", sessionCount: 3),
                FrontApplicationUsageSummary(bundleID: "com.example.d", name: "Delta", sessionCount: 2),
                FrontApplicationUsageSummary(bundleID: "__other__", name: "Other", sessionCount: 3),
            ]
        )
    }

    func testDonutRevealArcPushesCounterclockwiseFromTheTop() {
        XCTAssertEqual(DonutRevealArc(progress: 0).startDegrees, -90)
        XCTAssertEqual(DonutRevealArc(progress: 0).endDegrees, -90)
        XCTAssertEqual(DonutRevealArc(progress: 0.25).endDegrees, -180)
        XCTAssertEqual(DonutRevealArc(progress: 1).endDegrees, -450)
        XCTAssertTrue(DonutRevealArc(progress: 1).drawsClockwise)
    }

    func testDonutRevealMaskUsesRoundedMovingHeadAndPersistentTerminalCap() {
        let style = DonutRevealMaskStroke.arcStyle(lineWidth: 18)
        let visibleHead = DonutRevealMovingHead(progress: 0.5, lineWidth: 18)
        let fadingHead = DonutRevealMovingHead(progress: 0.98, lineWidth: 18)
        let completedHead = DonutRevealMovingHead(progress: 1, lineWidth: 18)
        let hiddenTerminalCap = DonutRevealTerminalCap(progress: 0, lineWidth: 18)
        let growingTerminalCap = DonutRevealTerminalCap(progress: 0.04, lineWidth: 18)
        let visibleTerminalCap = DonutRevealTerminalCap(progress: 0.5, lineWidth: 18)
        let completedTerminalCap = DonutRevealTerminalCap(progress: 1, lineWidth: 18)
        let completedTerminalCapCenter = completedTerminalCap.center(
            in: CGRect(x: 0, y: 0, width: 100, height: 100)
        )

        XCTAssertEqual(style.lineCap, .butt)
        XCTAssertEqual(visibleHead.radius, 9, accuracy: 0.001)
        XCTAssertGreaterThan(fadingHead.radius, 0)
        XCTAssertLessThan(fadingHead.radius, visibleHead.radius)
        XCTAssertEqual(completedHead.radius, 0, accuracy: 0.001)
        XCTAssertEqual(hiddenTerminalCap.radius, 0, accuracy: 0.001)
        XCTAssertGreaterThan(growingTerminalCap.radius, 0)
        XCTAssertLessThan(growingTerminalCap.radius, visibleTerminalCap.radius)
        XCTAssertEqual(visibleTerminalCap.radius, 9, accuracy: 0.001)
        XCTAssertEqual(completedTerminalCap.radius, 9, accuracy: 0.001)
        XCTAssertEqual(completedTerminalCapCenter.x, 50, accuracy: 0.001)
        XCTAssertEqual(completedTerminalCapCenter.y, 0, accuracy: 0.001)
    }

    func testDonutTerminalCapUsesTheLastVisibleSegmentColor() {
        XCTAssertNil(DonutTerminalCapStyle.colorIndex(forSegmentCount: 0, paletteCount: 5))
        XCTAssertEqual(DonutTerminalCapStyle.colorIndex(forSegmentCount: 1, paletteCount: 5), 0)
        XCTAssertEqual(DonutTerminalCapStyle.colorIndex(forSegmentCount: 5, paletteCount: 5), 4)
        XCTAssertEqual(DonutTerminalCapStyle.colorIndex(forSegmentCount: 6, paletteCount: 5), 0)
    }

    func testUsageDashboardAnimationsUseSharedClosingEase() {
        let curve = DashboardUsageMotion.closingEaseCurve

        XCTAssertEqual(curve.controlPoint1X, 0.24, accuracy: 0.001)
        XCTAssertEqual(curve.controlPoint1Y, 0.72, accuracy: 0.001)
        XCTAssertEqual(curve.controlPoint2X, 0.22, accuracy: 0.001)
        XCTAssertEqual(curve.controlPoint2Y, 1, accuracy: 0.001)
        XCTAssertGreaterThan(curve.controlPoint1Y, curve.controlPoint1X)
        XCTAssertGreaterThan(curve.controlPoint2Y, curve.controlPoint2X)
        XCTAssertEqual(DashboardUsageMotion.donutRevealDuration, 0.96, accuracy: 0.001)
        XCTAssertEqual(DashboardUsageMotion.hourlyBarGrowDuration, 0.58, accuracy: 0.001)
        XCTAssertEqual(DashboardUsageMotion.hourlyBarDelayStep, 0.045, accuracy: 0.001)
    }
}
