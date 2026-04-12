import AppKit

@available(macOS 26.0, *)
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let windowActions = WindowActions()
    lazy var appController = AppController(windowActions: windowActions)
    private var isTerminating = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        guard !isRunningInXcodePreview() else { return }
        try? FileManager.default.removeItem(atPath: "/tmp/voily.log")
        debugLog("AppDelegate.applicationDidFinishLaunching")
        appController.start()
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        appController.handleReopen(hasVisibleWindows: flag)
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard !isTerminating else {
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
}
