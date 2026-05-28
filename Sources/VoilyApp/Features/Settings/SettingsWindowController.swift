import AppKit
import SwiftUI
import VoilyCore

enum SettingsWindowSceneID {
    static let settings = "settings-window"
}

struct SettingsWindowSceneView: View {
    let settings: AppSettings
    let usageStore: UsageStore
    let llmService: LLMRefinementService
    let asrConnectionTester: ASRConnectionTester
    let managedASRModels: ManagedASRModelStore
    let appUpdater: AppUpdater
    let permissionActions: SettingsPermissionActions
    let registerWindow: (NSWindow) -> Void
    let onInitialAppearance: () -> Void
    let onWindowHide: () -> Void

    var body: some View {
        SettingsRootView(
            settings: settings,
            usageStore: usageStore,
            llmService: llmService,
            asrConnectionTester: asrConnectionTester,
            managedASRModels: managedASRModels,
            appUpdater: appUpdater,
            permissionActions: permissionActions
        )
        .environment(\.locale, Locale(identifier: settings.appInterfaceLanguage.rawValue))
        .frame(minHeight: 760)
        .background(SettingsWindowLifecycleObserver(registerWindow: registerWindow, onHide: onWindowHide))
        .onAppear {
            debugLog("SettingsWindowSceneView.onAppear")
            onInitialAppearance()
        }
        .onDisappear {
            debugLog("SettingsWindowSceneView.onDisappear")
        }
    }
}

private struct SettingsWindowLifecycleObserver: NSViewRepresentable {
    let registerWindow: (NSWindow) -> Void
    let onHide: () -> Void

    func makeNSView(context: Context) -> SettingsWindowObserverView {
        SettingsWindowObserverView(registerWindow: registerWindow, onHide: onHide)
    }

    func updateNSView(_ nsView: SettingsWindowObserverView, context: Context) {}
}

private final class SettingsWindowObserverView: NSView {
    private let closeDelegate: SettingsWindowCloseDelegate
    private let registerWindow: (NSWindow) -> Void
    private weak var observedWindow: NSWindow?
    private var observationTokens: [NSObjectProtocol] = []

    init(registerWindow: @escaping (NSWindow) -> Void, onHide: @escaping () -> Void) {
        self.registerWindow = registerWindow
        closeDelegate = SettingsWindowCloseDelegate(onHide: onHide)
        super.init(frame: .zero)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()

        guard observedWindow !== window else { return }
        teardownObservers()
        observedWindow = window

        guard let window else {
            debugLog("SettingsWindowObserverView.viewDidMoveToWindow window=nil")
            return
        }

        let windowTitle = window.title
        debugLog("SettingsWindowObserverView.attach title=\(windowTitle) isVisible=\(window.isVisible)")
        registerWindow(window)
        closeDelegate.attach(to: window)
        let center = NotificationCenter.default
        observationTokens = [
            center.addObserver(forName: NSWindow.willCloseNotification, object: window, queue: .main) { _ in
                debugLog("SettingsWindowObserverView.windowWillClose title=\(windowTitle)")
            },
            center.addObserver(forName: NSWindow.didBecomeKeyNotification, object: window, queue: .main) { _ in
                debugLog("SettingsWindowObserverView.windowDidBecomeKey title=\(windowTitle)")
            },
            center.addObserver(forName: NSWindow.didResignKeyNotification, object: window, queue: .main) { _ in
                debugLog("SettingsWindowObserverView.windowDidResignKey title=\(windowTitle)")
            },
            center.addObserver(forName: NSWindow.didBecomeMainNotification, object: window, queue: .main) { _ in
                debugLog("SettingsWindowObserverView.windowDidBecomeMain title=\(windowTitle)")
            },
            center.addObserver(forName: NSWindow.didResignMainNotification, object: window, queue: .main) { _ in
                debugLog("SettingsWindowObserverView.windowDidResignMain title=\(windowTitle)")
            },
            center.addObserver(forName: NSWindow.didMiniaturizeNotification, object: window, queue: .main) { _ in
                debugLog("SettingsWindowObserverView.windowDidMiniaturize title=\(windowTitle)")
            },
            center.addObserver(forName: NSWindow.didDeminiaturizeNotification, object: window, queue: .main) { _ in
                debugLog("SettingsWindowObserverView.windowDidDeminiaturize title=\(windowTitle)")
            }
        ]
    }

    private func teardownObservers() {
        let center = NotificationCenter.default
        observationTokens.forEach(center.removeObserver)
        observationTokens.removeAll()
    }
}

@MainActor
private final class SettingsWindowCloseDelegate: NSObject, NSWindowDelegate {
    private let onHide: () -> Void

    init(onHide: @escaping () -> Void) {
        self.onHide = onHide
    }

    func attach(to window: NSWindow) {
        guard window.delegate !== self else { return }
        window.delegate = self
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        debugLog("SettingsWindowCloseDelegate.windowShouldClose title=\(sender.title) hiding=true")
        sender.orderOut(nil)
        onHide()
        return false
    }
}

private enum SettingsPage: String, CaseIterable, Identifiable, Hashable {
    case home
    case model
    case glossary
    case general
    case input
    case about

    var id: String { rawValue }

    static let overviewPages: [SettingsPage] = [.home]
    static let configurationPages: [SettingsPage] = [.model, .glossary, .general, .input]
    static let appPages: [SettingsPage] = [.about]

    func title(languageCode: String) -> String {
        switch self {
        case .home:
            return AppLocalization.localized("首页", languageCode: languageCode)
        case .model:
            return AppLocalization.localized("模型", languageCode: languageCode)
        case .glossary:
            return AppLocalization.localized("词库", languageCode: languageCode)
        case .general:
            return AppLocalization.localized("通用", languageCode: languageCode)
        case .input:
            return AppLocalization.localized("输入", languageCode: languageCode)
        case .about:
            return AppLocalization.localized("关于", languageCode: languageCode)
        }
    }

    func subtitle(languageCode: String) -> String {
        switch self {
        case .home:
            return AppLocalization.localized("今天的语音输入情况、趋势变化和完整历史都集中放在这里。", languageCode: languageCode)
        case .model:
            return AppLocalization.localized("按模型角色选择默认 provider。触发键单击用于普通听写，长按用于快捷翻译；触发键可在“输入”页调整。", languageCode: languageCode)
        case .glossary:
            return AppLocalization.localized("选择默认术语包，并维护自定义词条。该词库会参与 LLM 文本润色。", languageCode: languageCode)
        case .general:
            return AppLocalization.localized("管理界面语言、Dock 展示和设置窗口说明。", languageCode: languageCode)
        case .input:
            return AppLocalization.localized("管理默认输入语言、麦克风、触发键和录音期间系统输出。", languageCode: languageCode)
        case .about:
            return AppLocalization.localized("查看版本信息，并手动检查软件更新。", languageCode: languageCode)
        }
    }

