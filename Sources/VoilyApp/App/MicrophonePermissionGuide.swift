import Foundation
import PermissionFlow

@MainActor
final class MicrophonePermissionGuide {
    private var controller: PermissionFlowController?

    func openSettings() {
        let controller = PermissionFlow.makeController()
        controller.authorize(pane: .microphone)
        self.controller = controller
    }
}
