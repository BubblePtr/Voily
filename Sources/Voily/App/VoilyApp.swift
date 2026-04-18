import SwiftUI

@main
struct VoilyApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        Window("Voily", id: SettingsWindowSceneID.settings) {
            appDelegate.appController.makeSettingsWindowSceneView()
        }
        .defaultSize(width: 1120, height: 760)
        .commands {
            SettingsWindowCommands(appController: appDelegate.appController)
        }
    }
}

private struct SettingsWindowCommands: Commands {
    let appController: AppController

    @Environment(\.openWindow) private var openWindow

    var body: some Commands {
        registerOpenSettingsWindowAction()

        return CommandGroup(replacing: .appSettings) {
            Button("Settings...") {
                appController.showSettingsWindow()
            }
            .keyboardShortcut(",", modifiers: .command)
        }
    }

    private func registerOpenSettingsWindowAction() {
        appController.registerOpenSettingsWindowAction {
            openWindow(id: SettingsWindowSceneID.settings)
        }
    }
}