    var sidebarIcon: Image {
        switch self {
        case .home:
            return Ph.house.regular
        case .model:
            return Ph.cpu.regular
        case .glossary:
            return Ph.books.regular
        case .general:
            return Ph.gear.regular
        case .input:
            return Image(systemName: "keyboard")
        case .about:
            return Image(systemName: "info.circle")
        }
    }

}

private struct SettingsRootView: View {
    @Bindable var settings: AppSettings
    let usageStore: UsageStore
    let llmService: LLMRefinementService
    let asrConnectionTester: ASRConnectionTester
    let managedASRModels: ManagedASRModelStore
    let appUpdater: AppUpdater
    let permissionActions: SettingsPermissionActions

    @State private var selection: SettingsPage? = .home

    private var currentPage: SettingsPage {
        selection ?? .home
    }

    var body: some View {
        let interfaceLanguageCode = settings.appInterfaceLanguageCode

        NavigationSplitView {
            List(selection: $selection) {
                Section {
                    SidebarHeader(settings: settings)
                        .tag(nil as SettingsPage?)
                        .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 12, trailing: 16))
                        .listRowBackground(Color.clear)
                }

                Section(AppLocalization.localized("概览", languageCode: interfaceLanguageCode)) {
                    ForEach(SettingsPage.overviewPages) { page in
                        sidebarRow(for: page, languageCode: interfaceLanguageCode)
                    }
                }

                Section(AppLocalization.localized("配置", languageCode: interfaceLanguageCode)) {
                    ForEach(SettingsPage.configurationPages) { page in
                        sidebarRow(for: page, languageCode: interfaceLanguageCode)
                    }
                }

                Section(AppLocalization.localized("应用", languageCode: interfaceLanguageCode)) {
                    ForEach(SettingsPage.appPages) { page in
                        sidebarRow(for: page, languageCode: interfaceLanguageCode)
                    }
                }
            }
            .listStyle(.sidebar)
            .navigationSplitViewColumnWidth(min: 180, ideal: 196, max: 220)
        } detail: {
            Group {
                switch currentPage {
                case .home:
                    DashboardHomePage(
                        usageStore: usageStore,
                        permissionActions: permissionActions,
                        onOpenInputSettings: {
                            selection = .input
                        }
                    )
                case .model:
                    ModelSettingsPage(
                        settings: settings,
                        llmService: llmService,
                        asrConnectionTester: asrConnectionTester,
                        managedASRModels: managedASRModels
                    )
                case .glossary:
                    GlossarySettingsPage(settings: settings)
                case .general:
                    GeneralSettingsPage(settings: settings)
                case .input:
                    InputSettingsPage(
                        settings: settings,
                        permissionActions: permissionActions
                    )
                case .about:
                    AboutSettingsPage(appUpdater: appUpdater)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .navigationTitle(currentPage.title(languageCode: interfaceLanguageCode))
            .navigationSubtitle(currentPage.subtitle(languageCode: interfaceLanguageCode))
        }
    }

    private func sidebarRow(for page: SettingsPage, languageCode: String) -> some View {
        HStack(spacing: 12) {
            page.sidebarIcon
                .renderingMode(.template)
                .scaledToFit()
                .frame(width: 18, height: 18)

            Text(page.title(languageCode: languageCode))
                .font(.system(size: 14, weight: .medium))
        }
        .id("\(page.id)-\(languageCode)")
        .tag(page)
    }
}

private enum Ph {
    struct Icon {
        let assetName: String

        var regular: Image {
            Image(assetName)
                .renderingMode(.template)
                .resizable()
        }
    }

    static let house = Icon(assetName: "SidebarPhHouseIcon")
    static let books = Icon(assetName: "SidebarPhBooksIcon")
    static let cpu = Icon(assetName: "SidebarPhCPUIcon")
    static let gear = Icon(assetName: "SidebarPhGearIcon")
}

private struct SidebarHeader: View {
    let settings: AppSettings
    @State private var isUnlockMessageVisible = false

    var body: some View {
        HStack(spacing: 12) {
            SidebarAppIcon(settings: settings, onUnlock: showUnlockMessage)
                .frame(width: 44, height: 44)

            VStack(alignment: .leading, spacing: 2) {
                Text("Voily")
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(.primary)

                if isUnlockMessageVisible {
                    Text("彩蛋已解锁")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.secondary)
                }
            }
            .allowsHitTesting(false)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func showUnlockMessage() {
        isUnlockMessageVisible = true

        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            isUnlockMessageVisible = false
        }
    }
}

private struct SidebarAppIcon: View {
    let settings: AppSettings
    let onUnlock: () -> Void
    @State private var isTapFeedbackActive = false
    @State private var shouldSkipNextTapFeedback = false
    @State private var tapFeedbackSequence = 0

    var body: some View {
        Group {
            if let image = settings.selectedAppIconVariant.previewImage {
                Image(nsImage: image)
                    .resizable()
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
        .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .opacity(isTapFeedbackActive ? 0.8 : 1)
        .simultaneousGesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in
                    guard !isTapFeedbackActive else { return }
                    shouldSkipNextTapFeedback = true
                    activateTapFeedback()
                }
                .onEnded { _ in
                    deactivateTapFeedback()
                }
        )
        .simultaneousGesture(
            TapGesture().onEnded {
                guard !shouldSkipNextTapFeedback else {
                    shouldSkipNextTapFeedback = false
                    return
                }
                pulseTapFeedback()
                shouldSkipNextTapFeedback = false
            }
        )
        .onDisappear {
            isTapFeedbackActive = false
            shouldSkipNextTapFeedback = false
        }
        .onTapGesture(count: 7) {
            guard !settings.isEasterEggUnlocked else { return }
            settings.isEasterEggUnlocked = true
            onUnlock()
        }
    }

    private func activateTapFeedback() {
        withAnimation(.easeOut(duration: 0.06)) {
            isTapFeedbackActive = true
        }
    }

