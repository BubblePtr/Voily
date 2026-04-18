import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let windowActions = WindowActions()
    lazy var appController = AppController(windowActions: windowActions)
    private var isTerminating = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        guard !isRunningInXcodePreview() else { return }
        try? FileManager.default.removeItem(atPath: "/tmp/voily.log")
        debugLog("AppDelegate.applicationDidFinishLaunching")
        guard !isRunningUnderXCTest() else {
            debugLog("AppDelegate.applicationDidFinishLaunching skipping app startup under XCTest")
            return
        }
        appController.start()
        Task { @MainActor in
            self.appController.showSettingsWindow()
        }
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        debugLog("AppDelegate.applicationShouldHandleReopen hasVisibleWindows=\(flag)")
        return appController.handleReopen(hasVisibleWindows: flag)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        debugLog("AppDelegate.applicationShouldTerminateAfterLastWindowClosed false")
        return false
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard !isTerminating else {
            debugLog("AppDelegate.applicationShouldTerminate already terminating")
            return .terminateNow
        }

        isTerminating = true
        debugLog("AppDelegate.applicationShouldTerminate")
        Task { @MainActor in
            await appController.stop()
            sender.reply(toApplicationShouldTerminate: true)
        }
        return .terminateLater
    }

    func applicationWillTerminate(_ notification: Notification) {
        debugLog("AppDelegate.applicationWillTerminate")
    }

    func applicationWillBecomeActive(_ notification: Notification) {
        debugLog("AppDelegate.applicationWillBecomeActive")
    }

    func applicationDidBecomeActive(_ notification: Notification) {
        debugLog("AppDelegate.applicationDidBecomeActive")
        appController.handleApplicationDidBecomeActive()
    }

    func applicationWillResignActive(_ notification: Notification) {
        debugLog("AppDelegate.applicationWillResignActive")
    }

    func applicationDidResignActive(_ notification: Notification) {
        debugLog("AppDelegate.applicationDidResignActive")
    }

    func applicationWillHide(_ notification: Notification) {
        debugLog("AppDelegate.applicationWillHide")
    }

    func applicationDidHide(_ notification: Notification) {
        debugLog("AppDelegate.applicationDidHide")
    }

    func applicationWillUnhide(_ notification: Notification) {
        debugLog("AppDelegate.applicationWillUnhide")
    }

    func applicationDidUnhide(_ notification: Notification) {
        debugLog("AppDelegate.applicationDidUnhide")
    }
}
