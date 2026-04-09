import AppKit
import SwiftUI

@MainActor
final class SettingsWindowController: NSWindowController {
    init(settings: AppSettings, usageStore: UsageStore, llmService: LLMRefinementService, managedASRModels: ManagedASRModelStore) {
        let view = SettingsRootView(settings: settings, usageStore: usageStore, llmService: llmService, managedASRModels: managedASRModels)
        let hostingController = NSHostingController(rootView: view)
        let window = NSWindow(contentViewController: hostingController)
        let minimumContentSize = NSSize(width: 1120, height: 760)

        window.title = ""
        window.titleVisibility = .hidden
        window.setContentSize(minimumContentSize)
        window.contentMinSize = minimumContentSize
        window.minSize = window.frameRect(forContentRect: NSRect(origin: .zero, size: minimumContentSize)).size
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
    case settings

    var id: String { rawValue }

    var title: String {
        switch self {
        case .home:
            return "首页"
        case .model:
            return "模型"
        case .glossary:
            return "词库"
        case .settings:
            return "设置"
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
        case .settings:
            return "gearshape"
        }
    }
}

private struct SettingsRootView: View {
    @Bindable var settings: AppSettings
    let usageStore: UsageStore
    let llmService: LLMRefinementService
    let managedASRModels: ManagedASRModelStore

    @State private var selection: SettingsPage? = .home
    @State private var columnVisibility: NavigationSplitViewVisibility = .all

    var body: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            SettingsSidebar(selection: $selection)
                .navigationSplitViewColumnWidth(min: 220, ideal: 220, max: 220)
        } detail: {
            Group {
                switch selection ?? .home {
                case .home:
                    DashboardHomePage(usageStore: usageStore)
                case .model:
                    ModelSettingsPage(settings: settings, llmService: llmService, managedASRModels: managedASRModels)
                case .glossary:
                    GlossarySettingsPage(settings: settings)
                case .settings:
                    GeneralSettingsPage(settings: settings)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color(nsColor: .windowBackgroundColor))
        }
        .toolbar {
            ToolbarItem(placement: .navigation) {
                Button(action: toggleSidebar) {
                    Label(sidebarToggleTitle, systemImage: "sidebar.left")
                }
                .help(sidebarToggleTitle)
            }
        }
    }

    private var sidebarToggleTitle: String {
        columnVisibility == .detailOnly ? "显示侧边栏" : "隐藏侧边栏"
    }

    private func toggleSidebar() {
        columnVisibility = columnVisibility == .detailOnly ? .all : .detailOnly
    }
}

private struct SettingsSidebar: View {
    @Binding var selection: SettingsPage?
    private let backgroundColor = Color(nsColor: .windowBackgroundColor)

    var body: some View {
        VStack(spacing: 0) {
            SidebarHeader()

            List(SettingsPage.allCases, selection: $selection) { page in
                NavigationLink(value: page) {
                    Label(page.title, systemImage: page.systemImage)
                        .font(.system(size: 14, weight: .medium))
                        .padding(.vertical, 6)
                }
                .tag(page)
            }
            .listStyle(.sidebar)
            .scrollContentBackground(.hidden)
            .background(backgroundColor)
        }
        .background(backgroundColor)
    }
}

private struct SidebarHeader: View {
    private let backgroundColor = Color(nsColor: .windowBackgroundColor)

    var body: some View {
        HStack(spacing: 12) {
            SidebarAppIcon()
                .frame(width: 44, height: 44)

            Text("Voily")
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(.primary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 16)
        .padding(.top, 20)
        .padding(.bottom, 16)
        .background(backgroundColor)
    }
}

private struct SidebarAppIcon: View {
    var body: some View {
        Group {
            if let image = NSApp.applicationIconImage {
                Image(nsImage: image)
                    .resizable()
                    .interpolation(.high)
                    .aspectRatio(contentMode: .fit)
            } else {
                Image(systemName: "app.fill")
                    .resizable()
                    .scaledToFit()
                    .foregroundStyle(.secondary)
                    .padding(6)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
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
    @Bindable var managedASRModels: ManagedASRModelStore

    @State private var draftSelectedASRProvider: ASRProvider = .senseVoice
    @State private var draftSelectedTextProvider: TextRefinementProvider = .deepSeek
    @State private var draftTextRefinementEnabled = false
    @State private var draftEnabledDictationSkills: [DictationProcessingSkill] = []
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
                    title: "模型",
                    subtitle: "按模型角色选择默认 provider。按住 Fn 为普通听写，双击 Fn 为快捷翻译。"
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
                            asrProviderCard(for: provider)
                        }
                    }
                }