    private func deactivateTapFeedback() {
        withAnimation(.spring(response: 0.18, dampingFraction: 0.72)) {
            isTapFeedbackActive = false
        }
    }

    private func pulseTapFeedback() {
        tapFeedbackSequence += 1
        let sequence = tapFeedbackSequence

        activateTapFeedback()

        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 110_000_000)
            guard sequence == tapFeedbackSequence else { return }
            deactivateTapFeedback()
        }
    }
}

private struct AppIconSelector: View {
    @Binding var selection: AppIconVariant

    var body: some View {
        HStack(spacing: 12) {
            ForEach(AppIconVariant.allCases) { variant in
                AppIconOptionCard(
                    variant: variant,
                    isSelected: selection == variant
                ) {
                    selection = variant
                }
            }
        }
    }
}

private struct AppIconOptionCard: View {
    let variant: AppIconVariant
    let isSelected: Bool
    let onSelect: () -> Void

    var body: some View {
        Button(action: onSelect) {
            VStack(alignment: .leading, spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(Color(nsColor: .textBackgroundColor))

                    if let image = variant.previewImage {
                        Image(nsImage: image)
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .padding(12)
                    } else {
                        Image(systemName: "app.fill")
                            .font(.system(size: 28, weight: .medium))
                            .foregroundStyle(.secondary)
                    }
                }
                .frame(height: 96)

                HStack(spacing: 8) {
                    Text(variant.displayName)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.primary)

                    Spacer(minLength: 8)

                    Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(isSelected ? Color.accentColor : Color.secondary.opacity(0.7))
                }

                Text(AppLocalization.localized(isSelected ? "当前使用中" : "点击切换"))
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(cardBackground)
            .overlay(cardBorder)
            .contentShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    private var cardBackground: some View {
        RoundedRectangle(cornerRadius: 18, style: .continuous)
            .fill(isSelected ? Color.accentColor.opacity(0.08) : Color(nsColor: .controlBackgroundColor))
    }

    private var cardBorder: some View {
        RoundedRectangle(cornerRadius: 18, style: .continuous)
            .stroke(
                isSelected ? Color.accentColor.opacity(0.45) : Color.primary.opacity(0.08),
                lineWidth: isSelected ? 1.5 : 1
            )
    }
}

private extension AppIconVariant {
    var previewImage: NSImage? {
        NSImage(named: imageAssetName)
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
    let asrConnectionTester: ASRConnectionTester
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
                                logoFallbackText: provider.logoFallbackText,
                                tag: AppLocalization.localized("云端"),
                                isSelected: draftSelectedTextProvider == provider,
                                isConfigured: isConfigured,
                                statusText: isConfigured ? AppLocalization.localized("已配置") : AppLocalization.localized("未配置"),
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
                    languageCode: settings.selectedLanguageCode,
                    connectionTester: asrConnectionTester,
                    managedState: managedASRModels.state(for: provider),
                    estimatedDownload: managedASRModels.estimatedDownload(for: provider),
                    onInstall: { managedASRModels.install(provider: provider) },
                    onUninstall: { managedASRModels.uninstall(provider: provider) },
                    onSave: { config in
                        asrDrafts[provider] = config
                        settings.setASRConfig(config, for: provider)
                        statusMessage = String(
                            format: AppLocalization.localized("已保存 %@ 配置。"),
                            provider.displayName
                        )
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
                        statusMessage = String(
                            format: AppLocalization.localized("已保存 %@ 配置。"),
                            provider.displayName
                        )
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
            logoFallbackText: provider.logoFallbackText,
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
            return (
                isConfigured,
                isConfigured ? AppLocalization.localized("已配置") : AppLocalization.localized("未配置")
            )
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
                    AppLocalization.localized(
                        isTextRefinementEnabled
                            ? "当前配置会在普通听写时生效。\"整理成有序列表\" 只会在内容存在 2 个及以上清晰事项时触发。"
                            : "当前未启用普通听写纠错。技能配置会保留，待开启后在普通听写中生效。"
                    )
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
            Text(LocalizedStringKey(title))
                .font(.system(size: 16, weight: .semibold))

            Menu {
                ForEach(menuSections) { section in
                    if let title = section.title {
                        Section(LocalizedStringKey(title)) {
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

            Text(LocalizedStringKey(description))
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
            return AppLocalization.localized("豆包语音识别 2.0")
        case .funASR:
            return "Fun-ASR Realtime"
        case .qwenASR:
            return "Qwen3 ASR Flash"
        case .stepfunASR:
            return "Step-ASR-1.1-Stream"
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
        Text(AppLocalization.localized(title))
            .font(.system(size: 18, weight: .semibold))
    }
}

private struct ProviderServiceCard: View {
    let title: String
    let subtitle: String
    let logoName: String
    let logoFallbackText: String?
    let tag: String
    let isSelected: Bool
    let isConfigured: Bool
    let statusText: String?
    let onOpen: () -> Void

    var body: some View {
        Button(action: onOpen) {
            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .center, spacing: 14) {
                    ProviderLogoIcon(name: logoName, fallbackText: logoFallbackText)

                    VStack(alignment: .leading, spacing: 6) {
                        HStack(spacing: 10) {
                            Text(title)
                                .font(.system(size: 17, weight: .semibold))

                            TagBadge(text: tag)

                            if isSelected {
                                TagBadge(text: AppLocalization.localized("默认"))
                            }
                        }

                        Text(LocalizedStringKey(subtitle))
                            .font(.system(size: 13))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.tail)

                        if let statusText {
                            Text(LocalizedStringKey(statusText))
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
    let languageCode: String
    let connectionTester: ASRConnectionTester
    let managedState: ManagedASRInstallState
    let estimatedDownload: String
    let onInstall: () -> Void
    let onUninstall: () -> Void
    let onSave: (ASRProviderConfig) -> Void

    @Environment(\.dismiss) private var dismiss

    @State private var showingInstallConfirmation = false
    @State private var draftConfig = ASRProviderConfig.empty
    @State private var statusMessage = ""
    @State private var isTesting = false

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            SheetHeader(
                logoName: provider.logoAssetName,
                logoFallbackText: provider.logoFallbackText,
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

                HStack(spacing: 12) {
                    Button("测试连接") {
                        testConnection()
                    }
                    .disabled(isTesting || !draftConfig.isConfigured(for: provider))

                    if isTesting {
                        ProgressView()
                            .controlSize(.small)
                    }

                    Text(statusMessage.isEmpty ? defaultTestingHint : statusMessage)
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }
            }

            SheetFooter(
                statusText: provider.category == .local ? AppLocalization.localized("本地模型由应用托管下载和卸载。") : provider.cloudStatusText,
                onCancel: { dismiss() },
                onSave: {
                    onSave(normalizedConfig(draftConfig))
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
            } else if provider == .funASR {
                if draftConfig.baseURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    draftConfig.baseURL = "wss://dashscope.aliyuncs.com/api-ws/v1/inference"
                }
                if draftConfig.model.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    draftConfig.model = "fun-asr-realtime"
                }
            } else if provider == .stepfunASR {
                if draftConfig.baseURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    draftConfig.baseURL = "wss://api.stepfun.com/v1/realtime/asr/stream"
                }
                if draftConfig.model.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    draftConfig.model = "step-asr-1.1-stream"
                }
            } else if provider == .doubaoStreaming {
                if draftConfig.baseURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    draftConfig.baseURL = "wss://openspeech.bytedance.com/api/v3/sauc/bigmodel_async"
                }
                if draftConfig.model.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    draftConfig.model = "volc.seedasr.sauc.duration"
                }
            }
        }
        .alert(installConfirmationTitle, isPresented: $showingInstallConfirmation) {
            Button("取消", role: .cancel) {}
            Button("确认下载") {
                onInstall()
            }
        } message: {
            Text("会在首次安装时下载 SenseVoice Small 的 MLX 模型文件。安装完成后只走本地常驻识别。")
        }
    }

    private var defaultTestingHint: String {
        AppLocalization.localized("会使用当前表单内容发起一次真实握手。")
    }

    private func testConnection() {
        isTesting = true
        statusMessage = AppLocalization.localized("正在测试连接...")
        draftConfig = normalizedConfig(draftConfig)

        Task {
            defer { isTesting = false }

            do {
                try await connectionTester.testConnection(
                    provider: provider,
                    config: draftConfig,
                    languageCode: languageCode
                )
                statusMessage = AppLocalization.localized("连接成功，可以用于实时识别。")
            } catch {
                statusMessage = String(
                    format: AppLocalization.localized("测试失败：%@"),
                    error.localizedDescription
                )
            }
        }
    }

    private var installConfirmationTitle: String {
        String(format: AppLocalization.localized("下载 %@"), provider.displayName)
    }

    private func normalizedConfig(_ config: ASRProviderConfig) -> ASRProviderConfig {
        guard provider == .doubaoStreaming || provider == .funASR || provider == .stepfunASR else {
            return config
        }

        var normalized = config
        if provider == .doubaoStreaming {
            normalized.baseURL = DoubaoStreamingASRService.normalizedSingleLineValue(config.baseURL)
            normalized.apiKey = DoubaoStreamingASRService.normalizedSingleLineValue(config.apiKey)
            normalized.model = DoubaoStreamingASRService.normalizedSingleLineValue(config.model)
            normalized.appID = DoubaoStreamingASRService.normalizedSingleLineValue(config.appID)
        } else if provider == .funASR {
            normalized.baseURL = FunASRRealtimeService.normalizedSingleLineValue(config.baseURL)
            normalized.apiKey = FunASRRealtimeService.normalizedSingleLineValue(config.apiKey)
            normalized.model = FunASRRealtimeService.normalizedSingleLineValue(config.model)
            normalized.appID = ""
        } else {
            normalized.baseURL = StepRealtimeASRService.normalizedSingleLineValue(config.baseURL)
            normalized.apiKey = StepRealtimeASRService.normalizedSingleLineValue(config.apiKey)
            normalized.model = StepRealtimeASRService.normalizedSingleLineValue(config.model)
            normalized.appID = ""
        }
        return normalized
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
                logoFallbackText: provider.logoFallbackText,
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
                statusText: AppLocalization.localized(
                    isEnabled
                        ? "当前已启用普通听写纠错，保存后会影响后续默认 provider。"
                        : "当前未启用普通听写纠错，保存配置后不会立即参与链路。"
                ),
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
        AppLocalization.localized("会使用当前表单内容发起一次真实请求。")
    }

    private func testConnection() {
        isTesting = true
        statusMessage = AppLocalization.localized("正在测试连接...")

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
                statusMessage = AppLocalization.localized("连接成功，可以用于文本处理。")
            } catch {
                statusMessage = String(
                    format: AppLocalization.localized("测试失败：%@"),
                    error.localizedDescription
                )
            }
        }
    }
}

