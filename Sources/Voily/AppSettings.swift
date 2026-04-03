import Foundation
import Observation

enum ASRProvider: String, CaseIterable, Codable, Identifiable {
    case whisperCpp
    case senseVoice
    case doubaoStreaming
    case qwenASR

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .whisperCpp:
            return "whisper.cpp"
        case .senseVoice:
            return "SenseVoice"
        case .doubaoStreaming:
            return "豆包流式语音识别"
        case .qwenASR:
            return "Qwen ASR"
        }
    }

    var category: ProviderCategory {
        switch self {
        case .whisperCpp, .senseVoice:
            return .local
        case .doubaoStreaming, .qwenASR:
            return .cloud
        }
    }
}

enum TextRefinementProvider: String, CaseIterable, Codable, Identifiable {
    case deepSeek
    case dashScope
    case volcengine

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .deepSeek:
            return "DeepSeek"
        case .dashScope:
            return "阿里云百炼"
        case .volcengine:
            return "火山引擎"
        }
    }
}

enum ProviderCategory: String, Codable {
    case local
    case cloud

    var displayName: String {
        switch self {
        case .local:
            return "本地"
        case .cloud:
            return "云端"
        }
    }
}

struct ASRProviderConfig: Codable, Equatable {
    var executablePath: String
    var modelPath: String
    var additionalArguments: String
    var baseURL: String
    var apiKey: String
    var model: String

    static let empty = ASRProviderConfig(
        executablePath: "",
        modelPath: "",
        additionalArguments: "",
        baseURL: "",
        apiKey: "",
        model: ""
    )

    func isConfigured(for provider: ASRProvider) -> Bool {
        switch provider.category {
        case .local:
            return !modelPath.trimmed.isEmpty || !executablePath.trimmed.isEmpty
        case .cloud:
            return !baseURL.trimmed.isEmpty && !apiKey.trimmed.isEmpty && !model.trimmed.isEmpty
        }
    }
}

struct TextRefinementProviderConfig: Codable, Equatable {
    var baseURL: String
    var apiKey: String
    var model: String

    static let empty = TextRefinementProviderConfig(baseURL: "", apiKey: "", model: "")

    var isConfigured: Bool {
        !baseURL.trimmed.isEmpty && !apiKey.trimmed.isEmpty && !model.trimmed.isEmpty
    }
}

struct ModelSettingsSnapshot: Codable, Equatable {
    var selectedASRProvider: ASRProvider
    var selectedTextProvider: TextRefinementProvider
    var textRefinementEnabled: Bool
    var asrConfigsByProvider: [ASRProvider: ASRProviderConfig]
    var textConfigsByProvider: [TextRefinementProvider: TextRefinementProviderConfig]

    static let `default` = ModelSettingsSnapshot(
        selectedASRProvider: .whisperCpp,
        selectedTextProvider: .deepSeek,
        textRefinementEnabled: false,
        asrConfigsByProvider: Dictionary(
            uniqueKeysWithValues: ASRProvider.allCases.map { ($0, .empty) }
        ),
        textConfigsByProvider: Dictionary(
            uniqueKeysWithValues: TextRefinementProvider.allCases.map { ($0, .empty) }
        )
    )
}