                VStack(alignment: .leading, spacing: 16) {
                    SectionTitle(title: "大模型服务商")

                    LazyVGrid(columns: gridColumns, spacing: 20) {
                        ForEach(TextRefinementProvider.allCases) { provider in
                            let isConfigured = (textDrafts[provider] ?? .empty).isConfigured
                            ProviderServiceCard(
                                title: provider.displayName,
                                subtitle: provider.providerSummary,
                                logoName: provider.logoAssetName,
                                tag: "云端",
                                isSelected: draftSelectedTextProvider == provider,
                                isConfigured: isConfigured,
                                statusText: isConfigured ? "已配置" : "未配置",
                                onOpen: { presentedSheet = .text(provider) }
                            )
                        }
                    }
                }

                DictationSkillsCard(
                    enabledSkills: $draftEnabledDictationSkills,
                    isTextRefinementEnabled: draftTextRefinementEnabled
                )

                if !statusMessage.isEmpty {
                    Text(statusMessage)
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }
            }
            .padding(28)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .scrollIndicators(.hidden)
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
        .onChange(of: draftEnabledDictationSkills) { _, newValue in
            settings.setEnabledDictationSkills(newValue)
        }
        .sheet(item: $presentedSheet) { sheet in
            switch sheet.kind {
            case let .asr(provider):
                ASRProviderConfigSheet(
                    provider: provider,
                    config: asrDrafts[provider] ?? .empty,
                    managedState: managedASRModels.state(for: provider),
                    estimatedDownload: managedASRModels.estimatedDownload(for: provider),
                    onInstall: { managedASRModels.install(provider: provider) },
                    onUninstall: { managedASRModels.uninstall(provider: provider) },
                    onSave: { config in
                        asrDrafts[provider] = config
                        settings.setASRConfig(config, for: provider)
                        statusMessage = "已保存 \(provider.displayName) 配置。"
                    }
                )
            case let .text(provider):
                TextRefinementProviderConfigSheet(
                    provider: provider,
                    config: textDrafts[provider] ?? .empty,
                    isEnabled: draftTextRefinementEnabled,
                    llmService: llmService,
                    onSave: { config in
                        textDrafts[provider] = config
                        settings.setTextRefinementConfig(config, for: provider)
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
        draftEnabledDictationSkills = settings.enabledDictationSkills
        asrDrafts = Dictionary(uniqueKeysWithValues: ASRProvider.allCases.map { ($0, settings.asrConfig(for: $0)) })
        textDrafts = Dictionary(uniqueKeysWithValues: TextRefinementProvider.allCases.map { ($0, settings.textRefinementConfig(for: $0)) })
    }

    private func asrProviderCard(for provider: ASRProvider) -> some View {
        let status = asrStatus(for: provider)

        return ProviderServiceCard(
            title: provider.displayName,
            subtitle: provider.providerSummary,
            logoName: provider.logoAssetName,
            tag: provider.category.displayName,
            isSelected: draftSelectedASRProvider == provider,
            isConfigured: status.isConfigured,
            statusText: status.text,
            onOpen: { presentedSheet = .asr(provider) }
        )
    }

    private func asrStatus(for provider: ASRProvider) -> (isConfigured: Bool, text: String) {
        switch provider.category {
        case .local:
            let managedState = managedASRModels.state(for: provider)
            return (managedState.isInstalled, managedState.statusText)
        case .cloud:
            let config = asrDrafts[provider] ?? .empty
            let isConfigured = config.isConfigured(for: provider)
            return (isConfigured, isConfigured ? "已配置" : "未配置")
        }
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

                Toggle("启用普通听写纠错", isOn: $textRefinementEnabled)
                    .toggleStyle(.switch)
            }

            HStack(alignment: .top, spacing: 18) {
                DefaultModelSelectorColumn(
                    title: "语音识别模型",
                    description: selectedASRProvider.providerSummary,
                    modelDisplayName: selectedASRProvider.modelSummary(using: asrConfig),
                    selection: $selectedASRProvider
                )

                DefaultModelSelectorColumn(
                    title: "文本处理模型",
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

private struct DictationSkillsCard: View {
    @Binding var enabledSkills: [DictationProcessingSkill]
    let isTextRefinementEnabled: Bool

    var body: some View {
        SettingsCard(
            title: "文本处理技能",
            subtitle: "仅作用于普通听写。基础纠错始终启用，下面这些技能可按需叠加。"
        ) {
            VStack(alignment: .leading, spacing: 14) {
                ForEach(DictationProcessingSkill.allCases) { skill in
                    Toggle(isOn: binding(for: skill)) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(skill.displayName)
                                .font(.system(size: 14, weight: .semibold))

                            Text(skill.summary)
                                .font(.system(size: 12))
                                .foregroundStyle(.secondary)
                        }
                    }
                    .toggleStyle(.switch)
                }

                Text(
                    isTextRefinementEnabled
                        ? "当前配置会在普通听写时生效。\"整理成有序列表\" 只会在内容存在 2 个及以上清晰事项时触发。"
                        : "当前未启用普通听写纠错。技能配置会保留，待开启后在普通听写中生效。"
                )
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
            }
        }
    }

    private func binding(for skill: DictationProcessingSkill) -> Binding<Bool> {
        Binding(
            get: { enabledSkills.contains(skill) },
            set: { isEnabled in
                var next = Set(enabledSkills)
                if isEnabled {
                    next.insert(skill)
                } else {
                    next.remove(skill)
                }
                enabledSkills = DictationProcessingSkill.allCases.filter { next.contains($0) }
            }
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

            Menu {
                ForEach(menuSections) { section in
                    if let title = section.title {
                        Section(title) {
                            sectionButtons(for: section.options)
                        }
                    } else {
                        sectionButtons(for: section.options)
                    }
                }
            } label: {
                HStack(spacing: 12) {
                    Text(selection.pickerDisplayName)
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(.primary)

                    Spacer(minLength: 12)

                    Image(systemName: "chevron.up.chevron.down")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.secondary)
                }
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
            }
            .menuStyle(.borderlessButton)
            .fixedSize(horizontal: false, vertical: true)

            if modelDisplayName != selection.pickerDisplayName {
                Text(modelDisplayName)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.primary)
            }

            Text(description)
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private func sectionButtons(for options: [SelectionValue]) -> some View {
        ForEach(options) { option in
            Button {
                selection = option
            } label: {
                if selection == option {
                    Label(option.pickerDisplayName, systemImage: "checkmark")
                } else {
                    Text(option.pickerDisplayName)
                }
            }
        }
    }

    private var menuSections: [ProviderMenuSection<SelectionValue>] {
        let options = Array(SelectionValue.allCases)
        var sections: [ProviderMenuSection<SelectionValue>] = []

        for option in options {
            if let index = sections.indices.last, sections[index].title == option.pickerSectionTitle {
                sections[index].options.append(option)
            } else {
                sections.append(
                    ProviderMenuSection(
                        title: option.pickerSectionTitle,
                        options: [option]
                    )
                )
            }
        }

        return sections
    }
}

private protocol ProviderPresentable {
    var displayName: String { get }
    var pickerDisplayName: String { get }
    var pickerSectionTitle: String? { get }
}

private struct ProviderMenuSection<Option: Identifiable>: Identifiable {
    let title: String?
    var options: [Option]

    var id: String { title ?? "__default__" }
}

extension ASRProvider: ProviderPresentable {
    var pickerDisplayName: String {
        switch self {
        case .senseVoice:
            return "SenseVoice Small"
        case .doubaoStreaming:
            return "豆包语音识别 2.0"
        case .qwenASR:
            return "Qwen3 ASR Flash"
        }
    }

    var pickerSectionTitle: String? {
        category.displayName
    }
}

extension TextRefinementProvider: ProviderPresentable {
    var pickerDisplayName: String { displayName }
    var pickerSectionTitle: String? { nil }
}

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
    let statusText: String?
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
                            .lineLimit(1)
                            .truncationMode(.tail)

                        if let statusText {
                            Text(statusText)
                                .font(.system(size: 12, weight: .medium))
                                .foregroundStyle(.secondary)
                        }
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
    let managedState: ManagedASRInstallState
    let estimatedDownload: String
    let onInstall: () -> Void
    let onUninstall: () -> Void
    let onSave: (ASRProviderConfig) -> Void

    @Environment(\.dismiss) private var dismiss

    @State private var showingInstallConfirmation = false
    @State private var draftConfig = ASRProviderConfig.empty

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            SheetHeader(
                logoName: provider.logoAssetName,
                title: provider.displayName,
                subtitle: provider.providerSummary
            )

            if provider.category == .local {
                ManagedLocalProviderFields(
                    provider: provider,
                    managedState: managedState,
                    estimatedDownload: estimatedDownload,
                    onInstall: { showingInstallConfirmation = true },
                    onUninstall: onUninstall
                )
            } else {
                CloudProviderFields(
                    provider: provider,
                    config: $draftConfig,
                    modelPlaceholder: provider.defaultModelPlaceholder
                )
            }

            SheetFooter(
                statusText: provider.category == .local ? "本地模型由应用托管下载和卸载。" : provider.cloudStatusText,
                onCancel: { dismiss() },
                onSave: {
                    onSave(draftConfig)
                    dismiss()
                }
            )
        }
        .padding(24)
        .frame(width: 520)
        .onAppear {
            draftConfig = config
            if provider == .qwenASR {
                if draftConfig.baseURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    draftConfig.baseURL = "wss://dashscope.aliyuncs.com/api-ws/v1/realtime"
                }
                if draftConfig.model.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    draftConfig.model = "qwen3-asr-flash-realtime"
                }
            }
        }
        .alert("下载 \(provider.displayName)", isPresented: $showingInstallConfirmation) {
            Button("取消", role: .cancel) {}
            Button("确认下载") {
                onInstall()
            }
        } message: {
            Text("会在首次安装时下载 SenseVoice Small 的 MLX 模型文件。安装完成后只走本地常驻识别。")
        }
    }
}