private struct SheetHeader: View {
    let logoName: String
    let logoFallbackText: String?
    let title: String
    let subtitle: String

    var body: some View {
        HStack(spacing: 14) {
            ProviderLogoIcon(name: logoName, fallbackText: logoFallbackText, size: 50)

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
    let fallbackText: String?
    var size: CGFloat = 44

    var body: some View {
        BrandIconImage(resourceName: name, fallbackText: fallbackText)
            .frame(width: size - 12, height: size - 12)
            .frame(width: size, height: size)
    }
}

private struct BrandIconImage: View {
    let resourceName: String
    let fallbackText: String?

    var body: some View {
        Group {
            if let image = BrandIconLoader.image(named: resourceName) {
                Image(nsImage: image)
                    .resizable()
                    .interpolation(.high)
                    .aspectRatio(contentMode: .fit)
            } else {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color.primary.opacity(0.08))
                    .overlay {
                        Text(fallbackText ?? "AI")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(.secondary)
                    }
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
                Text(downloadDescription)
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
            SettingsFormField(title: provider.cloudBaseURLTitle) {
                TextField(provider.cloudBaseURLPlaceholder, text: $config.baseURL)
                    .textFieldStyle(.roundedBorder)
            }

            if provider == .doubaoStreaming {
                SettingsFormField(title: "App ID") {
                    TextField(AppLocalization.localized("填写火山控制台中的 App ID"), text: $config.appID)
                        .textFieldStyle(.roundedBorder)
                }
            }

            SettingsFormField(title: provider.cloudAPIKeyTitle) {
                APIKeyField(text: $config.apiKey)
            }

            SettingsFormField(title: provider.cloudModelTitle) {
                TextField(modelPlaceholder, text: $config.model)
                    .textFieldStyle(.roundedBorder)
            }

            if provider == .qwenASR {
                Text(AppLocalization.localized("北京区：wss://dashscope.aliyuncs.com/api-ws/v1/realtime\n国际区：wss://dashscope-intl.aliyuncs.com/api-ws/v1/realtime"))
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            } else if provider == .funASR {
                Text(AppLocalization.localized("推荐地址：wss://dashscope.aliyuncs.com/api-ws/v1/inference\n模型示例：fun-asr-realtime\n音频要求：16k PCM 单声道流式输入。"))
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            } else if provider == .stepfunASR {
                Text(AppLocalization.localized("推荐地址：wss://api.stepfun.com/v1/realtime/asr/stream\n模型示例：step-asr-1.1-stream\n当前只支持中文或英文。"))
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            } else if provider == .doubaoStreaming {
                Text(AppLocalization.localized("推荐地址：wss://openspeech.bytedance.com/api/v3/sauc/bigmodel_async\nResource ID 示例：volc.seedasr.sauc.duration（小时版）\nResource ID 示例：volc.seedasr.sauc.concurrent（并发版）"))
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
            return "https://api.deepseek.com"
        case .dashScope:
            return "https://dashscope.aliyuncs.com/compatible-mode/v1"
        case .volcengine:
            return "https://ark.cn-beijing.volces.com/api/v3"
        case .minimax:
            return "https://api.minimax.io/v1"
        case .kimi:
            return "https://api.moonshot.cn/v1"
        case .zhipu:
            return "https://open.bigmodel.cn/api/paas/v4"
        }
    }

    private var modelPlaceholder: String {
        switch provider {
        case .deepSeek:
            return "deepseek-v4-flash"
        case .dashScope:
            return "qwen-plus"
        case .volcengine:
            return "doubao-1.5-pro"
        case .minimax:
            return "MiniMax-M2.5"
        case .kimi:
            return "kimi-k2.5"
        case .zhipu:
            return "glm-4.7-flash"
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
            .help(AppLocalization.localized(isRevealed ? "隐藏 API Key" : "显示 API Key"))
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
                                            onToggle: { togglePreset(preset.id, name: localizedFullTitle(for: preset)) }
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
                                        statusMessage = String(
                                            format: AppLocalization.localized("已删除自定义词条：%@"),
                                            term
                                        )
                                    }
                                }
                            }
                        }

                        HStack(spacing: 12) {
                            Button("清空自定义词条") {
                                settings.clearCustomGlossaryTerms()
                                statusMessage = AppLocalization.localized("自定义词条已清空。")
                            }
                            .disabled(settings.customGlossaryTerms.isEmpty)

                            Text(statusMessage.isEmpty ? customGlossaryCountStatus : statusMessage)
                                .font(.system(size: 12))
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                SettingsCard(title: "最终生效词库", subtitle: "Fun-ASR 会优先将这里同步为热词词表；开启文本润色后，LLM 也会继续参考这些标准写法") {
                    if settings.effectiveGlossarySections.isEmpty {
                        Text("还没有启用任何术语包或自定义词条。")
                            .foregroundStyle(.secondary)
                    } else {
                        VStack(alignment: .leading, spacing: 16) {
                            HStack(spacing: 12) {
                                TagBadge(text: String(format: AppLocalization.localized("共 %@ 条"), "\(settings.effectiveGlossaryItems.count)"))
                                TagBadge(text: String(format: AppLocalization.localized("默认包 %@ 个"), "\(settings.enabledGlossaryPresetIDs.count)"))
                                if !settings.customGlossaryTerms.isEmpty {
                                    TagBadge(text: String(format: AppLocalization.localized("自定义 %@ 条"), "\(settings.customGlossaryTerms.count)"))
                                }
                            }

                            ForEach(settings.effectiveGlossarySections, id: \.title) { section in
                                VStack(alignment: .leading, spacing: 10) {
                                    HStack(spacing: 8) {
                                        Text(localizedSectionTitle(section.title))
                                            .font(.system(size: 14, weight: .semibold))

                                        Text(String(format: AppLocalization.localized("%@ 条"), "\(section.items.count)"))
                                            .font(.system(size: 12))
                                            .foregroundStyle(.secondary)
                                    }

                                    LazyVGrid(columns: tagColumns, spacing: 10) {
                                        ForEach(Array(section.items.prefix(8)), id: \.self) { item in
                                            TagBadge(text: item)
                                        }
                                    }

                                    if section.items.count > 8 {
                                        Text(String(format: AppLocalization.localized("还有 %@ 条未展开"), "\(section.items.count - 8)"))
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
        if isCurrentlyEnabled {
            statusMessage = String(format: AppLocalization.localized("已停用术语包：%@"), name)
        } else {
            statusMessage = String(format: AppLocalization.localized("已启用术语包：%@"), name)
        }
    }

    private func addCustomTerm() {
        let term = draftCustomTerm.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !term.isEmpty else { return }

        if settings.addCustomGlossaryTerm(term) {
            draftCustomTerm = ""
            statusMessage = String(
                format: AppLocalization.localized("已添加自定义词条：%@"),
                term
            )
        } else {
            statusMessage = AppLocalization.localized("词条已存在或内容为空。")
        }
    }

    private var customGlossaryCountStatus: String {
        String(
            format: AppLocalization.localized("当前共 %@ 条自定义词条。"),
            "\(settings.customGlossaryTerms.count)"
        )
    }

    private func localizedFullTitle(for preset: GlossaryPresetDefinition) -> String {
        let domainTitle = AppLocalization.localized(preset.domainTitle)
        guard let sceneTitle = preset.sceneTitle else {
            return domainTitle
        }

        return String(
            format: AppLocalization.localized("%@-%@"),
            domainTitle,
            AppLocalization.localized(sceneTitle)
        )
    }

    private func localizedSectionTitle(_ title: String) -> String {
        let parts = title.split(separator: "-", maxSplits: 1).map(String.init)
        guard parts.count == 2 else {
            return AppLocalization.localized(title)
        }

        return String(
            format: AppLocalization.localized("%@-%@"),
            AppLocalization.localized(parts[0]),
            AppLocalization.localized(parts[1])
        )
    }
}

private struct GeneralSettingsPage: View {
    @Bindable var settings: AppSettings

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                SettingsCard(title: "界面语言", subtitle: "选择 Voily 的界面显示语言") {
                    VStack(alignment: .leading, spacing: 14) {
                        Picker("界面语言", selection: $settings.appInterfaceLanguage) {
                            ForEach(AppInterfaceLanguage.allCases) { language in
                                Text(language.displayName).tag(language)
                            }
                        }
                        .pickerStyle(.menu)
                        .labelsHidden()

                        Text("界面会立即按所选语言更新。")
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                    }
                }

                AppAppearanceSettingsCard(settings: settings)

                SettingsCard(title: "通用说明", subtitle: "设置窗口的基础使用说明") {
                    VStack(alignment: .leading, spacing: 12) {
                        GeneralSettingNoteRow(
                            title: "打开方式",
                            detail: "点击 menu bar 中的 Voily 可以随时回到当前设置窗口。"
                        )

                        GeneralSettingNoteRow(
                            title: "快捷操作",
                            detail: settings.triggerKey.summary
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

private struct AppAppearanceSettingsCard: View {
    @Bindable var settings: AppSettings

    var body: some View {
        SettingsCard(title: "App 外观", subtitle: "控制 Dock 与 menu bar 的展示方式") {
            VStack(alignment: .leading, spacing: 14) {
                Toggle("显示 Dock 图标", isOn: $settings.dockIconVisible)
                    .toggleStyle(.switch)

                if settings.isEasterEggUnlocked {
                    SettingsFormField(title: "App 图标") {
                        AppIconSelector(selection: $settings.selectedAppIconVariant)
                    }

                    Text("图标切换会立即作用到当前运行中的 App。")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }

                Text("关闭后会隐藏 Dock 图标，仅保留 menu bar 入口；切换会立即生效。")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }
        }
    }
}

private struct InputSettingsPage: View {
    @Bindable var settings: AppSettings
    let permissionActions: SettingsPermissionActions
    let loadInputDevices: () -> [AudioInputDevice]

    @State private var availableInputDevices: [AudioInputDevice] = []
    @State private var deviceMonitor = AudioInputDeviceMonitor()

    init(
        settings: AppSettings,
        permissionActions: SettingsPermissionActions = .preview(),
        loadInputDevices: @escaping () -> [AudioInputDevice] = { AudioInputDeviceCatalog().availableInputDevices() }
    ) {
        self.settings = settings
        self.permissionActions = permissionActions
        self.loadInputDevices = loadInputDevices
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                SettingsPermissionCard(actions: permissionActions)

                SettingsCard(title: "输入语言", subtitle: "普通听写默认使用这里选择的语言") {
                    VStack(alignment: .leading, spacing: 14) {
                        Picker("输入语言", selection: $settings.selectedLanguage) {
                            ForEach(SupportedLanguage.allCases) { language in
                                Text(language.displayName).tag(language)
                            }
                        }
                        .pickerStyle(.menu)
                        .labelsHidden()

                        Text("快捷翻译仍固定使用简体中文作为输入语言。")
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                    }
                }

                MicrophoneInputSettingsCard(
                    preferredMicrophoneUID: $settings.preferredMicrophoneUID,
                    availableDevices: availableInputDevices,
                    onRefresh: reloadInputDevices
                )

                SettingsCard(title: "触发键", subtitle: "选择用于语音输入的触发键，交互固定为单击听写、长按翻译") {
                    VStack(alignment: .leading, spacing: 14) {
                        SettingsFormField(title: "用于触发语音输入的按键") {
                            Picker("触发键", selection: $settings.triggerKey) {
                                ForEach(TriggerKey.allCases) { triggerKey in
                                    Text(triggerKey.displayName).tag(triggerKey)
                                }
                            }
                            .pickerStyle(.menu)
                            .labelsHidden()
                        }

                        Text(settings.triggerKey.summary)
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)

                        Text("快捷翻译开始后可松手，结束方式保持现在的确认/取消交互。选择右 Command 时，仅单独点击或长按会生效，不会覆盖系统组合键。")
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                    }
                }

                SettingsCard(title: "系统输出", subtitle: "控制语音任务期间对系统输出声音的处理") {
                    VStack(alignment: .leading, spacing: 14) {
                        Toggle("语音输入时自动静音系统输出，结束后恢复", isOn: $settings.interruptSystemMediaPlayback)
                            .toggleStyle(.switch)

                        Text("统一作用于普通听写和快捷翻译。Voily 会在任务开始时临时静音当前默认输出设备，并在会话结束时恢复；如果你中途切换了输出设备，则不会改动新的设备。")
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .padding(28)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .scrollIndicators(.hidden)
        .onAppear {
            reloadInputDevices()
            deviceMonitor.start(onChange: reloadInputDevices)
        }
        .onDisappear {
            deviceMonitor.stop()
        }
    }

    private func reloadInputDevices() {
        availableInputDevices = loadInputDevices()
    }
}

private struct AboutSettingsPage: View {
    let appUpdater: AppUpdater

    var body: some View {
        let versionInfo = appUpdater.versionInfo

        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                SettingsCard(title: versionInfo.displayName, subtitle: "开源 macOS 听写应用") {
                    HStack(alignment: .center, spacing: 18) {
                        AppAboutIcon()
                            .frame(width: 72, height: 72)

                        VStack(alignment: .leading, spacing: 8) {
                            Text(versionInfo.versionSummary)
                                .font(.system(size: 24, weight: .semibold))

                            Text("按一下触发键开始录音，再按一下停止转写，自动粘贴到光标位置。")
                                .font(.system(size: 13))
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }

                        Spacer(minLength: 16)
                    }
                }

                SettingsCard(title: "版本信息", subtitle: "用于诊断、反馈和发布验证") {
                    VStack(alignment: .leading, spacing: 12) {
                        SettingsInfoRow(label: "版本", value: versionInfo.shortVersion)
                        SettingsInfoRow(label: "构建", value: versionInfo.buildNumber.isEmpty ? "-" : versionInfo.buildNumber)
                        SettingsInfoRow(
                            label: "更新检查",
                            value: appUpdater.isUpdateCheckConfigured ? AppLocalization.localized("已配置") : AppLocalization.localized("未配置")
                        )
                    }
                }

                SettingsCard(title: "软件更新", subtitle: "手动检查 Voily 是否有可用新版本") {
                    VStack(alignment: .leading, spacing: 14) {
                        Text(updateStatusDescription)
                            .font(.system(size: 13))
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)

                        Button("检查更新…") {
                            appUpdater.checkForUpdates()
                        }
                    }
                }
            }
            .padding(28)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .scrollIndicators(.hidden)
    }

    private var updateStatusDescription: String {
        if appUpdater.isUpdateCheckConfigured {
            return AppLocalization.localized("会通过 Sparkle 检查 GitHub Release appcast。")
        }

        return AppLocalization.localized("当前构建没有可用的 Sparkle 配置，点击检查更新会显示配置提示。")
    }
}

private struct AppAboutIcon: View {
    var body: some View {
        Image(nsImage: NSWorkspace.shared.icon(forFile: Bundle.main.bundlePath))
            .resizable()
            .aspectRatio(contentMode: .fit)
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
    }
}

private struct GeneralSettingNoteRow: View {
    let title: String
    let detail: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(LocalizedStringKey(title))
                .font(.system(size: 14, weight: .semibold))

            Text(LocalizedStringKey(detail))
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
        }
    }
}

private struct MicrophoneInputSettingsCard: View {
    @Binding var preferredMicrophoneUID: String?

    let availableDevices: [AudioInputDevice]
    let onRefresh: () -> Void

    private let catalog = AudioInputDeviceCatalog()

    private var isPreferredDeviceMissing: Bool {
        guard let preferredMicrophoneUID else { return false }
        return !availableDevices.contains(where: { $0.uid == preferredMicrophoneUID })
    }

    private var automaticallySelectedDevice: AudioInputDevice? {
        catalog.automaticallySelectedInputDevice(from: availableDevices)
    }

    private var selectedDeviceDescription: String {
        if let preferredMicrophoneUID,
           let device = availableDevices.first(where: { $0.uid == preferredMicrophoneUID }) {
            return String(
                format: AppLocalization.localized("当前使用 %@，普通听写和快捷翻译都会立即生效。"),
                device.name
            )
        }

        if let automaticallySelectedDevice {
            return String(
                format: AppLocalization.localized("当前自动选择 %@。优先级为 USB > 内置麦克风 > 蓝牙，普通听写和快捷翻译都会立即生效。"),
                automaticallySelectedDevice.name
            )
        }

        return AppLocalization.localized("当前自动选择可用输入设备。优先级为 USB > 内置麦克风 > 蓝牙，普通听写和快捷翻译都会立即生效。")
    }

    private var automaticSelectionLabel: String {
        if let automaticallySelectedDevice {
            return String(
                format: AppLocalization.localized("自动选择（当前会用 %@）"),
                automaticallySelectedDevice.name
            )
        }
        return AppLocalization.localized("自动选择")
    }

    var body: some View {
        SettingsCard(title: "麦克风输入", subtitle: "为所有录音场景选择统一的输入设备") {
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .center, spacing: 12) {
                    Picker("麦克风输入", selection: $preferredMicrophoneUID) {
                        Text(automaticSelectionLabel)
                            .tag(nil as String?)

                        ForEach(availableDevices) { device in
                            Text(deviceLabel(for: device))
                                .tag(Optional(device.uid))
                        }
                    }
                    .pickerStyle(.menu)
                    .labelsHidden()

                    Button("重新扫描", action: onRefresh)
                        .controlSize(.small)
                }

                Text(selectedDeviceDescription)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)

                if isPreferredDeviceMissing {
                    Text("当前设备不可用，录音时将回退到自动选择规则。重新接回设备后会继续命中这个选择。")
                        .font(.system(size: 12))
                        .foregroundStyle(.orange)
                }
            }
        }
    }

    private func deviceLabel(for device: AudioInputDevice) -> String {
        if automaticallySelectedDevice?.uid == device.uid {
            return String(format: AppLocalization.localized("%@（自动优先）"), device.name)
        }
        if device.isDefault {
            return String(format: AppLocalization.localized("%@（系统默认）"), device.name)
        }
        return device.name
    }
}

private extension ManagedLocalProviderFields {
    var downloadDescription: String {
        String(
            format: AppLocalization.localized("%@ 的 MLX 模型文件，%@"),
            provider.displayName,
            estimatedDownload
        )
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
                        Text(AppLocalization.localized(preset.title))
                            .font(.system(size: 15, weight: .semibold))

                        Text(String(format: AppLocalization.localized("%@ 条标准写法"), "\(preset.itemCount)"))
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

struct SettingsCard<Content: View>: View {
    let title: String
    let subtitle: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 4) {
                Text(LocalizedStringKey(title))
                    .font(.system(size: 17, weight: .semibold))

                Text(LocalizedStringKey(subtitle))
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
            Text(LocalizedStringKey(title))
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
            Text(LocalizedStringKey(label))
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
                baseURL: "wss://openspeech.bytedance.com/api/v3/sauc/bigmodel_async",
                apiKey: "volc-asr-key",
                model: "volc.seedasr.sauc.duration",
                appID: "doubao-preview-app"
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
                model: "",
                appID: ""
            ),
            for: .senseVoice
        )
        settings.setTextRefinementConfig(
            TextRefinementProviderConfig(
                baseURL: "https://api.deepseek.com",
                apiKey: "sk-preview-123456",
                model: "deepseek-v4-flash"
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

    static func configuredSettings(preferredMicrophoneUID: String?) -> AppSettings {
        let settings = configuredSettings()
        settings.preferredMicrophoneUID = preferredMicrophoneUID
        return settings
    }

    static func emptySettings() -> AppSettings {
        let suiteName = "Voily.SettingsPreview.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        return AppSettings(defaults: defaults)
    }

    static let sampleAudioInputDevices: [AudioInputDevice] = [
        AudioInputDevice(
            uid: "usb-audio-interface",
            name: "Shure MV7",
            isDefault: false,
            transport: .usb
        ),
        AudioInputDevice(
            uid: "BuiltInMicrophoneDevice",
            name: "MacBook Pro Microphone",
            isDefault: true,
            transport: .builtIn
        ),
        AudioInputDevice(
            uid: "airpods-mic",
            name: "AirPods Pro Microphone",
            isDefault: false,
            transport: .bluetooth
        ),
    ]

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
                        recognizedText: "Recognized text \(dayOffset)-\(index)",
                        finalText: "Preview history item \(index + 1), showing the dashboard history list and copy behavior.",
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
            return AppLocalization.localized("本地常驻识别，偏向中文输入。")
        case .doubaoStreaming:
            return AppLocalization.localized("豆包大模型流式识别，适合低延迟输入。")
        case .funASR:
            return AppLocalization.localized("通义实验室流式识别，偏中文听写和方言口音场景。")
        case .qwenASR:
            return AppLocalization.localized("阿里云实时识别，支持流式返回。")
        case .stepfunASR:
            return AppLocalization.localized("跃阶星辰流式识别，当前按官方文档只接中文/英文。")
        }
    }

    var logoAssetName: String {
        switch self {
        case .senseVoice:
            return "bailian"
        case .doubaoStreaming:
            return "doubao"
        case .funASR:
            return "bailian"
        case .qwenASR:
            return "bailian"
        case .stepfunASR:
            return "stepfun"
        }
    }

    var logoFallbackText: String? {
        switch self {
        case .senseVoice:
            return "SV"
        case .doubaoStreaming:
            return "DB"
        case .funASR:
            return "FA"
        case .qwenASR:
            return "QW"
        case .stepfunASR:
            return "SF"
        }
    }

    var defaultModelPlaceholder: String {
        switch self {
        case .senseVoice:
            return "SenseVoice Small"
        case .doubaoStreaming:
            return "volc.seedasr.sauc.duration"
        case .funASR:
            return "fun-asr-realtime"
        case .qwenASR:
            return "qwen3-asr-flash-realtime"
        case .stepfunASR:
            return "step-asr-1.1-stream"
        }
    }

    var cloudBaseURLPlaceholder: String {
        switch self {
        case .doubaoStreaming:
            return "wss://openspeech.bytedance.com/api/v3/sauc/bigmodel_async"
        case .funASR:
            return "wss://dashscope.aliyuncs.com/api-ws/v1/inference"
        case .qwenASR:
            return "wss://dashscope.aliyuncs.com/api-ws/v1/realtime"
        case .stepfunASR:
            return "wss://api.stepfun.com/v1/realtime/asr/stream"
        case .senseVoice:
            return ""
        }
    }

    var cloudBaseURLTitle: String {
        "WebSocket URL"
    }

    var cloudAPIKeyTitle: String {
        switch self {
        case .doubaoStreaming:
            return "Token"
        case .funASR, .qwenASR, .stepfunASR:
            return "API Key"
        case .senseVoice:
            return ""
        }
    }

    var cloudModelTitle: String {
        switch self {
        case .doubaoStreaming:
            return "Resource ID"
        case .funASR, .qwenASR, .stepfunASR:
            return "Model"
        case .senseVoice:
            return ""
        }
    }

    var cloudStatusText: String {
        switch self {
        case .funASR:
            return AppLocalization.localized("云端流式 provider 会直接建立 Fun-ASR WebSocket 会话，按需同步词库热词，并发送 16k PCM 音频。")
        case .qwenASR:
            return AppLocalization.localized("云端流式 provider 会直接建立阿里云实时 ASR WebSocket 会话。")
        case .doubaoStreaming:
            return AppLocalization.localized("云端流式 provider 会直接建立豆包大模型流式识别 WebSocket 会话。")
        case .stepfunASR:
            return AppLocalization.localized("云端流式 provider 会直接建立跃阶星辰实时 ASR WebSocket 会话。")
        case .senseVoice:
            return AppLocalization.localized("本地模型由应用托管下载和卸载。")
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
            return AppLocalization.localized("速度优先，适合文本纠错和保守润色。")
        case .dashScope:
            return AppLocalization.localized("阿里云百炼通道，便于后续扩展 Qwen 系列。")
        case .volcengine:
            return AppLocalization.localized("火山引擎通道，适合后续接入豆包大模型。")
        case .minimax:
            return AppLocalization.localized("MiniMax OpenAI 兼容通道，适合低成本文本处理。")
        case .kimi:
            return AppLocalization.localized("Kimi OpenAI 兼容通道，适合中文文本纠错。")
        case .zhipu:
            return AppLocalization.localized("智谱 OpenAI 兼容通道，便于接入 GLM 系列。")
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
        case .minimax:
            return "minimax"
        case .kimi:
            return "kimi"
        case .zhipu:
            return "zhipu"
        }
    }

    var logoFallbackText: String? {
        switch self {
        case .deepSeek:
            return "DS"
        case .dashScope:
            return "BL"
        case .volcengine:
            return "VC"
        case .minimax:
            return "MM"
        case .kimi:
            return "Ki"
        case .zhipu:
            return "ZP"
        }
    }

    func modelSummary(using config: TextRefinementProviderConfig) -> String {
        let model = config.model.trimmingCharacters(in: .whitespacesAndNewlines)
        return model.isEmpty ? displayName : model
    }
}

#Preview("Settings Home") {
    DashboardHomePage(usageStore: SettingsPreviewData.populatedUsageStore())
        .frame(width: 760, height: 700)
}

#Preview("Settings Model") {
    ModelSettingsPage(
        settings: SettingsPreviewData.configuredSettings(),
        llmService: LLMRefinementService(),
        asrConnectionTester: ASRConnectionTester.live(),
        managedASRModels: ManagedASRModelStore()
    )
    .frame(width: 1120, height: 760)
}

#Preview("Settings Glossary") {
    GlossarySettingsPage(settings: SettingsPreviewData.configuredSettings())
        .frame(width: 760, height: 700)
}

#Preview("Settings General") {
    GeneralSettingsPage(settings: SettingsPreviewData.configuredSettings())
        .frame(width: 760, height: 700)
}

#Preview("Settings Input") {
    ScrollView {
        VStack(alignment: .leading, spacing: 20) {
            MicrophoneInputSettingsCard(
                preferredMicrophoneUID: .constant(nil),
                availableDevices: SettingsPreviewData.sampleAudioInputDevices,
                onRefresh: {}
            )

            MicrophoneInputSettingsCard(
                preferredMicrophoneUID: .constant("BuiltInMicrophoneDevice"),
                availableDevices: SettingsPreviewData.sampleAudioInputDevices,
                onRefresh: {}
            )

            MicrophoneInputSettingsCard(
                preferredMicrophoneUID: .constant("usb-audio-interface"),
                availableDevices: SettingsPreviewData.sampleAudioInputDevices,
                onRefresh: {}
            )

            MicrophoneInputSettingsCard(
                preferredMicrophoneUID: .constant("missing-microphone"),
                availableDevices: SettingsPreviewData.sampleAudioInputDevices,
                onRefresh: {}
            )
        }
        .padding(28)
    }
    .frame(width: 760, height: 760)
}

#Preview("Settings About") {
    AboutSettingsPage(
        appUpdater: AppUpdater(
            configuration: SparkleUpdaterConfiguration(
                feedURLString: "https://github.com/BubblePtr/Voily/releases/latest/download/appcast.xml",
                publicEDKey: ""
            )
        )
    )
    .frame(width: 760, height: 700)
}
