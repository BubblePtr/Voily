import XCTest
@testable import Voily

final class AppUpdaterConfigurationTests: XCTestCase {
    func testAppVersionInfoFormatsVersionAndBuildNumber() {
        let info = AppVersionInfo(
            displayName: "Voily",
            shortVersion: "0.1.3",
            buildNumber: "3"
        )

        XCTAssertEqual(info.versionSummary, "0.1.3 (3)")
    }

    func testConfigurationIsNotReadyWithoutPublicKey() {
        let configuration = SparkleUpdaterConfiguration(
            feedURLString: "https://github.com/BubblePtr/Voily/releases/latest/download/appcast.xml",
            publicEDKey: ""
        )

        XCTAssertFalse(configuration.isReady)
    }

    func testConfigurationIsNotReadyWithUnresolvedBuildSettingPublicKey() {
        let configuration = SparkleUpdaterConfiguration(
            feedURLString: "https://github.com/BubblePtr/Voily/releases/latest/download/appcast.xml",
            publicEDKey: "$(VOILY_SPARKLE_PUBLIC_ED_KEY)"
        )

        XCTAssertFalse(configuration.isReady)
    }

    func testConfigurationIsReadyWithHTTPSFeedAndPublicKey() {
        let configuration = SparkleUpdaterConfiguration(
            feedURLString: "https://github.com/BubblePtr/Voily/releases/latest/download/appcast.xml",
            publicEDKey: "MDEyMzQ1Njc4OWFiY2RlZjAxMjM0NTY3ODlhYmNkZWY="
        )

        XCTAssertTrue(configuration.isReady)
    }
}
