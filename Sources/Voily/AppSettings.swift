import Foundation
import Observation

@MainActor
@Observable
final class AppSettings {
    private enum Keys {
        static let selectedLanguageCode = "selectedLanguageCode"
        static let llmEnabled = "llmEnabled"
        static let llmBaseURL = "llmBaseURL"
        static let llmAPIKey = "llmAPIKey"
        static let llmModel = "llmModel"
    }

    var selectedLanguageCode: String {
        didSet { defaults.set(selectedLanguageCode, forKey: Keys.selectedLanguageCode) }
    }

    var llmEnabled: Bool {
        didSet { defaults.set(llmEnabled, forKey: Keys.llmEnabled) }
    }

    var llmBaseURL: String {
        didSet { defaults.set(llmBaseURL, forKey: Keys.llmBaseURL) }
    }

    var llmAPIKey: String {
        didSet { defaults.set(llmAPIKey, forKey: Keys.llmAPIKey) }
    }

    var llmModel: String {
        didSet { defaults.set(llmModel, forKey: Keys.llmModel) }
    }

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        self.selectedLanguageCode = defaults.string(forKey: Keys.selectedLanguageCode) ?? SupportedLanguage.simplifiedChinese.rawValue
        self.llmEnabled = defaults.object(forKey: Keys.llmEnabled) as? Bool ?? false
        self.llmBaseURL = defaults.string(forKey: Keys.llmBaseURL) ?? ""
        self.llmAPIKey = defaults.string(forKey: Keys.llmAPIKey) ?? ""
        self.llmModel = defaults.string(forKey: Keys.llmModel) ?? ""
    }

    var selectedLanguage: SupportedLanguage {
        get { SupportedLanguage(rawValue: selectedLanguageCode) ?? .simplifiedChinese }
        set { selectedLanguageCode = newValue.rawValue }
    }

    var isLLMConfigured: Bool {
        !llmBaseURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        !llmAPIKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        !llmModel.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}