private extension String {
    var trimmed: String {
        trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

@MainActor
@Observable
final class AppSettings {
    private enum Keys {
        static let selectedLanguageCode = "selectedLanguageCode"
        static let glossaryEntries = "glossaryEntries"
        static let modelSettingsSnapshot = "modelSettingsSnapshot"

        static let legacyLLMEnabled = "llmEnabled"
        static let legacyLLMBaseURL = "llmBaseURL"
        static let legacyLLMAPIKey = "llmAPIKey"
        static let legacyLLMModel = "llmModel"
    }

    var selectedLanguageCode: String {
        didSet { defaults.set(selectedLanguageCode, forKey: Keys.selectedLanguageCode) }
    }

    var glossaryEntries: String {
        didSet { defaults.set(glossaryEntries, forKey: Keys.glossaryEntries) }
    }

    var selectedASRProvider: ASRProvider {
        didSet { persistSnapshot() }
    }

    var selectedTextProvider: TextRefinementProvider {
        didSet { persistSnapshot() }
    }

    var textRefinementEnabled: Bool {
        didSet { persistSnapshot() }
    }

    var asrConfigsByProvider: [ASRProvider: ASRProviderConfig] {
        didSet { persistSnapshot() }
    }

    var textConfigsByProvider: [TextRefinementProvider: TextRefinementProviderConfig] {
        didSet { persistSnapshot() }
    }

    private let defaults: UserDefaults
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        self.selectedLanguageCode = defaults.string(forKey: Keys.selectedLanguageCode) ?? SupportedLanguage.simplifiedChinese.rawValue
        self.glossaryEntries = defaults.string(forKey: Keys.glossaryEntries) ?? ""

        let snapshot = Self.loadSnapshot(from: defaults) ?? Self.makeLegacySnapshot(from: defaults)
        self.selectedASRProvider = snapshot.selectedASRProvider
        self.selectedTextProvider = snapshot.selectedTextProvider
        self.textRefinementEnabled = snapshot.textRefinementEnabled
        self.asrConfigsByProvider = snapshot.asrConfigsByProvider
        self.textConfigsByProvider = snapshot.textConfigsByProvider

        persistSnapshot()
    }

    var selectedLanguage: SupportedLanguage {
        get { SupportedLanguage(rawValue: selectedLanguageCode) ?? .simplifiedChinese }
        set { selectedLanguageCode = newValue.rawValue }
    }

    var selectedASRConfig: ASRProviderConfig {
        get { asrConfigsByProvider[selectedASRProvider] ?? .empty }
        set { asrConfigsByProvider[selectedASRProvider] = newValue }
    }

    var selectedTextProviderConfig: TextRefinementProviderConfig {
        get { textConfigsByProvider[selectedTextProvider] ?? .empty }
        set { textConfigsByProvider[selectedTextProvider] = newValue }
    }

    var isTextRefinementConfigured: Bool {
        selectedTextProviderConfig.isConfigured
    }

    var glossaryItems: [String] {
        glossaryEntries
            .split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    func asrConfig(for provider: ASRProvider) -> ASRProviderConfig {
        asrConfigsByProvider[provider] ?? .empty
    }

    func setASRConfig(_ config: ASRProviderConfig, for provider: ASRProvider) {
        asrConfigsByProvider[provider] = config
    }

    func textRefinementConfig(for provider: TextRefinementProvider) -> TextRefinementProviderConfig {
        textConfigsByProvider[provider] ?? .empty
    }

    func setTextRefinementConfig(_ config: TextRefinementProviderConfig, for provider: TextRefinementProvider) {
        textConfigsByProvider[provider] = config
    }

    private func persistSnapshot() {
        let snapshot = ModelSettingsSnapshot(
            selectedASRProvider: selectedASRProvider,
            selectedTextProvider: selectedTextProvider,
            textRefinementEnabled: textRefinementEnabled,
            asrConfigsByProvider: Dictionary(
                uniqueKeysWithValues: ASRProvider.allCases.map { provider in
                    (provider, asrConfigsByProvider[provider] ?? .empty)
                }
            ),
            textConfigsByProvider: Dictionary(
                uniqueKeysWithValues: TextRefinementProvider.allCases.map { provider in
                    (provider, textConfigsByProvider[provider] ?? .empty)
                }
            )
        )

        guard let data = try? encoder.encode(snapshot) else { return }
        defaults.set(data, forKey: Keys.modelSettingsSnapshot)
    }

    private static func loadSnapshot(from defaults: UserDefaults) -> ModelSettingsSnapshot? {
        guard let data = defaults.data(forKey: Keys.modelSettingsSnapshot) else {
            return nil
        }

        let decoder = JSONDecoder()
        guard var snapshot = try? decoder.decode(ModelSettingsSnapshot.self, from: data) else {
            return nil
        }

        for provider in ASRProvider.allCases where snapshot.asrConfigsByProvider[provider] == nil {
            snapshot.asrConfigsByProvider[provider] = .empty
        }

        for provider in TextRefinementProvider.allCases where snapshot.textConfigsByProvider[provider] == nil {
            snapshot.textConfigsByProvider[provider] = .empty
        }

        return snapshot
    }

    private static func makeLegacySnapshot(from defaults: UserDefaults) -> ModelSettingsSnapshot {
        var snapshot = ModelSettingsSnapshot.default
        snapshot.textRefinementEnabled = defaults.object(forKey: Keys.legacyLLMEnabled) as? Bool ?? false

        let baseURL = defaults.string(forKey: Keys.legacyLLMBaseURL) ?? ""
        let apiKey = defaults.string(forKey: Keys.legacyLLMAPIKey) ?? ""
        let model = defaults.string(forKey: Keys.legacyLLMModel) ?? ""

        if !baseURL.trimmed.isEmpty || !apiKey.trimmed.isEmpty || !model.trimmed.isEmpty {
            snapshot.textConfigsByProvider[.deepSeek] = TextRefinementProviderConfig(
                baseURL: baseURL,
                apiKey: apiKey,
                model: model
            )
        }

        return snapshot
    }
}