private struct TextRefinementProviderConfigSheet: View {
    let provider: TextRefinementProvider
    let config: TextRefinementProviderConfig
    let isEnabled: Bool
    let llmService: LLMRefinementService
    let onSave: (TextRefinementProviderConfig) -> Void

    @Environment(\.dismiss) private var dismiss

    @State private var draftConfig = TextRefinementProviderConfig.empty
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
                statusText: isEnabled ? "当前已启用普通听写纠错，保存后会影响后续默认 provider。" : "当前未启用普通听写纠错，保存配置后不会立即参与链路。",
                onCancel: { dismiss() },
                onSave: {
                    onSave(draftConfig)
                    dismiss()
                }
            )
        }
        .padding(24)
        .frame(width: 560)
        .onAppear {
            draftConfig = config
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
                statusMessage = "连接成功，可以用于文本处理。"
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
        BrandIconImage(resourceName: name)
            .frame(width: size - 12, height: size - 12)
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

private struct ManagedLocalProviderFields: View {
    let provider: ASRProvider
    let managedState: ManagedASRInstallState
    let estimatedDownload: String
    let onInstall: () -> Void
    let onUninstall: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            SettingsFormField(title: "安装状态") {
                Text(managedState.statusText)
                    .font(.system(size: 14))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                    .background(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(Color(nsColor: .textBackgroundColor))
                    )
            }

            SettingsFormField(title: "下载内容") {
                Text("\(provider.displayName) 的 MLX 模型文件，\(estimatedDownload)")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            HStack(spacing: 12) {
                Button("下载模型", action: onInstall)
                    .disabled({
                        if case .installing = managedState {
                            return true
                        }
                        return managedState.isInstalled
                    }())

                Button("卸载模型", action: onUninstall)
                    .disabled(!managedState.isInstalled)

                Spacer()

                if case .installing = managedState {
                    ProgressView()
                        .controlSize(.small)
                }
            }
        }
    }
}

