import AppKit
import SwiftUI

@MainActor
final class SettingsWindowController: NSWindowController {
    init(settings: AppSettings, llmService: LLMRefinementService) {
        let view = SettingsRootView(settings: settings, llmService: llmService)
        let hostingController = NSHostingController(rootView: view)
        let window = NSWindow(contentViewController: hostingController)
        window.title = "Voily Settings"
        window.setContentSize(NSSize(width: 980, height: 680))
        window.minSize = NSSize(width: 900, height: 620)
        window.styleMask = [.titled, .closable, .miniaturizable, .resizable]
        window.center()
        super.init(window: window)
        shouldCascadeWindows = true
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func show() {
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}

private enum SettingsPage: String, CaseIterable, Identifiable, Hashable {
    case home
    case model
    case glossary

    var id: String { rawValue }

    var title: String {
        switch self {
        case .home:
            return "首页"
        case .model:
            return "模型配置"
        case .glossary:
            return "词库配置"
        }
    }

    var systemImage: String {
        switch self {
        case .home:
            return "house"
        case .model:
            return "cpu"
        case .glossary:
            return "text.book.closed"
        }
    }
}

private struct SettingsRootView: View {
    @Bindable var settings: AppSettings
    let llmService: LLMRefinementService

    @State private var selection: SettingsPage? = .home

    var body: some View {
        NavigationSplitView {
            SettingsSidebar(selection: $selection)
                .navigationSplitViewColumnWidth(min: 220, ideal: 240, max: 260)
        } detail: {
            Group {
                switch selection ?? .home {
                case .home:
                    SettingsHomePage(settings: settings)
                case .model:
                    ModelSettingsPage(settings: settings, llmService: llmService)
                case .glossary:
                    GlossarySettingsPage(settings: settings)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color(nsColor: .windowBackgroundColor))
        }
    }
}

private struct SettingsSidebar: View {
    @Binding var selection: SettingsPage?

    var body: some View {
        List(SettingsPage.allCases, selection: $selection) { page in
            NavigationLink(value: page) {
                Label(page.title, systemImage: page.systemImage)
                    .font(.system(size: 14, weight: .medium))
                    .padding(.vertical, 6)
            }
            .tag(page)
        }
        .listStyle(.sidebar)
        .safeAreaInset(edge: .top) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Voily")
                    .font(.system(size: 22, weight: .semibold))
                Text("语音输入与纠错")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 16)
            .padding(.top, 20)
            .padding(.bottom, 14)
            .background(.regularMaterial)
        }
    }
}

private struct SettingsHomePage: View {
    @Bindable var settings: AppSettings

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                SettingsPageHeader(
                    title: "首页",
                    subtitle: "查看当前语音输入配置，并快速调整常用设置。"
                )

                SettingsCard(title: "基础设置", subtitle: "语言与纠错开关") {
                    VStack(alignment: .leading, spacing: 18) {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("识别语言")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(.secondary)

                            Picker("识别语言", selection: $settings.selectedLanguageCode) {
                                ForEach(SupportedLanguage.allCases) { language in
                                    Text(language.displayName)
                                        .tag(language.rawValue)
                                }
                            }
                            .labelsHidden()
                            .pickerStyle(.menu)
                        }

                        Toggle("启用语音输入润色", isOn: $settings.textRefinementEnabled)
                            .toggleStyle(.switch)

                        Divider()

                        SettingsInfoRow(label: "当前语言", value: settings.selectedLanguage.displayName)
                        SettingsInfoRow(
                            label: "语音识别模型",
                            value: settings.selectedASRProvider.displayName
                        )
                        SettingsInfoRow(
                            label: "语音输入模型",
                            value: settings.selectedTextProvider.displayName
                        )
                        SettingsInfoRow(
                            label: "润色状态",
                            value: settings.isTextRefinementConfigured ? "已配置" : "未配置"
                        )
                        SettingsInfoRow(
                            label: "词库词条数",
                            value: "\(settings.glossaryItems.count)"
                        )
                    }
                }

