import XCTest
@testable import Voily

@MainActor
final class AccessibilityPermissionGuideTests: XCTestCase {
    func testOpenUsesCurrentAppBundleWithoutPromptingForAXTracking() {
        let appURL = URL(fileURLWithPath: "/Applications/Voily.app")
        var openedRequest: AccessibilityPermissionGuide.Request?
        let guide = AccessibilityPermissionGuide(appBundleURL: appURL) { request in
            openedRequest = request
            return nil
        }

        guide.open()

        XCTAssertEqual(
            openedRequest,
            AccessibilityPermissionGuide.Request(
                suggestedAppURLs: [appURL.standardizedFileURL],
                promptForAccessibilityTrust: false
            )
        )
    }
}