private struct CloudProviderFields: View {
    let provider: ASRProvider
    @Binding var config: ASRProviderConfig
    let modelPlaceholder: String

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            SettingsFormField(title: "API Base URL") {
                TextField(provider.cloudBaseURLPlaceholder, text: $config.baseURL)
                    .textFieldStyle(.roundedBorder)
            }

            SettingsFormField(title: "API Key") {
                APIKeyField(text: $config.apiKey)
            }

            SettingsFormField(title: "Model") {
                TextField(modelPlaceholder, text: $config.model)
                    .textFieldStyle(.roundedBorder)
            }

            if provider == .qwenASR {
                Text("北京区：wss://dashscope.aliyuncs.com/api-ws/v1/realtime\n国际区：wss://dashscope-intl.aliyuncs.com/api-ws/v1/realtime")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
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
                APIKeyField(text: $config.apiKey)
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

private struct APIKeyField: View {
    @Binding var text: String
    @State private var isRevealed = false
    @FocusState private var focusedField: FocusedField?

    private enum FocusedField {
        case concealed
        case revealed
    }

    var body: some View {
        HStack(spacing: 10) {
            if isRevealed {
                TextField("sk-...", text: $text)
                    .textFieldStyle(.roundedBorder)
                    .focused($focusedField, equals: .revealed)
            } else {
                SecureField("sk-...", text: $text)
                    .textFieldStyle(.roundedBorder)
                    .focused($focusedField, equals: .concealed)
            }

            Button {
                isRevealed.toggle()
            } label: {
                Image(systemName: isRevealed ? "eye.slash" : "eye")
                    .font(.system(size: 14, weight: .medium))
            }
            .buttonStyle(.borderless)
            .help(isRevealed ? "隐藏 API Key" : "显示 API Key")
        }
        .onChange(of: isRevealed) { _, newValue in
            focusedField = newValue ? .revealed : .concealed
        }
    }
}

private struct GlossarySettingsPage: View {
    @Bindable var settings: AppSettings

    @State private var draftCustomTerm: String = ""
    @State private var statusMessage: String = ""

    private let presetColumns = [
        GridItem(.adaptive(minimum: 190, maximum: 260), spacing: 12, alignment: .top)
    ]

    private let tagColumns = [
        GridItem(.adaptive(minimum: 140, maximum: 240), spacing: 10, alignment: .leading)
    ]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                SettingsPageHeader(
                    title: "词库",
                    subtitle: "选择默认术语包，并维护自定义词条。该词库会参与 LLM 文本润色。"
                )

                SettingsCard(title: "默认术语包", subtitle: "按行业和场景启用内置词库，点击即可切换") {
                    VStack(alignment: .leading, spacing: 18) {
                        ForEach(GlossaryPresetDefinition.categories) { category in
                            VStack(alignment: .leading, spacing: 12) {
                                SectionTitle(title: category.title)

                                LazyVGrid(columns: presetColumns, spacing: 12) {
                                    ForEach(category.presets) { preset in
                                        GlossaryPresetToggleCard(
                                            preset: preset,
                                            isEnabled: settings.enabledGlossaryPresetIDs.contains(preset.id),
                                            onToggle: { togglePreset(preset.id, name: preset.fullTitle) }
                                        )
                                    }
                                }
                            }
                        }
                    }
                }

                SettingsCard(title: "自定义词条", subtitle: "输入一个标准写法，回车或点击按钮即可添加") {
                    VStack(alignment: .leading, spacing: 14) {
                        HStack(spacing: 12) {
                            TextField("例如：Whisper、DeepSeek、SwiftUI", text: $draftCustomTerm)
                                .textFieldStyle(.roundedBorder)
                                .onSubmit(addCustomTerm)

                            Button("添加", action: addCustomTerm)
                                .keyboardShortcut(.defaultAction)
                                .disabled(draftCustomTerm.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        }

                        if settings.customGlossaryTerms.isEmpty {
                            Text("还没有自定义词条。可以补充产品名、缩写、人名或团队内部固定术语。")
                                .font(.system(size: 13))
                                .foregroundStyle(.secondary)
                        } else {
                            LazyVGrid(columns: tagColumns, spacing: 10) {
                                ForEach(settings.customGlossaryTerms, id: \.self) { term in
                                    EditableGlossaryTag(text: term) {
                                        settings.removeCustomGlossaryTerm(term)
                                        statusMessage = "已删除自定义词条：\(term)"
                                    }
                                }
                            }
                        }

                        HStack(spacing: 12) {
                            Button("清空自定义词条") {
                                settings.clearCustomGlossaryTerms()
                                statusMessage = "自定义词条已清空。"
                            }
                            .disabled(settings.customGlossaryTerms.isEmpty)

                            Text(statusMessage.isEmpty ? "当前共 \(settings.customGlossaryTerms.count) 条自定义词条。" : statusMessage)
                                .font(.system(size: 12))
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                SettingsCard(title: "最终生效词库", subtitle: "LLM 文本润色会参考这里的标准写法") {
                    if settings.effectiveGlossarySections.isEmpty {
                        Text("还没有启用任何术语包或自定义词条。")
                            .foregroundStyle(.secondary)
                    } else {
                        VStack(alignment: .leading, spacing: 16) {
                            HStack(spacing: 12) {
                                TagBadge(text: "共 \(settings.effectiveGlossaryItems.count) 条")
                                TagBadge(text: "默认包 \(settings.enabledGlossaryPresetIDs.count) 个")
                                if !settings.customGlossaryTerms.isEmpty {
                                    TagBadge(text: "自定义 \(settings.customGlossaryTerms.count) 条")
                                }
                            }

                            ForEach(settings.effectiveGlossarySections, id: \.title) { section in
                                VStack(alignment: .leading, spacing: 10) {
                                    HStack(spacing: 8) {
                                        Text(section.title)
                                            .font(.system(size: 14, weight: .semibold))

                                        Text("\(section.items.count) 条")
                                            .font(.system(size: 12))
                                            .foregroundStyle(.secondary)
                                    }

                                    LazyVGrid(columns: tagColumns, spacing: 10) {
                                        ForEach(Array(section.items.prefix(8)), id: \.self) { item in
                                            TagBadge(text: item)
                                        }
                                    }

                                    if section.items.count > 8 {
                                        Text("还有 \(section.items.count - 8) 条未展开")
                                            .font(.system(size: 12))
                                            .foregroundStyle(.secondary)
                                    }
                                }
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }
            .padding(28)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .scrollIndicators(.hidden)
    }

    private func togglePreset(_ presetID: GlossaryPresetID, name: String) {
        let isCurrentlyEnabled = settings.enabledGlossaryPresetIDs.contains(presetID)
        settings.toggleGlossaryPreset(presetID)
        statusMessage = isCurrentlyEnabled ? "已停用术语包：\(name)" : "已启用术语包：\(name)"
    }

    private func addCustomTerm() {
        let term = draftCustomTerm.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !term.isEmpty else { return }

        if settings.addCustomGlossaryTerm(term) {
            draftCustomTerm = ""
            statusMessage = "已添加自定义词条：\(term)"
        } else {
            statusMessage = "词条已存在或内容为空。"
        }
    }
}

private struct GeneralSettingsPage: View {
    @Bindable var settings: AppSettings

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                SettingsPageHeader(
                    title: "设置",
                    subtitle: "在这里管理输入语言和 app 的通用行为说明。模型、文本处理和词库配置分别保留在各自页面。"
                )

                SettingsCard(title: "输入语言", subtitle: "普通听写默认使用这里选择的语言") {
                    VStack(alignment: .leading, spacing: 14) {
                        Picker("输入语言", selection: $settings.selectedLanguage) {
                            ForEach(SupportedLanguage.allCases) { language in
                                Text(language.displayName).tag(language)
                            }
                        }
                        .pickerStyle(.menu)
                        .labelsHidden()

                        Text("双击 Fn 的快捷翻译仍固定使用简体中文作为输入语言。")
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                    }
                }

                SettingsCard(title: "App 外观", subtitle: "控制 Dock 与 menu bar 的展示方式") {
                    VStack(alignment: .leading, spacing: 14) {
                        Toggle("显示 Dock 图标", isOn: $settings.dockIconVisible)
                            .toggleStyle(.switch)

                        Text("关闭后会隐藏 Dock 图标，仅保留 menu bar 入口；切换会立即生效。")
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                    }
                }

                SettingsCard(title: "通用说明", subtitle: "menu bar 入口已经简化，配置统一移动到 settings") {
                    VStack(alignment: .leading, spacing: 12) {
                        GeneralSettingNoteRow(
                            title: "打开方式",
                            detail: "点击 menu bar 中的 Voily 可以随时回到当前设置窗口。"
                        )

                        GeneralSettingNoteRow(
                            title: "快捷操作",
                            detail: "按住 Fn 开始普通听写，双击 Fn 触发快捷翻译。"
                        )

                        GeneralSettingNoteRow(
                            title: "配置归位",
                            detail: "语言在本页管理，模型与文本处理在“模型”页管理，术语相关内容在“词库”页管理。"
                        )
                    }
                }
            }
            .padding(28)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .scrollIndicators(.hidden)
    }
}

private struct GeneralSettingNoteRow: View {
    let title: String
    let detail: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.system(size: 14, weight: .semibold))

            Text(detail)
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
        }
    }
}

private struct GlossaryPresetToggleCard: View {
    let preset: GlossaryPresetDefinition
    let isEnabled: Bool
    let onToggle: () -> Void

    var body: some View {
        Button(action: onToggle) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .top, spacing: 10) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(preset.title)
                            .font(.system(size: 15, weight: .semibold))

                        Text("\(preset.itemCount) 条标准写法")
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                    }

                    Spacer(minLength: 8)

                    Image(systemName: isEnabled ? "checkmark.circle.fill" : "circle")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(isEnabled ? Color.accentColor : Color.secondary.opacity(0.5))
                }

                Text(preset.terms.prefix(3).joined(separator: "、"))
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(16)
            .frame(maxWidth: .infinity, minHeight: 104, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(isEnabled ? Color.accentColor.opacity(0.08) : Color(nsColor: .windowBackgroundColor))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(isEnabled ? Color.accentColor.opacity(0.35) : Color.primary.opacity(0.08), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }
}

private struct EditableGlossaryTag: View {
    let text: String
    let onRemove: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            Text(text)
                .font(.system(size: 13, weight: .medium))
                .lineLimit(1)

            Spacer(minLength: 0)

            Button(action: onRemove) {
                Image(systemName: "xmark")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(.secondary)
                    .frame(width: 18, height: 18)
                    .background(
                        Circle()
                            .fill(Color.primary.opacity(0.08))
                    )
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color.primary.opacity(0.05))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(Color.primary.opacity(0.06), lineWidth: 1)
        )
    }
}