                SettingsCard(title: "使用方式", subtitle: "当前交互约定") {
                    VStack(alignment: .leading, spacing: 12) {
                        SettingsBullet(text: "按住 Fn 开始录音，松开后自动结束并注入文本。")
                        SettingsBullet(text: "语音识别与文本润色已拆分为两套模型配置，后续可独立扩展。")
                        SettingsBullet(text: "词库页可维护常用术语、产品名和专有名词。")
                    }
                }
            }
            .padding(28)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

private struct ModelSettingsPage: View {
    @Bindable var settings: AppSettings
    let llmService: LLMRefinementService

    @State private var draftSelectedASRProvider: ASRProvider = .whisperCpp
    @State private var draftSelectedTextProvider: TextRefinementProvider = .deepSeek
    @State private var draftTextRefinementEnabled = false
    @State private var asrDrafts: [ASRProvider: ASRProviderConfig] = [:]
    @State private var textDrafts: [TextRefinementProvider: TextRefinementProviderConfig] = [:]
    @State private var asrStatusMessage = ""
    @State private var textStatusMessage = ""
    @State private var isTestingTextModel = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                SettingsPageHeader(
                    title: "模型配置",
                    subtitle: "配置语音识别与语音输入两个模型的 provider、模型名与连接参数。"
                )

                SpeechRecognitionSettingsSection(
                    selectedProvider: $draftSelectedASRProvider,
                    drafts: $asrDrafts,
                    statusMessage: $asrStatusMessage,
                    onSave: saveASRSettings
                )

                TextRefinementSettingsSection(
                    llmService: llmService,
                    selectedProvider: $draftSelectedTextProvider,
                    isEnabled: $draftTextRefinementEnabled,
                    drafts: $textDrafts,
                    statusMessage: $textStatusMessage,
                    isTesting: $isTestingTextModel,
                    onSave: saveTextSettings,
                    onTest: testTextConnection
                )
            }
            .padding(28)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .onAppear(perform: loadDrafts)
    }

    private func loadDrafts() {
        draftSelectedASRProvider = settings.selectedASRProvider
        draftSelectedTextProvider = settings.selectedTextProvider
        draftTextRefinementEnabled = settings.textRefinementEnabled
        asrDrafts = Dictionary(
            uniqueKeysWithValues: ASRProvider.allCases.map { provider in
                (provider, settings.asrConfig(for: provider))
            }
        )
        textDrafts = Dictionary(
            uniqueKeysWithValues: TextRefinementProvider.allCases.map { provider in
                (provider, settings.textRefinementConfig(for: provider))
            }
        )
    }

    private func saveASRSettings() {
        settings.selectedASRProvider = draftSelectedASRProvider
        for provider in ASRProvider.allCases {
            settings.setASRConfig(asrDrafts[provider] ?? .empty, for: provider)
        }

        asrStatusMessage = "已保存语音识别模型配置。"
    }

    private func saveTextSettings() {
        settings.selectedTextProvider = draftSelectedTextProvider
        settings.textRefinementEnabled = draftTextRefinementEnabled
        for provider in TextRefinementProvider.allCases {
            settings.setTextRefinementConfig(textDrafts[provider] ?? .empty, for: provider)
        }

        textStatusMessage = "已保存语音输入模型配置。"
    }

    private func testTextConnection() {
        saveTextSettings()
        textStatusMessage = "正在测试连接..."
        isTestingTextModel = true

        Task {
            defer { isTestingTextModel = false }

            do {
                try await llmService.testConnection(settings: settings)
                textStatusMessage = "连接成功，可以用于语音输入润色。"
            } catch {
                textStatusMessage = "测试失败：\(error.localizedDescription)"
            }
        }
    }
}

private struct SpeechRecognitionSettingsSection: View {
    @Binding var selectedProvider: ASRProvider
    @Binding var drafts: [ASRProvider: ASRProviderConfig]
    @Binding var statusMessage: String

    let onSave: () -> Void

    private var currentConfig: Binding<ASRProviderConfig> {
        Binding(
            get: { drafts[selectedProvider] ?? .empty },
            set: { drafts[selectedProvider] = $0 }
        )
    }

