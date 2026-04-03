import AppKit
import SwiftUI

@MainActor
final class SettingsWindowController: NSWindowController {
    init(settings: AppSettings, llmService: LLMRefinementService) {
        let view = SettingsRootView(settings: settings, llmService: llmService)
        let hostingController = NSHostingController(rootView: view)
        let window = NSWindow(contentViewController: hostingController)
        window.title = "Voily Settings"
        window.setContentSize(NSSize(width: 1120, height: 760))
        window.minSize = NSSize(width: 980, height: 700)
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
                        SettingsInfoRow(label: "语音识别模型", value: settings.selectedASRProvider.displayName)
                        SettingsInfoRow(label: "语音输入模型", value: settings.selectedTextProvider.displayName)
                        SettingsInfoRow(
                            label: "润色状态",
                            value: settings.isTextRefinementConfigured ? "已配置" : "未配置"
                        )
                        SettingsInfoRow(label: "词库词条数", value: "\(settings.glossaryItems.count)")
                    }
                }

                SettingsCard(title: "使用方式", subtitle: "当前交互约定") {
                    VStack(alignment: .leading, spacing: 12) {
                        SettingsBullet(text: "按住 Fn 开始录音，松开后自动结束并注入文本。")
                        SettingsBullet(text: "模型配置页支持默认模型选择和按服务商弹窗配置。")
                        SettingsBullet(text: "词库页可维护常用术语、产品名和专有名词。")
                    }
                }
            }
            .padding(28)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

private struct ProviderSheet: Identifiable {
    enum Kind {
        case asr(ASRProvider)
        case text(TextRefinementProvider)
    }

    let id: String
    let kind: Kind

    static func asr(_ provider: ASRProvider) -> ProviderSheet {
        ProviderSheet(id: "asr.\(provider.rawValue)", kind: .asr(provider))
    }

