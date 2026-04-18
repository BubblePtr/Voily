import SwiftUI

@main
struct VoilyApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        Window("Voily", id: SettingsWindowSceneID.settings) {
            appDelegate.appController.makeSettingsWindowSceneView()
        }
        .defaultSize(width: 1120, height: 760)
    }
}