    var body: some View {
        SettingsCard(title: "语音识别模型", subtitle: "选择识别 provider，并配置本地模型或云端连接参数") {
            VStack(alignment: .leading, spacing: 18) {
                ProviderPickerRow(
                    title: "Provider",
                    subtitle: selectedProvider.category.displayName
                ) {
                    Picker("语音识别 Provider", selection: $selectedProvider) {
                        ForEach(ASRProvider.allCases) { provider in
                            Text(provider.displayName).tag(provider)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                    .frame(maxWidth: 280, alignment: .leading)
                }

                Group {
                    if selectedProvider.category == .local {
                        LocalProviderFields(config: currentConfig)
                    } else {
                        CloudProviderFields(
                            config: currentConfig,
                            modelPlaceholder: cloudASRPlaceholder(for: selectedProvider)
                        )
                    }
                }

                Divider()

                HStack(spacing: 12) {
                    Button("保存") {
                        onSave()
                    }

                    Text(statusMessage.isEmpty ? defaultStatusText : statusMessage)
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }

                ConfigStatusRow(
                    label: "当前状态",
                    value: (drafts[selectedProvider] ?? .empty).isConfigured(for: selectedProvider) ? "已配置" : "未配置"
                )
                ConfigStatusRow(
                    label: "Provider 类型",
                    value: selectedProvider.category.displayName
                )
                ConfigStatusRow(
                    label: "测试能力",
                    value: selectedProvider.category == .local ? "后续开放" : "后续接入"
                )
            }
        }
    }

    private var defaultStatusText: String {
        switch selectedProvider.category {
        case .local:
            return "本地 provider 当前仅保存路径与参数，不校验可执行文件。"
        case .cloud:
            return "云端 provider 当前仅保存连接参数，真实接入在后续迭代。"
        }
    }

    private func cloudASRPlaceholder(for provider: ASRProvider) -> String {
        switch provider {
        case .doubaoStreaming:
            return "doubao-speech-realtime"
        case .qwenASR:
            return "qwen-asr"
        case .whisperCpp, .senseVoice:
            return ""
        }
    }
}

private struct TextRefinementSettingsSection: View {
    let llmService: LLMRefinementService

    @Binding var selectedProvider: TextRefinementProvider
    @Binding var isEnabled: Bool
    @Binding var drafts: [TextRefinementProvider: TextRefinementProviderConfig]
    @Binding var statusMessage: String
    @Binding var isTesting: Bool

    let onSave: () -> Void
    let onTest: () -> Void

    private var currentConfig: Binding<TextRefinementProviderConfig> {
        Binding(
            get: { drafts[selectedProvider] ?? .empty },
            set: { drafts[selectedProvider] = $0 }
        )
    }

    var body: some View {
        SettingsCard(title: "语音输入模型", subtitle: "配置识别结果的润色与纠错模型") {
            VStack(alignment: .leading, spacing: 18) {
                Toggle("启用语音输入润色", isOn: $isEnabled)
                    .toggleStyle(.switch)

                ProviderPickerRow(
                    title: "Provider",
                    subtitle: "云端"
                ) {
                    Picker("语音输入 Provider", selection: $selectedProvider) {
                        ForEach(TextRefinementProvider.allCases) { provider in
                            Text(provider.displayName).tag(provider)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                    .frame(maxWidth: 280, alignment: .leading)
                }

                TextRefinementProviderFields(
                    provider: selectedProvider,
                    config: currentConfig
                )

                Divider()

                HStack(spacing: 12) {
                    Button("保存") {
                        onSave()
                    }
                    .keyboardShortcut("s", modifiers: [.command])

                    Button("测试连接") {
                        onTest()
                    }
                    .disabled(isTesting || !(drafts[selectedProvider] ?? .empty).isConfigured)

                    if isTesting {
                        ProgressView()
                            .controlSize(.small)
                    }

                    Text(statusMessage.isEmpty ? "保存后可对当前 provider 发起一次真实测试请求。" : statusMessage)
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }

                ConfigStatusRow(
                    label: "当前状态",
                    value: (drafts[selectedProvider] ?? .empty).isConfigured ? "已配置" : "未配置"
                )
                ConfigStatusRow(
                    label: "启用状态",
                    value: isEnabled ? "已启用" : "未启用"
                )
            }
        }
    }
}

private struct ProviderPickerRow<Content: View>: View {
    let title: String
    let subtitle: String
    @ViewBuilder let content: Content

    var body: some View {
        HStack(alignment: .center, spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.system(size: 13, weight: .semibold))
                Text(subtitle)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 12)

            content
        }
    }
}

private struct LocalProviderFields: View {
    @Binding var config: ASRProviderConfig

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            SettingsFormField(title: "可执行文件路径") {
                TextField("/usr/local/bin/whisper-cli", text: $config.executablePath)
                    .textFieldStyle(.roundedBorder)
            }

            SettingsFormField(title: "模型文件路径") {
                TextField("/models/ggml-base.bin", text: $config.modelPath)
                    .textFieldStyle(.roundedBorder)
            }

            SettingsFormField(title: "附加参数") {
                TextField("--language zh --threads 4", text: $config.additionalArguments)
                    .textFieldStyle(.roundedBorder)
            }
        }
    }
}

