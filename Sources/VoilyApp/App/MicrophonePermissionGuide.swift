import Foundation
import PermissionFlow

@MainActor
final class MicrophonePermissionGuide {
    // PermissionFlow owns its panel through this controller while guidance is visible.
    private var controller: PermissionFlowController?

    func openSettings() {
        let controller = PermissionFlow.makeController()
        controller.authorize(pane: .microphone)
        self.controller = controller
    }
}
