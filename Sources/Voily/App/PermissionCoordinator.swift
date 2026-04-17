import AppKit
import AVFoundation
import Speech
import ApplicationServices

@MainActor
final class PermissionCoordinator {
    private var accessibilityPollTimer: Timer?
    private var onAccessibilityGranted: (@MainActor () -> Void)?

    init() {}

    var isAccessibilityTrusted: Bool {
        AXIsProcessTrusted()
    }

    var isMicrophoneAuthorized: Bool {
        AVCaptureDevice.authorizationStatus(for: .audio) == .authorized
    }

    var isSpeechRecognitionAuthorized: Bool {
        SFSpeechRecognizer.authorizationStatus() == .authorized
    }

    var microphoneAuthorizationStatus: AVAuthorizationStatus {
        AVCaptureDevice.authorizationStatus(for: .audio)
    }

    var speechRecognitionAuthorizationStatus: SFSpeechRecognizerAuthorizationStatus {
        SFSpeechRecognizer.authorizationStatus()
    }

    func promptForAccessibilityIfNeeded(force: Bool = false) {
        guard !isRunningUnderXCTest() else {
            debugLog("PermissionCoordinator.promptForAccessibilityIfNeeded skipped under XCTest")
            return
        }
        guard !isAccessibilityTrusted else { return }
        let options = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
    }

    func waitForAccessibilityGrant(onGranted: @escaping @MainActor () -> Void) {
        guard !isRunningUnderXCTest() else {
            debugLog("PermissionCoordinator.waitForAccessibilityGrant skipped under XCTest")
            return
        }
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

    func requestMicrophoneIfNeeded() async -> Bool {
        guard !isRunningUnderXCTest() else {
            debugLog("PermissionCoordinator.requestMicrophoneIfNeeded skipped under XCTest")
            return false
        }
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized:
            return true
        case .notDetermined:
            return await withCheckedContinuation { continuation in
                AVCaptureDevice.requestAccess(for: .audio) { granted in
                    continuation.resume(returning: granted)
                }
            }
        case .denied, .restricted:
            return false
        @unknown default:
            return false
        }
    }

    func requestSpeechRecognitionIfNeeded() async -> Bool {
        guard !isRunningUnderXCTest() else {
            debugLog("PermissionCoordinator.requestSpeechRecognitionIfNeeded skipped under XCTest")
            return false
        }
        switch SFSpeechRecognizer.authorizationStatus() {
        case .authorized:
            return true
        case .notDetermined:
            return await withCheckedContinuation { continuation in
                SFSpeechRecognizer.requestAuthorization { status in
                    continuation.resume(returning: status == .authorized)
                }
            }
        case .denied, .restricted:
            return false
        @unknown default:
            return false
        }
    }
}