    static func text(_ provider: TextRefinementProvider) -> ProviderSheet {
        ProviderSheet(id: "text.\(provider.rawValue)", kind: .text(provider))
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
    @State private var statusMessage = ""
    @State private var isTestingTextModel = false
    @State private var presentedSheet: ProviderSheet?

    private let gridColumns = [
        GridItem(.flexible(), spacing: 20, alignment: .top),
        GridItem(.flexible(), spacing: 20, alignment: .top),
    ]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 30) {
                SettingsPageHeader(
                    title: "模型配置",
                    subtitle: "按模型角色选择默认 provider，点击服务商卡片弹出详细配置。"
                )

                DefaultModelsOverviewCard(
                    selectedASRProvider: $draftSelectedASRProvider,
                    selectedTextProvider: $draftSelectedTextProvider,
                    textRefinementEnabled: $draftTextRefinementEnabled,
                    asrConfig: asrDrafts[draftSelectedASRProvider] ?? .empty,
                    textConfig: textDrafts[draftSelectedTextProvider] ?? .empty
                )

                VStack(alignment: .leading, spacing: 16) {
                    SectionTitle(title: "语音识别服务商")

                    LazyVGrid(columns: gridColumns, spacing: 20) {
                        ForEach(ASRProvider.allCases) { provider in
                            ProviderServiceCard(
                                title: provider.displayName,
                                subtitle: provider.providerSummary,
                                logoName: provider.logoAssetName,
                                tag: provider.category.displayName,
                                isSelected: draftSelectedASRProvider == provider,
                                isConfigured: (asrDrafts[provider] ?? .empty).isConfigured(for: provider),
                                onOpen: { presentedSheet = .asr(provider) }
                            )
                        }
                    }
                }

                VStack(alignment: .leading, spacing: 16) {
                    SectionTitle(title: "大模型服务商")

                    LazyVGrid(columns: gridColumns, spacing: 20) {
                        ForEach(TextRefinementProvider.allCases) { provider in
                            ProviderServiceCard(
                                title: provider.displayName,
                                subtitle: provider.providerSummary,
                                logoName: provider.logoAssetName,
                                tag: "云端",
                                isSelected: draftSelectedTextProvider == provider,
                                isConfigured: (textDrafts[provider] ?? .empty).isConfigured,
                                onOpen: { presentedSheet = .text(provider) }
                            )
                        }
                    }
                }

                if !statusMessage.isEmpty {
                    Text(statusMessage)
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }
            }
            .padding(28)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .onAppear(perform: loadDrafts)
        .onChange(of: draftSelectedASRProvider) { _, newValue in
            settings.selectedASRProvider = newValue
        }
        .onChange(of: draftSelectedTextProvider) { _, newValue in
            settings.selectedTextProvider = newValue
        }
        .onChange(of: draftTextRefinementEnabled) { _, newValue in
            settings.textRefinementEnabled = newValue
        }
        .sheet(item: $presentedSheet) { sheet in
            switch sheet.kind {
            case let .asr(provider):
                ASRProviderConfigSheet(
                    provider: provider,
                    config: asrDrafts[provider] ?? .empty,
                    isSelected: draftSelectedASRProvider == provider,
                    onSave: { config, setAsDefault in
                        asrDrafts[provider] = config
                        settings.setASRConfig(config, for: provider)
                        if setAsDefault {
                            draftSelectedASRProvider = provider
                        }
                        statusMessage = "已保存 \(provider.displayName) 配置。"
                    }
                )
            case let .text(provider):
                TextRefinementProviderConfigSheet(
                    provider: provider,
                    config: textDrafts[provider] ?? .empty,
                    isSelected: draftSelectedTextProvider == provider,
                    isEnabled: draftTextRefinementEnabled,
                    llmService: llmService,
                    onSave: { config, setAsDefault in
                        textDrafts[provider] = config
                        settings.setTextRefinementConfig(config, for: provider)
                        if setAsDefault {
                            draftSelectedTextProvider = provider
                        }
                        statusMessage = "已保存 \(provider.displayName) 配置。"
                    }
                )
            }
        }
    }

    private func loadDrafts() {
        draftSelectedASRProvider = settings.selectedASRProvider
        draftSelectedTextProvider = settings.selectedTextProvider
        draftTextRefinementEnabled = settings.textRefinementEnabled
        asrDrafts = Dictionary(uniqueKeysWithValues: ASRProvider.allCases.map { ($0, settings.asrConfig(for: $0)) })
        textDrafts = Dictionary(uniqueKeysWithValues: TextRefinementProvider.allCases.map { ($0, settings.textRefinementConfig(for: $0)) })
    }
}

private struct DefaultModelsOverviewCard: View {
    @Binding var selectedASRProvider: ASRProvider
    @Binding var selectedTextProvider: TextRefinementProvider
    @Binding var textRefinementEnabled: Bool

    let asrConfig: ASRProviderConfig
    let textConfig: TextRefinementProviderConfig

    var body: some View {
        VStack(alignment: .leading, spacing: 26) {
            HStack {
                Label("默认模型", systemImage: "cpu")
                    .font(.system(size: 24, weight: .semibold))

                Spacer()

                Toggle("启用语音输入润色", isOn: $textRefinementEnabled)
                    .toggleStyle(.switch)
                    .labelsHidden()

                Text("全局生效")
                    .font(.system(size: 12, weight: .medium))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(
                        Capsule()
                            .fill(Color.primary.opacity(0.05))
                    )
            }

            HStack(alignment: .top, spacing: 18) {
                DefaultModelSelectorColumn(
                    title: "语音识别模型",
                    description: selectedASRProvider.providerSummary,
                    modelDisplayName: selectedASRProvider.modelSummary(using: asrConfig),
                    selection: $selectedASRProvider
                )

                DefaultModelSelectorColumn(
                    title: "语音输入大模型",
                    description: selectedTextProvider.providerSummary,
                    modelDisplayName: selectedTextProvider.modelSummary(using: textConfig),
                    selection: $selectedTextProvider
                )
            }
        }
        .padding(24)
        .background(
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .fill(Color(nsColor: .controlBackgroundColor))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .stroke(Color.primary.opacity(0.08), lineWidth: 1)
        )
    }
}

