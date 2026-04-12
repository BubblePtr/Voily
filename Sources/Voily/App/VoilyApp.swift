import SwiftUI

@main
@available(macOS 26.0, *)
struct VoilyApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        Window("Voily", id: SettingsWindowSceneID.settings) {
            appDelegate.appController.makeSettingsWindowSceneView()
        }
        .defaultLaunchBehavior(.presented)
        .defaultSize(width: 1120, height: 760)
        .windowResizability(.contentMinSize)
    }
}