private struct CloudProviderFields: View {
    @Binding var config: ASRProviderConfig
    let modelPlaceholder: String

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            SettingsFormField(title: "API Base URL") {
                TextField("https://api.example.com/v1", text: $config.baseURL)
                    .textFieldStyle(.roundedBorder)
            }

            SettingsFormField(title: "API Key") {
                SecureField("sk-...", text: $config.apiKey)
                    .textFieldStyle(.roundedBorder)
            }

            SettingsFormField(title: "Model") {
                TextField(modelPlaceholder, text: $config.model)
                    .textFieldStyle(.roundedBorder)
            }
        }
    }
}

private struct TextRefinementProviderFields: View {
    let provider: TextRefinementProvider
    @Binding var config: TextRefinementProviderConfig

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            SettingsFormField(title: "API Base URL") {
                TextField(baseURLPlaceholder, text: $config.baseURL)
                    .textFieldStyle(.roundedBorder)
            }

            SettingsFormField(title: "API Key") {
                SecureField("sk-...", text: $config.apiKey)
                    .textFieldStyle(.roundedBorder)
            }

            SettingsFormField(title: "Model") {
                TextField(modelPlaceholder, text: $config.model)
                    .textFieldStyle(.roundedBorder)
            }
        }
    }

    private var baseURLPlaceholder: String {
        switch provider {
        case .deepSeek:
            return "https://api.deepseek.com/v1"
        case .dashScope:
            return "https://dashscope.aliyuncs.com/compatible-mode/v1"
        case .volcengine:
            return "https://ark.cn-beijing.volces.com/api/v3"
        }
    }

    private var modelPlaceholder: String {
        switch provider {
        case .deepSeek:
            return "deepseek-chat"
        case .dashScope:
            return "qwen-plus"
        case .volcengine:
            return "doubao-1.5-pro"
        }
    }
}

private struct ConfigStatusRow: View {
    let label: String
    let value: String

    var body: some View {
        HStack {
            Text(label)
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .fontWeight(.medium)
        }
        .font(.system(size: 13))
    }
}

private struct GlossarySettingsPage: View {
    @Bindable var settings: AppSettings

    @State private var draftEntries: String = ""
    @State private var statusMessage: String = ""

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                SettingsPageHeader(
                    title: "词库配置",
                    subtitle: "维护常见专有名词。每行一个词条，后续可接入纠错链路。"
                )

                SettingsCard(title: "词条编辑", subtitle: "建议一行一个词条，方便后续处理") {
                    VStack(alignment: .leading, spacing: 14) {
                        TextEditor(text: $draftEntries)
                            .font(.system(size: 13))
                            .frame(minHeight: 260)
                            .padding(10)
                            .background(
                                RoundedRectangle(cornerRadius: 12)
                                    .fill(Color(nsColor: .textBackgroundColor))
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 12)
                                    .stroke(Color.primary.opacity(0.08), lineWidth: 1)
                            )

                        HStack(spacing: 12) {
                            Button("保存词库") {
                                save()
                            }

                            Button("清空") {
                                draftEntries = ""
                                save(status: "词库已清空。")
                            }

                            Text(statusMessage.isEmpty ? "当前共 \(settings.glossaryItems.count) 条词条。" : statusMessage)
                                .font(.system(size: 12))
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                SettingsCard(title: "预览", subtitle: "保存后会写入本地设置") {
                    if settings.glossaryItems.isEmpty && draftEntries.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        Text("还没有词条。可以先添加产品名、术语缩写或专有人名。")
                            .foregroundStyle(.secondary)
                    } else {
                        LazyVStack(alignment: .leading, spacing: 8) {
                            ForEach(previewItems.prefix(12), id: \.self) { item in
                                Text(item)
                                    .font(.system(size: 13, weight: .medium))
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 8)
                                    .background(
                                        Capsule()
                                            .fill(Color.primary.opacity(0.06))
                                    )
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }
            .padding(28)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .onAppear {
            draftEntries = settings.glossaryEntries
        }
    }

    private var previewItems: [String] {
        draftEntries
            .split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    private func save(status: String = "词库已保存。") {
        settings.glossaryEntries = draftEntries
        statusMessage = status
    }
}

private struct SettingsPageHeader: View {
    let title: String
    let subtitle: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.system(size: 30, weight: .semibold))

            Text(subtitle)
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
        }
    }
}