private struct DefaultModelSelectorColumn<SelectionValue: Hashable & CaseIterable & Identifiable & ProviderPresentable>: View where SelectionValue.AllCases: RandomAccessCollection {
    let title: String
    let description: String
    let modelDisplayName: String
    @Binding var selection: SelectionValue

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(title)
                .font(.system(size: 16, weight: .semibold))

            Picker(title, selection: $selection) {
                ForEach(Array(SelectionValue.allCases)) { option in
                    Text(option.displayName).tag(option)
                }
            }
            .pickerStyle(.menu)
            .labelsHidden()
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(Color(nsColor: .textBackgroundColor))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(Color.primary.opacity(0.08), lineWidth: 1)
            )

            Text(modelDisplayName)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.primary)

            Text(description)
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private protocol ProviderPresentable {
    var displayName: String { get }
}

extension ASRProvider: ProviderPresentable {}
extension TextRefinementProvider: ProviderPresentable {}

private struct SectionTitle: View {
    let title: String

    var body: some View {
        Text(title)
            .font(.system(size: 18, weight: .semibold))
    }
}

private struct ProviderServiceCard: View {
    let title: String
    let subtitle: String
    let logoName: String
    let tag: String
    let isSelected: Bool
    let isConfigured: Bool
    let onOpen: () -> Void

    var body: some View {
        Button(action: onOpen) {
            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .center, spacing: 14) {
                    ProviderLogoIcon(name: logoName)

                    VStack(alignment: .leading, spacing: 6) {
                        HStack(spacing: 10) {
                            Text(title)
                                .font(.system(size: 17, weight: .semibold))

                            TagBadge(text: tag)

                            if isSelected {
                                TagBadge(text: "默认")
                            }
                        }

                        Text(subtitle)
                            .font(.system(size: 13))
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    Spacer(minLength: 12)

                    Circle()
                        .fill(isConfigured ? Color.green : Color.secondary.opacity(0.25))
                        .frame(width: 12, height: 12)
                }
                .padding(22)

                Divider()
                    .overlay(Color.primary.opacity(0.04))

                HStack {
                    Text("点击配置")
                        .font(.system(size: 15, weight: .medium))
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.tertiary)
                }
                .padding(.horizontal, 22)
                .padding(.vertical, 18)
            }
            .frame(maxWidth: .infinity, minHeight: 176, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .fill(Color(nsColor: .controlBackgroundColor))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .stroke(isSelected ? Color.accentColor.opacity(0.28) : Color.primary.opacity(0.08), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }
}

private struct TagBadge: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.system(size: 12, weight: .medium))
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(
                Capsule()
                    .fill(Color.primary.opacity(0.06))
            )
            .foregroundStyle(.secondary)
    }
}

private struct ASRProviderConfigSheet: View {
    let provider: ASRProvider
    let config: ASRProviderConfig
    let isSelected: Bool
    let onSave: (ASRProviderConfig, Bool) -> Void

    @Environment(\.dismiss) private var dismiss

    @State private var draftConfig = ASRProviderConfig.empty
    @State private var setAsDefault = false

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            SheetHeader(
                logoName: provider.logoAssetName,
                title: provider.displayName,
                subtitle: provider.providerSummary
            )

            if provider.category == .local {
                LocalProviderFields(config: $draftConfig)
            } else {
                CloudProviderFields(
                    config: $draftConfig,
                    modelPlaceholder: provider.defaultModelPlaceholder
                )
            }

            Toggle("设为默认语音识别模型", isOn: $setAsDefault)
                .toggleStyle(.checkbox)

            SheetFooter(
                statusText: provider.category == .local ? "本地 provider 仅保存路径和参数，不会做可执行性校验。" : "云端 provider 仅保存连接参数，真实转写接入在后续版本完成。",
                onCancel: { dismiss() },
                onSave: {
                    onSave(draftConfig, setAsDefault)
                    dismiss()
                }
            )
        }
        .padding(24)
        .frame(width: 520)
        .onAppear {
            draftConfig = config
            setAsDefault = isSelected
        }
    }
}