struct SettingsPageHeader: View {
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

struct SettingsCard<Content: View>: View {
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
enum SettingsPreviewData {
    static func configuredSettings() -> AppSettings {
        let suiteName = "Voily.SettingsPreview.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        let settings = AppSettings(defaults: defaults)
        settings.selectedLanguage = .simplifiedChinese
        settings.selectedASRProvider = .doubaoStreaming
        settings.selectedTextProvider = .deepSeek
        settings.textRefinementEnabled = true
        settings.setEnabledDictationSkills([.removeFillers, .formalize])
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
        settings.setGlossaryState(
            enabledPresetIDs: [.internetDevelopment, .medical],
            customTerms: [
                "Voily",
                "DeepSeek",
                "SenseVoice",
            ]
        )
        return settings
    }

    static func emptySettings() -> AppSettings {
        let suiteName = "Voily.SettingsPreview.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        return AppSettings(defaults: defaults)
    }

    static func populatedUsageStore() -> UsageStore {
        let store = UsageStore(databasePath: ":memory:")
        let now = Date()
        for dayOffset in stride(from: -55, through: 0, by: 1) {
            let sessionCount = dayOffset == 0 ? 3 : abs(dayOffset % 4)
            for index in 0..<sessionCount {
                let baseDate = Calendar.autoupdatingCurrent.date(byAdding: .day, value: dayOffset, to: now) ?? now
                let endDate = Calendar.autoupdatingCurrent.date(bySettingHour: 9 + (index * 2), minute: 20, second: 0, of: baseDate) ?? baseDate
                let startedAt = endDate.addingTimeInterval(TimeInterval(-(35 + (index * 20))))
                let sessionID = store.recordSession(
                    VoiceInputSessionDraft(
                        startedAt: startedAt,
                        endedAt: endDate,
                        languageCode: SupportedLanguage.simplifiedChinese.rawValue,
                        recognizedText: "识别文本 \(dayOffset)-\(index)",
                        finalText: "这是第 \(index + 1) 条预览历史记录，用来展示 dashboard 首页里的完整历史与复制能力。",
                        refinementApplied: index % 2 == 0,
                        asrProvider: index % 2 == 0 ? ASRProvider.senseVoice.rawValue : ASRProvider.doubaoStreaming.rawValue,
                        asrSource: index % 2 == 0 ? "local" : "system-speech",
                        recognitionTotalMs: 320 + (index * 180),
                        recognitionEngineMs: 280 + (index * 160),
                        recognitionFirstPartialMs: index % 2 == 0 ? 140 + (index * 40) : nil,
                        recognitionPartialCount: index % 2 == 0 ? 3 + index : 0
                    ),
                    now: now
                )
                if let sessionID {
                    store.markInjectionResult(sessionID: sessionID, succeeded: index % 3 != 0, now: now)
                }
            }
        }
        return store
    }
}

private extension ASRProvider {
    var providerSummary: String {
        switch self {
        case .senseVoice:
            return "本地常驻识别，偏向中文输入。"
        case .doubaoStreaming:
            return "流式识别优先，适合低延迟输入。"
        case .qwenASR:
            return "阿里云实时识别，支持流式返回。"
        }
    }

