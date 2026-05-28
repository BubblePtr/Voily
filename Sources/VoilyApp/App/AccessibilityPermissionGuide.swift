import Foundation
import PermissionFlow

@MainActor
final class AccessibilityPermissionGuide {
    struct Request: Equatable {
        let suggestedAppURLs: [URL]
        let promptForAccessibilityTrust: Bool
    }

    private let appBundleURL: URL
    private let openRequest: @MainActor (Request) -> PermissionFlowController?
    // PermissionFlow owns its panel through this controller while guidance is visible.
    private var controller: PermissionFlowController?

    init(
        appBundleURL: URL = Bundle.main.bundleURL,
        openRequest: @escaping @MainActor (Request) -> PermissionFlowController? = AccessibilityPermissionGuide.openWithPermissionFlow
    ) {
        self.appBundleURL = appBundleURL
        self.openRequest = openRequest
    }

    func open() {
        controller = openRequest(
            Request(
                suggestedAppURLs: [appBundleURL.standardizedFileURL],
                promptForAccessibilityTrust: false
            )
        )
    }

    private static func openWithPermissionFlow(_ request: Request) -> PermissionFlowController {
        let controller = PermissionFlow.makeController(
            configuration: PermissionFlowConfiguration(
                requiredAppURLs: request.suggestedAppURLs,
                promptForAccessibilityTrust: request.promptForAccessibilityTrust
            )
        )
        controller.authorize(pane: .accessibility, suggestedAppURLs: request.suggestedAppURLs)
        return controller
    }
}