private struct TextRefinementProviderConfigSheet: View {
    let provider: TextRefinementProvider
    let config: TextRefinementProviderConfig
    let isSelected: Bool
    let isEnabled: Bool
    let llmService: LLMRefinementService
    let onSave: (TextRefinementProviderConfig, Bool) -> Void

    @Environment(\.dismiss) private var dismiss

    @State private var draftConfig = TextRefinementProviderConfig.empty
    @State private var setAsDefault = false
    @State private var statusMessage = ""
    @State private var isTesting = false

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            SheetHeader(
                logoName: provider.logoAssetName,
                title: provider.displayName,
                subtitle: provider.providerSummary
            )

            TextRefinementProviderFields(provider: provider, config: $draftConfig)

            Toggle("设为默认语音输入模型", isOn: $setAsDefault)
                .toggleStyle(.checkbox)

            HStack(spacing: 12) {
                Button("测试连接") {
                    testConnection()
                }
                .disabled(isTesting || !draftConfig.isConfigured)

                if isTesting {
                    ProgressView()
                        .controlSize(.small)
                }

                Text(statusMessage.isEmpty ? defaultTestingHint : statusMessage)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }

            SheetFooter(
                statusText: isEnabled ? "当前已启用语音输入润色，保存后会影响后续默认 provider。" : "当前未启用语音输入润色，保存配置后不会立即参与链路。",
                onCancel: { dismiss() },
                onSave: {
                    onSave(draftConfig, setAsDefault)
                    dismiss()
                }
            )
        }
        .padding(24)
        .frame(width: 560)
        .onAppear {
            draftConfig = config
            setAsDefault = isSelected
        }
    }

    private var defaultTestingHint: String {
        "会使用当前表单内容发起一次真实请求。"
    }

    private func testConnection() {
        isTesting = true
        statusMessage = "正在测试连接..."

        let suiteName = "Voily.SettingsSheet.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        let tempSettings = AppSettings(defaults: defaults)
        tempSettings.selectedTextProvider = provider
        tempSettings.setTextRefinementConfig(draftConfig, for: provider)

        Task {
            defer { isTesting = false }

            do {
                try await llmService.testConnection(settings: tempSettings)
                statusMessage = "连接成功，可以用于语音输入润色。"
            } catch {
                statusMessage = "测试失败：\(error.localizedDescription)"
            }
        }
    }
}

private struct SheetHeader: View {
    let logoName: String
    let title: String
    let subtitle: String

    var body: some View {
        HStack(spacing: 14) {
            ProviderLogoIcon(name: logoName, size: 50)

            VStack(alignment: .leading, spacing: 6) {
                Text(title)
                    .font(.system(size: 22, weight: .semibold))

                Text(subtitle)
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
            }
        }
    }
}

private struct SheetFooter: View {
    let statusText: String
    let onCancel: () -> Void
    let onSave: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(statusText)
                .font(.system(size: 12))
                .foregroundStyle(.secondary)

            HStack {
                Spacer()

                Button("取消", action: onCancel)
                Button("保存", action: onSave)
                    .keyboardShortcut(.defaultAction)
            }
        }
    }
}

private struct ProviderLogoIcon: View {
    let name: String
    var size: CGFloat = 44

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color.primary.opacity(0.04))

            BrandIconImage(resourceName: name)
                .frame(width: size - 12, height: size - 12)
        }
        .frame(width: size, height: size)
    }
}

private struct BrandIconImage: View {
    let resourceName: String

    var body: some View {
        Group {
            if let image = BrandIconLoader.image(named: resourceName) {
                Image(nsImage: image)
                    .resizable()
                    .interpolation(.high)
                    .aspectRatio(contentMode: .fit)
            } else {
                Image(systemName: "photo")
                    .resizable()
                    .scaledToFit()
                    .foregroundStyle(.secondary)
                    .padding(6)
            }
        }
    }
}

