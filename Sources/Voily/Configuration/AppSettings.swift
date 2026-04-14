import Foundation
import Observation

enum ASRProvider: String, CaseIterable, Codable, Identifiable {
    case senseVoice
    case doubaoStreaming
    case qwenASR

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .senseVoice:
            return "SenseVoice Small"
        case .doubaoStreaming:
            return "豆包流式语音识别"
        case .qwenASR:
            return "Qwen ASR"
        }
    }

    var category: ProviderCategory {
        switch self {
        case .senseVoice:
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

enum DictationProcessingSkill: String, CaseIterable, Codable, Identifiable {
    case removeFillers
    case formalize
    case orderedList

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .removeFillers:
            return "去语气词"
        case .formalize:
            return "更正式"
        case .orderedList:
            return "整理成有序列表"
        }
    }

    var summary: String {
        switch self {
        case .removeFillers:
            return "删除明显语气词和停顿赘词，尽量不改句子结构。"
        case .formalize:
            return "将口述表达整理为中性书面语，不扩写、不总结。"
        case .orderedList:
            return "当内容包含 2 个及以上清晰事项时，整理为纯文本编号列表。"
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

enum AppIconVariant: String, CaseIterable, Codable, Identifiable {
    case `default`
    case easterEggSVG4

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .default:
            return "默认图标"
        case .easterEggSVG4:
            return "彩蛋图标"
        }
    }

    var imageAssetName: String {
        switch self {
        case .default:
            return "AppIconDefaultImage"
        case .easterEggSVG4:
            return "AppIconEasterEggSVG4Image"
        }
    }
}

enum TriggerKey: String, CaseIterable, Codable, Identifiable {
    case fn
    case rightCommand

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .fn:
            return "Fn"
        case .rightCommand:
            return "右 Command"
        }
    }

    var summary: String {
        switch self {
        case .fn:
            return "单击 Fn 开始普通听写，再单击一次 Fn 结束；长按 Fn 0.8 秒启动快捷翻译。"
        case .rightCommand:
            return "单击右 Command 开始普通听写，再单击一次右 Command 结束；长按右 Command 0.8 秒启动快捷翻译。"
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

    private enum CodingKeys: String, CodingKey {
        case executablePath
        case modelPath
        case additionalArguments
        case baseURL
        case apiKey
        case model
    }

    init(
        executablePath: String,
        modelPath: String,
        additionalArguments: String,
        baseURL: String,
        apiKey: String,
        model: String
    ) {
        self.executablePath = executablePath
        self.modelPath = modelPath
        self.additionalArguments = additionalArguments
        self.baseURL = baseURL
        self.apiKey = apiKey
        self.model = model
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        executablePath = try container.decodeIfPresent(String.self, forKey: .executablePath) ?? ""
        modelPath = try container.decodeIfPresent(String.self, forKey: .modelPath) ?? ""
        additionalArguments = try container.decodeIfPresent(String.self, forKey: .additionalArguments) ?? ""
        baseURL = try container.decodeIfPresent(String.self, forKey: .baseURL) ?? ""
        apiKey = try container.decodeIfPresent(String.self, forKey: .apiKey) ?? ""
        model = try container.decodeIfPresent(String.self, forKey: .model) ?? ""
    }

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
    var triggerKey: TriggerKey
    var dockIconVisible: Bool
    var preferredMicrophoneUID: String?
    var enabledDictationSkills: [DictationProcessingSkill]
    var asrConfigsByProvider: [ASRProvider: ASRProviderConfig]
    var textConfigsByProvider: [TextRefinementProvider: TextRefinementProviderConfig]

    static let `default` = ModelSettingsSnapshot(
        selectedASRProvider: .senseVoice,
        selectedTextProvider: .deepSeek,
        textRefinementEnabled: false,
        triggerKey: .fn,
        dockIconVisible: true,
        preferredMicrophoneUID: nil,
        enabledDictationSkills: [],
        asrConfigsByProvider: {
            var configs: [ASRProvider: ASRProviderConfig] = Dictionary(
                uniqueKeysWithValues: ASRProvider.allCases.map { ($0, ASRProviderConfig.empty) }
            )
            configs[.qwenASR] = ASRProviderConfig(
                executablePath: "",
                modelPath: "",
                additionalArguments: "",
                baseURL: "wss://dashscope.aliyuncs.com/api-ws/v1/realtime",
                apiKey: "",
                model: "qwen3-asr-flash-realtime"
            )
            return configs
        }(),
        textConfigsByProvider: Dictionary(
            uniqueKeysWithValues: TextRefinementProvider.allCases.map { ($0, .empty) }
        )
    )

    private enum CodingKeys: String, CodingKey {
        case selectedASRProvider
        case selectedTextProvider
        case textRefinementEnabled
        case triggerKey
        case dockIconVisible
        case preferredMicrophoneUID
        case enabledDictationSkills
        case asrConfigsByProvider
        case textConfigsByProvider
    }

    init(
        selectedASRProvider: ASRProvider,
        selectedTextProvider: TextRefinementProvider,
        textRefinementEnabled: Bool,
        triggerKey: TriggerKey,
        dockIconVisible: Bool,
        preferredMicrophoneUID: String?,
        enabledDictationSkills: [DictationProcessingSkill],
        asrConfigsByProvider: [ASRProvider: ASRProviderConfig],
        textConfigsByProvider: [TextRefinementProvider: TextRefinementProviderConfig]
    ) {
        self.selectedASRProvider = selectedASRProvider
        self.selectedTextProvider = selectedTextProvider
        self.textRefinementEnabled = textRefinementEnabled
        self.triggerKey = triggerKey
        self.dockIconVisible = dockIconVisible
        self.preferredMicrophoneUID = preferredMicrophoneUID
        self.enabledDictationSkills = enabledDictationSkills
        self.asrConfigsByProvider = asrConfigsByProvider
        self.textConfigsByProvider = textConfigsByProvider
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let selectedASRRawValue = try container.decodeIfPresent(String.self, forKey: .selectedASRProvider)
        selectedASRProvider = Self.migratedSelectedASRProvider(from: selectedASRRawValue)
        selectedTextProvider = try container.decodeIfPresent(TextRefinementProvider.self, forKey: .selectedTextProvider) ?? .deepSeek
        textRefinementEnabled = try container.decode(Bool.self, forKey: .textRefinementEnabled)
        triggerKey = try container.decodeIfPresent(TriggerKey.self, forKey: .triggerKey) ?? .fn
        dockIconVisible = try container.decodeIfPresent(Bool.self, forKey: .dockIconVisible) ?? true
        preferredMicrophoneUID = try container.decodeIfPresent(String.self, forKey: .preferredMicrophoneUID)
        enabledDictationSkills = try container.decodeIfPresent([DictationProcessingSkill].self, forKey: .enabledDictationSkills) ?? []
        let rawASRConfigs: [ASRProvider: ASRProviderConfig] = try Self.decodeRawConfigMap(
            from: container,
            forKey: .asrConfigsByProvider,
            supportedKey: Self.supportedASRProvider(for:)
        )
        asrConfigsByProvider = rawASRConfigs.reduce(into: [:]) { partialResult, entry in
            partialResult[entry.key] = entry.value
        }
        textConfigsByProvider = try Self.decodeRawConfigMap(
            from: container,
            forKey: .textConfigsByProvider,
            supportedKey: TextRefinementProvider.init(rawValue:)
        )
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(selectedASRProvider.rawValue, forKey: .selectedASRProvider)
        try container.encode(selectedTextProvider, forKey: .selectedTextProvider)
        try container.encode(textRefinementEnabled, forKey: .textRefinementEnabled)
        try container.encode(triggerKey, forKey: .triggerKey)
        try container.encode(dockIconVisible, forKey: .dockIconVisible)
        try container.encodeIfPresent(preferredMicrophoneUID, forKey: .preferredMicrophoneUID)
        try container.encode(enabledDictationSkills, forKey: .enabledDictationSkills)
        try container.encode(
            Dictionary(uniqueKeysWithValues: asrConfigsByProvider.map { ($0.key.rawValue, $0.value) }),
            forKey: .asrConfigsByProvider
        )
        try container.encode(
            Dictionary(uniqueKeysWithValues: textConfigsByProvider.map { ($0.key.rawValue, $0.value) }),
            forKey: .textConfigsByProvider
        )
    }

    private static func migratedSelectedASRProvider(from rawValue: String?) -> ASRProvider {
        guard let rawValue else {
            return .senseVoice
        }
        if rawValue == "whisperCpp" {
            return .senseVoice
        }
        return supportedASRProvider(for: rawValue) ?? .senseVoice
    }

    private static func supportedASRProvider(for rawValue: String) -> ASRProvider? {
        ASRProvider(rawValue: rawValue)
    }

    private static func decodeRawConfigMap<Key: Hashable, Value: Decodable>(
        from container: KeyedDecodingContainer<CodingKeys>,
        forKey codingKey: CodingKeys,
        supportedKey: (String) -> Key?
    ) throws -> [Key: Value] {
        if let rawDictionary = try? container.decode([String: Value].self, forKey: codingKey) {
            return rawDictionary.reduce(into: [:]) { partialResult, entry in
                guard let key = supportedKey(entry.key) else { return }
                partialResult[key] = entry.value
            }
        }

        guard container.contains(codingKey) else {
            return [:]
        }

        var rawPairs = try container.nestedUnkeyedContainer(forKey: codingKey)
        var decoded: [Key: Value] = [:]

        while !rawPairs.isAtEnd {
            let rawKey = try rawPairs.decode(String.self)
            let value = try rawPairs.decode(Value.self)
            guard let key = supportedKey(rawKey) else { continue }
            decoded[key] = value
        }

        return decoded
    }
}

enum GlossaryPresetID: String, CaseIterable, Codable, Identifiable {
    case internetDevelopment
    case internetTesting
    case internetProductManager
    case medical
    case legal

    var id: String { rawValue }
}

struct GlossaryPresetDefinition: Identifiable, Equatable {
    let id: GlossaryPresetID
    let domainTitle: String
    let sceneTitle: String?
    let terms: [String]

    var title: String {
        sceneTitle ?? domainTitle
    }

    var fullTitle: String {
        if let sceneTitle {
            return "\(domainTitle)-\(sceneTitle)"
        }
        return domainTitle
    }

    var itemCount: Int {
        terms.count
    }

    static let categories: [GlossaryPresetCategory] = [
        GlossaryPresetCategory(
            title: "互联网",
            presets: [
                GlossaryPresetDefinition(
                    id: .internetDevelopment,
                    domainTitle: "互联网",
                    sceneTitle: "开发",
                    terms: [
                        "OpenAI",
                        "ChatGPT",
                        "API",
                        "SDK",
                        "JSON",
                        "Python",
                        "TypeScript",
                        "SwiftUI",
                        "Xcode",
                        "GitHub",
                        "iOS",
                        "macOS",
                    ]
                ),
                GlossaryPresetDefinition(
                    id: .internetTesting,
                    domainTitle: "互联网",
                    sceneTitle: "测试",
                    terms: [
                        "QA",
                        "Test Case",
                        "Bug",
                        "Regression",
                        "Smoke Test",
                        "Integration Test",
                        "E2E",
                        "Selenium",
                        "Playwright",
                        "Jira",
                    ]
                ),
                GlossaryPresetDefinition(
                    id: .internetProductManager,
                    domainTitle: "互联网",
                    sceneTitle: "产品经理",
                    terms: [
                        "PRD",
                        "Roadmap",
                        "Backlog",
                        "MVP",
                        "KPI",
                        "OKR",
                        "User Story",
                        "Wireframe",
                        "Prototype",
                        "A/B Test",
                    ]
                ),
            ]
        ),
        GlossaryPresetCategory(
            title: "医疗",
            presets: [
                GlossaryPresetDefinition(
                    id: .medical,
                    domainTitle: "医疗",
                    sceneTitle: nil,
                    terms: [
                        "门诊",
                        "住院",
                        "病历",
                        "处方",
                        "诊断",
                        "CT",
                        "MRI",
                        "超声",
                        "心电图",
                        "检验科",
                    ]
                ),
            ]
        ),
        GlossaryPresetCategory(
            title: "法律",
            presets: [
                GlossaryPresetDefinition(
                    id: .legal,
                    domainTitle: "法律",
                    sceneTitle: nil,
                    terms: [
                        "合同",
                        "诉讼",
                        "仲裁",
                        "原告",
                        "被告",
                        "证据",
                        "法务",
                        "合规",
                        "尽职调查",
                        "知识产权",
                    ]
                ),
            ]
        ),
    ]

    static let all: [GlossaryPresetDefinition] = categories.flatMap(\.presets)

    static func definition(for id: GlossaryPresetID) -> GlossaryPresetDefinition {
        all.first(where: { $0.id == id }) ?? GlossaryPresetDefinition(
            id: id,
            domainTitle: "未知",
            sceneTitle: nil,
            terms: []
        )
    }
}

struct GlossaryPresetCategory: Identifiable, Equatable {
    let title: String
    let presets: [GlossaryPresetDefinition]

    var id: String { title }
}

struct GlossarySection: Equatable {
    let title: String
    let items: [String]
}

struct GlossarySettingsSnapshot: Codable, Equatable {
    var enabledPresetIDs: [GlossaryPresetID]
    var customTerms: [String]

    static let `default` = GlossarySettingsSnapshot(enabledPresetIDs: [], customTerms: [])
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
        static let glossarySettingsSnapshot = "glossarySettingsSnapshot"
        static let modelSettingsSnapshot = "modelSettingsSnapshot"
        static let isEasterEggUnlocked = "isEasterEggUnlocked"
        static let selectedAppIconVariant = "selectedAppIconVariant"

        static let legacyLLMEnabled = "llmEnabled"
        static let legacyLLMBaseURL = "llmBaseURL"
        static let legacyLLMAPIKey = "llmAPIKey"
        static let legacyLLMModel = "llmModel"
    }

    var selectedLanguageCode: String {
        didSet {
            defaults.set(selectedLanguageCode, forKey: Keys.selectedLanguageCode)
            flushDefaults()
        }
    }

    var glossaryEntries: String {
        didSet {
            defaults.set(glossaryEntries, forKey: Keys.glossaryEntries)
            flushDefaults()

            guard !isSyncingLegacyGlossary else { return }

            let normalizedTerms = Self.normalizeTerms(Self.parseLegacyGlossaryEntries(glossaryEntries))
            guard normalizedTerms != glossaryState.customTerms else { return }

            glossaryState = GlossarySettingsSnapshot(
                enabledPresetIDs: glossaryState.enabledPresetIDs,
                customTerms: normalizedTerms
            )
        }
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

    var triggerKey: TriggerKey {
        didSet { persistSnapshot() }
    }

    var dockIconVisible: Bool {
        didSet { persistSnapshot() }
    }

    var preferredMicrophoneUID: String? {
        didSet { persistSnapshot() }
    }

    var enabledDictationSkills: [DictationProcessingSkill] {
        didSet {
            let normalized = Self.normalizedDictationSkills(enabledDictationSkills)
            if normalized != enabledDictationSkills {
                enabledDictationSkills = normalized
                return
            }
            persistSnapshot()
        }
    }

    var asrConfigsByProvider: [ASRProvider: ASRProviderConfig] {
        didSet { persistSnapshot() }
    }

    var textConfigsByProvider: [TextRefinementProvider: TextRefinementProviderConfig] {
        didSet { persistSnapshot() }
    }

    var isEasterEggUnlocked: Bool {
        didSet {
            defaults.set(isEasterEggUnlocked, forKey: Keys.isEasterEggUnlocked)
            flushDefaults()
        }
    }

    var selectedAppIconVariant: AppIconVariant {
        didSet {
            defaults.set(selectedAppIconVariant.rawValue, forKey: Keys.selectedAppIconVariant)
            flushDefaults()
        }
    }

    private var glossaryState: GlossarySettingsSnapshot {
        didSet {
            persistGlossaryState()
            syncLegacyGlossaryEntries()
        }
    }

    private let defaults: UserDefaults
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()
    private var isSyncingLegacyGlossary = false

    init(defaults: UserDefaults = .standard) {
        let legacyGlossaryEntries = defaults.string(forKey: Keys.glossaryEntries) ?? ""
        self.defaults = defaults
        self.selectedLanguageCode = defaults.string(forKey: Keys.selectedLanguageCode) ?? SupportedLanguage.simplifiedChinese.rawValue
        self.glossaryEntries = legacyGlossaryEntries
        self.glossaryState = Self.loadGlossarySnapshot(from: defaults)
            ?? Self.makeLegacyGlossarySnapshot(entries: legacyGlossaryEntries)

        let snapshot = Self.normalizedSnapshot(Self.loadSnapshot(from: defaults) ?? Self.makeLegacySnapshot(from: defaults))
        self.selectedASRProvider = snapshot.selectedASRProvider
        self.selectedTextProvider = snapshot.selectedTextProvider
        self.textRefinementEnabled = snapshot.textRefinementEnabled
        self.triggerKey = snapshot.triggerKey
        self.dockIconVisible = snapshot.dockIconVisible
        self.preferredMicrophoneUID = snapshot.preferredMicrophoneUID?.trimmed.nilIfEmpty
        self.enabledDictationSkills = snapshot.enabledDictationSkills
        self.asrConfigsByProvider = snapshot.asrConfigsByProvider
        self.textConfigsByProvider = snapshot.textConfigsByProvider
        self.isEasterEggUnlocked = defaults.object(forKey: Keys.isEasterEggUnlocked) as? Bool ?? false
        self.selectedAppIconVariant = AppIconVariant(
            rawValue: defaults.string(forKey: Keys.selectedAppIconVariant) ?? AppIconVariant.default.rawValue
        ) ?? .default

        persistSnapshot()
        persistGlossaryState()
        syncLegacyGlossaryEntries()
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

    var enabledGlossaryPresetIDs: [GlossaryPresetID] {
        get { glossaryState.enabledPresetIDs }
        set {
            setGlossaryState(
                enabledPresetIDs: newValue,
                customTerms: glossaryState.customTerms
            )
        }
    }

    var customGlossaryTerms: [String] {
        get { glossaryState.customTerms }
        set {
            setGlossaryState(
                enabledPresetIDs: glossaryState.enabledPresetIDs,
                customTerms: newValue
            )
        }
    }

    var effectiveGlossarySections: [GlossarySection] {
        var seen = Set<String>()
        var sections: [GlossarySection] = []

        let customItems = glossaryState.customTerms.filter { seen.insert($0).inserted }
        if !customItems.isEmpty {
            sections.append(GlossarySection(title: "自定义词条", items: customItems))
        }

        for presetID in GlossaryPresetID.allCases where glossaryState.enabledPresetIDs.contains(presetID) {
            let definition = GlossaryPresetDefinition.definition(for: presetID)
            let uniqueItems = definition.terms
                .map(\.trimmed)
                .filter { !$0.isEmpty }
                .filter { seen.insert($0).inserted }

            if !uniqueItems.isEmpty {
                sections.append(GlossarySection(title: definition.fullTitle, items: uniqueItems))
            }
        }

        return sections
    }

    var effectiveGlossaryItems: [String] {
        effectiveGlossarySections.flatMap(\.items)
    }

    var glossaryItems: [String] {
        effectiveGlossaryItems
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

    func setEnabledDictationSkills(_ skills: [DictationProcessingSkill]) {
        enabledDictationSkills = Self.normalizedDictationSkills(skills)
    }

    func toggleDictationSkill(_ skill: DictationProcessingSkill) {
        var nextSkills = enabledDictationSkills
        if let index = nextSkills.firstIndex(of: skill) {
            nextSkills.remove(at: index)
        } else {
            nextSkills.append(skill)
        }
        setEnabledDictationSkills(nextSkills)
    }

    func setGlossaryState(enabledPresetIDs: [GlossaryPresetID], customTerms: [String]) {
        glossaryState = Self.normalizedGlossaryState(
            GlossarySettingsSnapshot(
                enabledPresetIDs: enabledPresetIDs,
                customTerms: customTerms
            )
        )
    }

    func toggleGlossaryPreset(_ presetID: GlossaryPresetID) {
        var enabledPresetIDs = glossaryState.enabledPresetIDs
        if let index = enabledPresetIDs.firstIndex(of: presetID) {
            enabledPresetIDs.remove(at: index)
        } else {
            enabledPresetIDs.append(presetID)
        }

        setGlossaryState(enabledPresetIDs: enabledPresetIDs, customTerms: glossaryState.customTerms)
    }

    @discardableResult
    func addCustomGlossaryTerm(_ term: String) -> Bool {
        let normalized = term.trimmed
        guard !normalized.isEmpty else { return false }
        guard !glossaryState.customTerms.contains(normalized) else { return false }

        setGlossaryState(
            enabledPresetIDs: glossaryState.enabledPresetIDs,
            customTerms: glossaryState.customTerms + [normalized]
        )
        return true
    }

    func removeCustomGlossaryTerm(_ term: String) {
        setGlossaryState(
            enabledPresetIDs: glossaryState.enabledPresetIDs,
            customTerms: glossaryState.customTerms.filter { $0 != term }
        )
    }

    func clearCustomGlossaryTerms() {
        setGlossaryState(enabledPresetIDs: glossaryState.enabledPresetIDs, customTerms: [])
    }

    private func persistSnapshot() {
        let snapshot = ModelSettingsSnapshot(
            selectedASRProvider: selectedASRProvider,
            selectedTextProvider: selectedTextProvider,
            textRefinementEnabled: textRefinementEnabled,
            triggerKey: triggerKey,
            dockIconVisible: dockIconVisible,
            preferredMicrophoneUID: preferredMicrophoneUID?.trimmed.nilIfEmpty,
            enabledDictationSkills: enabledDictationSkills,
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
        flushDefaults()
    }

    private func persistGlossaryState() {
        guard let data = try? encoder.encode(glossaryState) else { return }
        defaults.set(data, forKey: Keys.glossarySettingsSnapshot)
        flushDefaults()
    }

    private func syncLegacyGlossaryEntries() {
        let normalizedEntries = glossaryState.customTerms.joined(separator: "\n")
        guard glossaryEntries != normalizedEntries else {
            defaults.set(glossaryEntries, forKey: Keys.glossaryEntries)
            flushDefaults()
            return
        }

        isSyncingLegacyGlossary = true
        glossaryEntries = normalizedEntries
        isSyncingLegacyGlossary = false
    }

    private func flushDefaults() {
        // Xcode stop/re-run can terminate the app before UserDefaults async writes hit disk.
        defaults.synchronize()
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

        return normalizedSnapshot(snapshot)
    }

    private static func loadGlossarySnapshot(from defaults: UserDefaults) -> GlossarySettingsSnapshot? {
        guard let data = defaults.data(forKey: Keys.glossarySettingsSnapshot) else {
            return nil
        }

        let decoder = JSONDecoder()
        guard let snapshot = try? decoder.decode(GlossarySettingsSnapshot.self, from: data) else {
            return nil
        }

        return normalizedGlossaryState(snapshot)
    }

    private static func makeLegacySnapshot(from defaults: UserDefaults) -> ModelSettingsSnapshot {
        var snapshot = ModelSettingsSnapshot.default
        snapshot.textRefinementEnabled = defaults.object(forKey: Keys.legacyLLMEnabled) as? Bool ?? false

        let baseURL = defaults.string(forKey: Keys.legacyLLMBaseURL) ?? ""
        let apiKey = defaults.string(forKey: Keys.legacyLLMAPIKey) ?? ""
        let model = defaults.string(forKey: Keys.legacyLLMModel) ?? ""

        if !baseURL.trimmed.isEmpty || !apiKey.trimmed.isEmpty || !model.trimmed.isEmpty {
            snapshot.textConfigsByProvider[TextRefinementProvider.deepSeek] = TextRefinementProviderConfig(
                baseURL: baseURL,
                apiKey: apiKey,
                model: model
            )
        }

        return snapshot
    }

    private static func makeLegacyGlossarySnapshot(entries: String) -> GlossarySettingsSnapshot {
        GlossarySettingsSnapshot(
            enabledPresetIDs: [],
            customTerms: normalizeTerms(parseLegacyGlossaryEntries(entries))
        )
    }

    private static func normalizedSnapshot(_ snapshot: ModelSettingsSnapshot) -> ModelSettingsSnapshot {
        var normalized = snapshot
        normalized.preferredMicrophoneUID = normalized.preferredMicrophoneUID?.trimmed.nilIfEmpty
        normalized.enabledDictationSkills = normalizedDictationSkills(snapshot.enabledDictationSkills)
        var qwenConfig = normalized.asrConfigsByProvider[.qwenASR] ?? .empty
        if qwenConfig.baseURL.trimmed.isEmpty {
            qwenConfig.baseURL = "wss://dashscope.aliyuncs.com/api-ws/v1/realtime"
        }
        if qwenConfig.model.trimmed.isEmpty {
            qwenConfig.model = "qwen3-asr-flash-realtime"
        }
        normalized.asrConfigsByProvider[.qwenASR] = qwenConfig
        return normalized
    }

    private static func normalizedDictationSkills(_ skills: [DictationProcessingSkill]) -> [DictationProcessingSkill] {
        let uniqueSkills = Set(skills)
        return DictationProcessingSkill.allCases.filter { uniqueSkills.contains($0) }
    }

    private static func normalizedGlossaryState(_ snapshot: GlossarySettingsSnapshot) -> GlossarySettingsSnapshot {
        GlossarySettingsSnapshot(
            enabledPresetIDs: GlossaryPresetID.allCases.filter { snapshot.enabledPresetIDs.contains($0) },
            customTerms: normalizeTerms(snapshot.customTerms)
        )
    }

    private static func parseLegacyGlossaryEntries(_ entries: String) -> [String] {
        entries
            .split(whereSeparator: \.isNewline)
            .map(String.init)
    }

    private static func normalizeTerms(_ terms: [String]) -> [String] {
        var seen = Set<String>()
        var normalizedTerms: [String] = []

        for term in terms.map(\.trimmed) where !term.isEmpty {
            if seen.insert(term).inserted {
                normalizedTerms.append(term)
            }
        }

        return normalizedTerms
    }
}

private extension String {
    var nilIfEmpty: String? {
        isEmpty ? nil : self
    }
}