private struct SettingsCard<Content: View>: View {
    let title: String
    let subtitle: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.system(size: 17, weight: .semibold))

                Text(subtitle)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }

            content
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color(nsColor: .controlBackgroundColor))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(Color.primary.opacity(0.06), lineWidth: 1)
        )
    }
}

private struct SettingsFormField<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.secondary)

            content
        }
    }
}

private struct SettingsInfoRow: View {
    let label: String
    let value: String

    var body: some View {
        HStack {
            Text(label)
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .fontWeight(.medium)
        }
        .font(.system(size: 13))
    }
}

private struct SettingsBullet: View {
    let text: String

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Circle()
                .fill(Color.accentColor)
                .frame(width: 6, height: 6)
                .padding(.top, 6)

            Text(text)
                .font(.system(size: 13))
                .foregroundStyle(.primary)
        }
    }
}

@MainActor
private enum SettingsPreviewData {
    static func configuredSettings() -> AppSettings {
        let suiteName = "Voily.SettingsPreview.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        let settings = AppSettings(defaults: defaults)
        settings.selectedLanguage = .simplifiedChinese
        settings.selectedASRProvider = .doubaoStreaming
        settings.selectedTextProvider = .deepSeek
        settings.textRefinementEnabled = true
        settings.setASRConfig(
            ASRProviderConfig(
                executablePath: "",
                modelPath: "",
                additionalArguments: "",
                baseURL: "https://openspeech.bytedance.com/api/v1",
                apiKey: "volc-asr-key",
                model: "doubao-speech-realtime"
            ),
            for: .doubaoStreaming
        )
        settings.setASRConfig(
            ASRProviderConfig(
                executablePath: "/opt/homebrew/bin/whisper-cli",
                modelPath: "/models/ggml-base.bin",
                additionalArguments: "--language zh",
                baseURL: "",
                apiKey: "",
                model: ""
            ),
            for: .whisperCpp
        )
        settings.setTextRefinementConfig(
            TextRefinementProviderConfig(
                baseURL: "https://api.deepseek.com/v1",
                apiKey: "sk-preview-123456",
                model: "deepseek-chat"
            ),
            for: .deepSeek
        )
        settings.glossaryEntries = """
        OpenAI
        Whisper
        JSON
        Python
        Voily
        """
        return settings
    }

    static func emptySettings() -> AppSettings {
        let suiteName = "Voily.SettingsPreview.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        return AppSettings(defaults: defaults)
    }
}

@available(macOS 26.0, *)
#Preview("Settings Home") {
    SettingsHomePage(settings: SettingsPreviewData.configuredSettings())
        .frame(width: 740, height: 680)
}

@available(macOS 26.0, *)
#Preview("Settings Model") {
    ModelSettingsPage(
        settings: SettingsPreviewData.configuredSettings(),
        llmService: LLMRefinementService()
    )
    .frame(width: 740, height: 680)
}

@available(macOS 26.0, *)
#Preview("Settings Model Empty") {
    ModelSettingsPage(
        settings: SettingsPreviewData.emptySettings(),
        llmService: LLMRefinementService()
    )
    .frame(width: 740, height: 680)
}

@available(macOS 26.0, *)
#Preview("Settings Glossary") {
    GlossarySettingsPage(settings: SettingsPreviewData.configuredSettings())
        .frame(width: 740, height: 680)
}