private enum BrandIconLoader {
    static func image(named name: String) -> NSImage? {
        guard let url = ResourceBundle.current.url(forResource: name, withExtension: "png", subdirectory: "BrandIcons") else {
            return nil
        }

        return NSImage(contentsOf: url)
    }
}

private enum ResourceBundle {
    static var current: Bundle {
#if SWIFT_PACKAGE
        return .module
#else
        return Bundle.main
#endif
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
        settings.setASRConfig(
            ASRProviderConfig(
                executablePath: "/opt/models/sensevoice",
                modelPath: "/opt/models/sensevoice-small",
                additionalArguments: "--vad true",
                baseURL: "",
                apiKey: "",
                model: ""
            ),
            for: .senseVoice
        )
        settings.setTextRefinementConfig(
            TextRefinementProviderConfig(
                baseURL: "https://api.deepseek.com/v1",
                apiKey: "sk-preview-123456",
                model: "deepseek-chat"
            ),
            for: .deepSeek
        )
        settings.setTextRefinementConfig(
            TextRefinementProviderConfig(
                baseURL: "https://dashscope.aliyuncs.com/compatible-mode/v1",
                apiKey: "dashscope-preview-key",
                model: "qwen-plus"
            ),
            for: .dashScope
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

private extension ASRProvider {
    var providerSummary: String {
        switch self {
        case .whisperCpp:
            return "本地运行，适合离线和可控部署。"
        case .senseVoice:
            return "阿里系本地识别模型，偏向轻量和中文场景。"
        case .doubaoStreaming:
            return "流式识别优先，适合低延迟语音输入。"
        case .qwenASR:
            return "云端 ASR 路线，便于后续接入统一平台。"
        }
    }

    var logoAssetName: String {
        switch self {
        case .whisperCpp:
            return "openai"
        case .senseVoice:
            return "bailian"
        case .doubaoStreaming:
            return "doubao"
        case .qwenASR:
            return "qwen"
        }
    }

    var defaultModelPlaceholder: String {
        switch self {
        case .whisperCpp:
            return "ggml-large-v3"
        case .senseVoice:
            return "sensevoice-small"
        case .doubaoStreaming:
            return "doubao-speech-realtime"
        case .qwenASR:
            return "qwen-asr"
        }
    }

    func modelSummary(using config: ASRProviderConfig) -> String {
        switch category {
        case .local:
            let path = config.modelPath.trimmingCharacters(in: .whitespacesAndNewlines)
            return path.isEmpty ? displayName : URL(fileURLWithPath: path).lastPathComponent
        case .cloud:
            let model = config.model.trimmingCharacters(in: .whitespacesAndNewlines)
            return model.isEmpty ? displayName : model
        }
    }
}

private extension TextRefinementProvider {
    var providerSummary: String {
        switch self {
        case .deepSeek:
            return "速度优先，适合文本纠错和保守润色。"
        case .dashScope:
            return "阿里云百炼通道，便于后续扩展 Qwen 系列。"
        case .volcengine:
            return "火山引擎通道，适合后续接入豆包大模型。"
        }
    }

    var logoAssetName: String {
        switch self {
        case .deepSeek:
            return "deepseek"
        case .dashScope:
            return "bailian"
        case .volcengine:
            return "volcengine"
        }
    }

    func modelSummary(using config: TextRefinementProviderConfig) -> String {
        let model = config.model.trimmingCharacters(in: .whitespacesAndNewlines)
        return model.isEmpty ? displayName : model
    }
}

@available(macOS 26.0, *)
#Preview("Settings Home") {
    SettingsHomePage(settings: SettingsPreviewData.configuredSettings())
        .frame(width: 760, height: 700)
}

@available(macOS 26.0, *)
#Preview("Settings Model") {
    ModelSettingsPage(
        settings: SettingsPreviewData.configuredSettings(),
        llmService: LLMRefinementService()
    )
    .frame(width: 1120, height: 760)
}

@available(macOS 26.0, *)
#Preview("Settings Glossary") {
    GlossarySettingsPage(settings: SettingsPreviewData.configuredSettings())
        .frame(width: 760, height: 700)
}
