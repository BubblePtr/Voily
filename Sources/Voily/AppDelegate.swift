import AppKit

@available(macOS 26.0, *)
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var appController: AppController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        guard !isRunningInXcodePreview() else { return }
        try? FileManager.default.removeItem(atPath: "/tmp/voily.log")
        debugLog("AppDelegate.applicationDidFinishLaunching")
        appController = AppController()
        appController?.start()
    }

    func applicationWillTerminate(_ notification: Notification) {
        debugLog("AppDelegate.applicationWillTerminate")
        appController?.stop()
    }
}
