import AppKit
import Sparkle
import VoilyCore

struct SparkleUpdaterConfiguration: Equatable {
    static let feedURLInfoKey = "SUFeedURL"
    static let publicEDKeyInfoKey = "SUPublicEDKey"

    let feedURLString: String?
    let publicEDKey: String?

    init(feedURLString: String?, publicEDKey: String?) {
        self.feedURLString = feedURLString
        self.publicEDKey = publicEDKey
    }

    init(bundle: Bundle) {
        self.feedURLString = bundle.object(forInfoDictionaryKey: Self.feedURLInfoKey) as? String
        self.publicEDKey = bundle.object(forInfoDictionaryKey: Self.publicEDKeyInfoKey) as? String
    }

    var isReady: Bool {
        validFeedURL != nil && validPublicEDKey != nil
    }

    private var validFeedURL: URL? {
        guard
            let feedURLString,
            let url = URL(string: feedURLString),
            url.scheme == "https",
            url.host?.isEmpty == false
        else {
            return nil
        }
        return url
    }

    private var validPublicEDKey: String? {
        guard let publicEDKey else { return nil }
        let trimmed = publicEDKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !trimmed.contains("$(") else {
            return nil
        }
        return trimmed
    }
}

@MainActor
final class AppUpdater: NSObject {
    private let updaterController: SPUStandardUpdaterController?
    private let configuration: SparkleUpdaterConfiguration

    override convenience init() {
        self.init(configuration: SparkleUpdaterConfiguration(bundle: .main))
    }

    init(configuration: SparkleUpdaterConfiguration) {
        self.configuration = configuration
        if configuration.isReady {
            updaterController = SPUStandardUpdaterController(
                startingUpdater: true,
                updaterDelegate: nil,
                userDriverDelegate: nil
            )
        } else {
            updaterController = nil
        }
        super.init()
    }

    func makeCheckForUpdatesMenuItem() -> NSMenuItem {
        let item = NSMenuItem(
            title: AppLocalization.localized("检查更新…"),
            action: nil,
            keyEquivalent: ""
        )
        configureCheckForUpdatesMenuItem(item)
        return item
    }

    func configureCheckForUpdatesMenuItem(_ item: NSMenuItem) {
        item.title = AppLocalization.localized("检查更新…")
        item.isEnabled = true

        if let updaterController {
            item.target = updaterController
            item.action = #selector(SPUStandardUpdaterController.checkForUpdates(_:))
        } else {
            item.target = self
            item.action = #selector(showUpdaterNotConfigured(_:))
        }
    }

    @objc
    private func showUpdaterNotConfigured(_ sender: Any?) {
        let alert = NSAlert()
        alert.messageText = AppLocalization.localized("应用内更新尚未配置")
        alert.informativeText = AppLocalization.localized("需要先在发布机生成 Sparkle EdDSA 公钥并发布 appcast。")
        alert.addButton(withTitle: AppLocalization.localized("OK"))
        alert.runModal()
    }
}
