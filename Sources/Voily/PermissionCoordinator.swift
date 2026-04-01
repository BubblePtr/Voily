import AppKit
import AVFoundation
import Speech
import ApplicationServices

final class PermissionCoordinator {
    private var accessibilityPollTimer: Timer?
    private var onAccessibilityGranted: (@MainActor () -> Void)?

    init() {}

    deinit {
        accessibilityPollTimer?.invalidate()
    }

    func requestStartupPermissions() {
        AVCaptureDevice.requestAccess(for: .audio) { _ in }
        SFSpeechRecognizer.requestAuthorization { _ in }
    }

    var isAccessibilityTrusted: Bool {
        AXIsProcessTrusted()
    }

    func promptForAccessibilityIfNeeded(force: Bool = false) {
        guard !isAccessibilityTrusted else { return }
        let options = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
    }

    func waitForAccessibilityGrant(onGranted: @escaping @MainActor () -> Void) {
        accessibilityPollTimer?.invalidate()
        onAccessibilityGranted = onGranted
        accessibilityPollTimer = Timer(
            timeInterval: 1,
            target: self,
            selector: #selector(checkAccessibilityGrant),
            userInfo: nil,
            repeats: true
        )

        if let accessibilityPollTimer {
            RunLoop.main.add(accessibilityPollTimer, forMode: .common)
        }
    }

    @objc
    @MainActor
    private func checkAccessibilityGrant() {
        guard isAccessibilityTrusted else { return }

        accessibilityPollTimer?.invalidate()
        accessibilityPollTimer = nil

        let callback = onAccessibilityGranted
        onAccessibilityGranted = nil
        callback?()
    }
}