    var logoAssetName: String {
        switch self {
        case .senseVoice:
            return "bailian"
        case .doubaoStreaming:
            return "doubao"
        case .qwenASR:
            return "bailian"
        }
    }

    var defaultModelPlaceholder: String {
        switch self {
        case .senseVoice:
            return "SenseVoice Small"
        case .doubaoStreaming:
            return "doubao-speech-realtime"
        case .qwenASR:
            return "qwen3-asr-flash-realtime"
        }
    }

    var cloudBaseURLPlaceholder: String {
        switch self {
        case .doubaoStreaming:
            return "wss://openspeech.bytedance.com/api/v3/realtime"
        case .qwenASR:
            return "wss://dashscope.aliyuncs.com/api-ws/v1/realtime"
        case .senseVoice:
            return ""
        }
    }

    var cloudStatusText: String {
        switch self {
        case .qwenASR:
            return "云端流式 provider 会直接建立阿里云实时 ASR WebSocket 会话。"
        case .doubaoStreaming:
            return "云端 provider 仅保存连接参数，真实转写接入在后续版本完成。"
        case .senseVoice:
            return "本地模型由应用托管下载和卸载。"
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
    DashboardHomePage(usageStore: SettingsPreviewData.populatedUsageStore())
        .frame(width: 760, height: 700)
}

@available(macOS 26.0, *)
#Preview("Settings Model") {
    ModelSettingsPage(
        settings: SettingsPreviewData.configuredSettings(),
        llmService: LLMRefinementService(),
        managedASRModels: ManagedASRModelStore()
    )
    .frame(width: 1120, height: 760)
}

@available(macOS 26.0, *)
#Preview("Settings Glossary") {
    GlossarySettingsPage(settings: SettingsPreviewData.configuredSettings())
        .frame(width: 760, height: 700)
}
