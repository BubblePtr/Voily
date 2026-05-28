import AVFoundation
import XCTest
@testable import Voily

final class SettingsPermissionSnapshotTests: XCTestCase {
    func testMicrophoneAuthorizationStatusMapsToSettingsPermissionState() {
        XCTAssertEqual(SettingsPermissionState.microphone(.authorized), .granted)
        XCTAssertEqual(SettingsPermissionState.microphone(.notDetermined), .needsRequest)
        XCTAssertEqual(SettingsPermissionState.microphone(.denied), .needsSettings)
        XCTAssertEqual(SettingsPermissionState.microphone(.restricted), .restricted)
    }

    func testAccessibilityTrustMapsToSettingsPermissionState() {
        XCTAssertEqual(SettingsPermissionState.accessibility(isTrusted: true), .granted)
        XCTAssertEqual(SettingsPermissionState.accessibility(isTrusted: false), .needsSettings)
    }

    func testSnapshotReportsMissingRequiredPermissions() {
        XCTAssertFalse(
            SettingsPermissionSnapshot(
                microphone: .granted,
                accessibility: .granted
            )
            .hasMissingRequiredPermissions
        )

        XCTAssertTrue(
            SettingsPermissionSnapshot(
                microphone: .needsRequest,
                accessibility: .granted
            )
            .hasMissingRequiredPermissions
        )

        XCTAssertTrue(
            SettingsPermissionSnapshot(
                microphone: .granted,
                accessibility: .needsSettings
            )
            .hasMissingRequiredPermissions
        )
    }

    func testSnapshotReportsKnownMissingRequiredPermissions() {
        XCTAssertFalse(SettingsPermissionSnapshot.unknown.hasKnownMissingRequiredPermissions)

        XCTAssertTrue(
            SettingsPermissionSnapshot(
                microphone: .needsRequest,
                accessibility: .granted
            )
            .hasKnownMissingRequiredPermissions
        )

        XCTAssertTrue(
            SettingsPermissionSnapshot(
                microphone: .granted,
                accessibility: .needsSettings
            )
            .hasKnownMissingRequiredPermissions
        )
    }
}
