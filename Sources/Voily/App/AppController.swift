import AppKit
import AVFoundation
import Charts
import Foundation
import Observation
import QuartzCore
import SwiftUI

func isRunningInXcodePreview() -> Bool {
    ProcessInfo.processInfo.environment["XCODE_RUNNING_FOR_PREVIEWS"] == "1"
}

func isRunningUnderXCTest() -> Bool {
    let environment = ProcessInfo.processInfo.environment
    if environment["XCTestConfigurationFilePath"] != nil {
        return true
    }
    return NSClassFromString("XCTestCase") != nil
}

private struct RecognitionOutcome {
    let text: String
    let provider: ASRProvider
    let source: String
    let totalDurationMs: Int
    let engineDurationMs: Int?
    let firstPartialMs: Int?
    let partialCount: Int
}

private enum CaptureSessionMode: Equatable {
    case dictation
    case quickTranslationZhToEn

    var inputLanguageCode: String {
        switch self {
        case .dictation:
            return ""
        case .quickTranslationZhToEn:
            return SupportedLanguage.simplifiedChinese.rawValue
        }
    }

    var debugName: String {
        switch self {
        case .dictation:
            return "dictation"
        case .quickTranslationZhToEn:
            return "quick-translation-zh-en"
        }
    }
}

private final class PendingRealtimeAppendCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var count = 0

    func increment() {
        lock.lock()
        count += 1
        lock.unlock()
    }

    func decrement() {
        lock.lock()
        count = max(0, count - 1)
        lock.unlock()
    }

    func reset() {
        lock.lock()
        count = 0
        lock.unlock()
    }

    var value: Int {
        lock.lock()
        defer { lock.unlock() }
        return count
    }
}

@MainActor
final class WindowActions {
    private weak var settingsWindow: NSWindow?

    var isSettingsWindowVisible: Bool {
        settingsWindow?.isVisible == true
    }

    func registerSettingsWindow(_ window: NSWindow) {
        settingsWindow = window
        debugLog("WindowActions.registerSettingsWindow title=\(window.title) isVisible=\(window.isVisible)")
    }

    @discardableResult
    func showSettingsWindow() -> Bool {
        if let window = settingsWindow {
            debugLog("WindowActions.showSettingsWindow existingWindow isVisible=\(window.isVisible)")
            if !window.isVisible {
                window.orderFrontRegardless()
            }
            window.makeKeyAndOrderFront(nil)
            return true
        }

        debugLog("WindowActions.showSettingsWindow noWindow")
        return false
    }
}

@MainActor
final class AppController: NSObject {
    private let windowActions: WindowActions
    private let settings = AppSettings()
    private let usageStore = UsageStore()
    private let permissionCoordinator = PermissionCoordinator()
    private let triggerKeyMonitor = TriggerKeyMonitor()
    private let audioCaptureService = AudioCaptureService()
    private let senseVoiceResidentService = SenseVoiceResidentService()
    private let funASRRealtimeService = FunASRRealtimeService()
    private let funASRVocabularyService = FunASRVocabularyService()
    private let qwenRealtimeASRService = QwenRealtimeASRService()
    private let stepRealtimeASRService = StepRealtimeASRService()
    private let doubaoStreamingASRService = DoubaoStreamingASRService()
    private let managedASRModels = ManagedASRModelStore()
    private let overlayController = OverlayPanelController()
    private let textInjectionService = TextInjectionService()
    private let llmRefinementService = LLMRefinementService()
    private let audioOutputMuteService = SystemAudioOutputMuteService()
    private let injectedASRCaptureSessionFactory: (any ASRCaptureSessionBuilding)?

    private var statusItem: NSStatusItem?
    private var statusMenu: NSMenu?
    private var dashboardMenuItem: NSMenuItem?
    private var dashboardHostingView: NSHostingView<MenuDashboardMenuItemView>?
    private var currentPhase: OverlayPhase = .idle
    private var currentOverlayControls: OverlayControls = .none
    private var currentText = ""
    private var smoothedRMS: Float = 0
    private var currentSessionStartedAt: Date?
    private var currentSessionMode: CaptureSessionMode?
    private var activeASRSession: ActiveASRCaptureSession?
    private var currentFirstPartialMs: Int?
    private var currentPartialCount = 0
    private var currentCaptureAppendError: Error?
    private var currentAudioOutputMuteToken: AudioOutputMuteInterruptionToken?
    private var realtimePartialDisplayThrottle = PartialTranscriptDisplayThrottle()
    private var realtimePartialFlushTask: Task<Void, Never>?
    private var hasStopped = false
    private var hasStartedStartupPermissionGuidance = false
    private var hasCompletedInitialSettingsWindowAppearance = false
    private var openSettingsWindowAction: (@MainActor () -> Void)?
    private let realtimeAppendCounter = PendingRealtimeAppendCounter()

    private lazy var defaultASRCaptureSessionFactory: any ASRCaptureSessionBuilding = LiveASRCaptureSessionFactory(
        senseVoiceResidentService: senseVoiceResidentService,
        funASRRealtimeService: funASRRealtimeService,
        funASRVocabularyService: funASRVocabularyService,
        qwenRealtimeASRService: qwenRealtimeASRService,
        stepRealtimeASRService: stepRealtimeASRService,
        doubaoStreamingASRService: doubaoStreamingASRService
    )

    private var asrCaptureSessionFactory: any ASRCaptureSessionBuilding {
        injectedASRCaptureSessionFactory ?? defaultASRCaptureSessionFactory
    }

    init(
        windowActions: WindowActions,
        asrCaptureSessionFactory: (any ASRCaptureSessionBuilding)? = nil
    ) {
        self.windowActions = windowActions
        self.injectedASRCaptureSessionFactory = asrCaptureSessionFactory
    }

    func start() {
        debugLog("AppController.start()")
        configureMainMenu()
        configureStatusItem()
        observeDockIconPreference()
        observeAppIconPreference()
        observeTriggerKeyPreference()
        configureOverlayActions()
    }

    func registerOpenSettingsWindowAction(_ action: @escaping @MainActor () -> Void) {
        openSettingsWindowAction = action
    }

    func stop() async {
        guard !hasStopped else { return }
        hasStopped = true

        debugLog("AppController.stop()")
        triggerKeyMonitor.stop()
        audioCaptureService.stop()
        await activeASRSession?.session.cancel()
        resetRealtimePartialDisplayState()
        await senseVoiceResidentService.stop()
        await restoreAudioOutputIfNeeded()
        activeASRSession = nil
        currentCaptureAppendError = nil
        currentSessionMode = nil
        currentOverlayControls = .none
        realtimeAppendCounter.reset()
    }

    func showSettingsWindow() {
        debugLog(
            "showSettingsWindow() begin activationPolicy=\(NSApp.activationPolicy().rawValue) isActive=\(NSApp.isActive)"
        )
        if NSApp.activationPolicy() != .regular {
            debugLog("showSettingsWindow() promoting activation policy to regular")
            NSApp.setActivationPolicy(.regular)
        }
        NSApp.activate(ignoringOtherApps: true)
        debugLog("showSettingsWindow() activated isActive=\(NSApp.isActive)")
        if windowActions.showSettingsWindow() {
            debugLog("showSettingsWindow() dispatched action")
            return
        }
        if let openSettingsWindowAction {
            debugLog("showSettingsWindow() opening settings scene")
            openSettingsWindowAction()
            return
        }
        debugLog("showSettingsWindow() noRegisteredWindowYet")
    }

    func handleReopen(hasVisibleWindows: Bool) -> Bool {
        debugLog("handleReopen(hasVisibleWindows: \(hasVisibleWindows))")
        if !hasVisibleWindows {
            showSettingsWindow()
        }
        return true
    }

    private func configureAccessibilityFeatures() {
        debugLog("configureAccessibilityFeatures trusted=\(permissionCoordinator.isAccessibilityTrusted)")
        guard permissionCoordinator.isAccessibilityTrusted else {
            debugLog("Accessibility not trusted yet, prompting and waiting")
            permissionCoordinator.promptForAccessibilityIfNeeded()
            permissionCoordinator.waitForAccessibilityGrant { [weak self] in
                debugLog("Accessibility granted, starting trigger key monitoring")
                self?.configureTriggerKeyMonitoring()
            }
            return
        }

        debugLog("Accessibility already trusted, starting trigger key monitoring")
        configureTriggerKeyMonitoringIfNeeded()
    }

    private func configureStartupPermissionGuidance() async {
        debugLog("configureStartupPermissionGuidance() begin")
        await requestMicrophonePermissionAtLaunchIfNeeded()
        configureAccessibilityFeatures()
    }

    private func requestMicrophonePermissionAtLaunchIfNeeded() async {
        let status = permissionCoordinator.microphoneAuthorizationStatus
        debugLog("requestMicrophonePermissionAtLaunchIfNeeded status=\(status.rawValue)")

        switch status {
        case .authorized:
            return
        case .notDetermined:
            NSApp.activate(ignoringOtherApps: true)
            let granted = await permissionCoordinator.requestMicrophoneIfNeeded()
            debugLog("Startup microphone permission granted=\(granted)")
            if !granted {
                await showPermissionGuidance("Enable Microphone access in System Settings to start recording.")
            }
        case .denied, .restricted:
            await showPermissionGuidance("Enable Microphone access in System Settings to start recording.")
        @unknown default:
            await showPermissionGuidance("Enable Microphone access in System Settings to start recording.")
        }
    }

    private func observeDockIconPreference() {
        withObservationTracking {
            _ = settings.dockIconVisible
        } onChange: { [weak self] in
            Task { @MainActor in
                self?.applyDockIconVisibility()
                self?.observeDockIconPreference()
            }
        }

        applyDockIconVisibility()
    }

    private func observeAppIconPreference() {
        withObservationTracking {
            _ = settings.selectedAppIconVariant
        } onChange: { [weak self] in
            Task { @MainActor in
                self?.applySelectedAppIcon()
                self?.observeAppIconPreference()
            }
        }

        applySelectedAppIcon()
    }

    private func observeTriggerKeyPreference() {
        withObservationTracking {
            _ = settings.triggerKey
        } onChange: { [weak self] in
            Task { @MainActor in
                self?.applyTriggerKey()
                self?.observeTriggerKeyPreference()
            }
        }

        applyTriggerKey()
    }

    func registerSettingsWindow(_ window: NSWindow) {
        windowActions.registerSettingsWindow(window)
    }

    func makeSettingsWindowSceneView() -> some View {
        SettingsWindowSceneView(
            settings: settings,
            usageStore: usageStore,
            llmService: llmRefinementService,
            asrConnectionTester: ASRConnectionTester.live(
                qwenService: qwenRealtimeASRService,
                stepService: stepRealtimeASRService,
                doubaoService: doubaoStreamingASRService,
                funASRService: funASRRealtimeService
            ),
            managedASRModels: managedASRModels,
            registerWindow: registerSettingsWindow(_:),
            onInitialAppearance: handleSettingsWindowInitialAppearance,
            onWindowHide: handleSettingsWindowDidHide
        )
    }

    private func handleSettingsWindowInitialAppearance() {
        guard !isRunningUnderXCTest() else {
            debugLog("handleSettingsWindowInitialAppearance skipping startup permission guidance under XCTest")
            return
        }
        guard !hasStartedStartupPermissionGuidance else { return }
        hasCompletedInitialSettingsWindowAppearance = true
        hasStartedStartupPermissionGuidance = true
        debugLog("handleSettingsWindowInitialAppearance()")
        Task { @MainActor in
            await configureStartupPermissionGuidance()
        }
    }

    private func applyDockIconVisibility() {
        let shouldKeepRegular =
            !hasCompletedInitialSettingsWindowAppearance ||
            windowActions.isSettingsWindowVisible
        let policy: NSApplication.ActivationPolicy =
            (settings.dockIconVisible || shouldKeepRegular) ? .regular : .accessory
        guard NSApp.activationPolicy() != policy else { return }
        NSApp.setActivationPolicy(policy)
    }

    func handleSettingsWindowDidHide() {
        debugLog("handleSettingsWindowDidHide()")
        applyDockIconVisibility()
    }

    private func applySelectedAppIcon() {
        let image: NSImage?
        switch settings.selectedAppIconVariant {
        case .default:
            image = NSWorkspace.shared.icon(forFile: Bundle.main.bundlePath)
        case .easterEggSVG4:
            image = NSImage(named: settings.selectedAppIconVariant.imageAssetName)
        }
        guard let image else { return }
        NSApp.applicationIconImage = image
    }

    private func configureStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let button = item.button {
            if let image = NSImage(named: "MenuBarIconTemplate") {
                image.isTemplate = true
                image.size = NSSize(width: 18, height: 18)
                button.image = image
                button.imagePosition = .imageOnly
                button.title = ""
            } else {
                button.title = "Voily"
            }
            button.toolTip = "Voily"
        }
        let menu = makeMenu()
        item.menu = menu
        statusItem = item
        statusMenu = menu
    }

    private func configureMainMenu() {
        let mainMenu = NSMenu()

        let appMenuItem = NSMenuItem()
        let appMenu = NSMenu(title: "Voily")

        let openSettingsItem = NSMenuItem(title: "设置…", action: #selector(openSettings), keyEquivalent: ",")
        openSettingsItem.target = self
        appMenu.addItem(openSettingsItem)

        let hideItem = NSMenuItem(title: "隐藏 Voily", action: #selector(NSApplication.hide(_:)), keyEquivalent: "h")
        appMenu.addItem(hideItem)
        appMenu.addItem(.separator())

        let quitItem = NSMenuItem(title: "退出 Voily", action: #selector(quit), keyEquivalent: "q")
        quitItem.target = self
        appMenu.addItem(quitItem)

        appMenuItem.submenu = appMenu
        mainMenu.addItem(appMenuItem)

        let editMenuItem = NSMenuItem()
        let editMenu = NSMenu(title: "Edit")
        editMenu.addItem(withTitle: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        editMenu.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        editMenu.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        editMenu.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        editMenuItem.submenu = editMenu
        mainMenu.addItem(editMenuItem)

        NSApp.mainMenu = mainMenu
    }

    private func makeMenu() -> NSMenu {
        let menu = NSMenu()
        menu.delegate = self

        let dashboardItem = NSMenuItem()
        dashboardItem.view = makeDashboardMenuView()
        dashboardItem.isEnabled = false
        menu.addItem(dashboardItem)
        dashboardMenuItem = dashboardItem

        menu.addItem(.separator())

        let voilyItem = NSMenuItem(title: "显示 Voily", action: #selector(openSettings), keyEquivalent: "")
        voilyItem.target = self
        menu.addItem(voilyItem)

        let quitItem = NSMenuItem(title: "Quit", action: #selector(quit), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)

        return menu
    }

    private func makeDashboardMenuView() -> NSView {
        let view = MenuDashboardMenuItemView(summary: usageStore.todaySummary, summaries: usageStore.weeklySummaries)
        let hostingView = NSHostingView(rootView: view)
        hostingView.frame = NSRect(x: 0, y: 0, width: 188, height: 102)
        hostingView.setFrameSize(NSSize(width: 188, height: 102))
        dashboardHostingView = hostingView
        return hostingView
    }

    private func refreshDashboardMenuItem() {
        usageStore.refresh()

        dashboardHostingView?.rootView = MenuDashboardMenuItemView(
            summary: usageStore.todaySummary,
            summaries: usageStore.weeklySummaries
        )
    }

    private func configureOverlayActions() {
        overlayController.onConfirm = { [weak self] in
            Task { @MainActor in
                await self?.confirmQuickTranslationRecording()
            }
        }

        overlayController.onCancel = { [weak self] in
            Task { @MainActor in
                await self?.cancelCurrentSession()
            }
        }
    }

    private func configureTriggerKeyMonitoring() {
        debugLog("configureTriggerKeyMonitoring()")
        triggerKeyMonitor.setTriggerKey(settings.triggerKey)
        triggerKeyMonitor.setSessionMode(triggerKeySessionMode)
        triggerKeyMonitor.onDictationStart = { [weak self] in
            debugLog("Trigger key dictation start callback")
            Task { @MainActor in
                await self?.beginRecording(mode: .dictation)
            }
        }

        triggerKeyMonitor.onDictationFinish = { [weak self] in
            debugLog("Trigger key dictation finish callback")
            Task { @MainActor in
                await self?.finishRecording()
            }
        }

        triggerKeyMonitor.onQuickTranslation = { [weak self] in
            debugLog("Trigger key quick translation callback")
            Task { @MainActor in
                await self?.beginRecording(mode: .quickTranslationZhToEn)
            }
        }

        triggerKeyMonitor.start()
    }

    private func configureTriggerKeyMonitoringIfNeeded() {
        guard permissionCoordinator.isAccessibilityTrusted else { return }
        guard !triggerKeyMonitor.isRunning else {
            debugLog("configureTriggerKeyMonitoringIfNeeded alreadyRunning=true")
            return
        }
        configureTriggerKeyMonitoring()
    }

    private func applyTriggerKey() {
        debugLog("applyTriggerKey key=\(settings.triggerKey.rawValue)")
        triggerKeyMonitor.setTriggerKey(settings.triggerKey)
        triggerKeyMonitor.setSessionMode(triggerKeySessionMode)
        configureTriggerKeyMonitoringIfNeeded()
    }

    func handleApplicationDidBecomeActive() {
        guard !isRunningUnderXCTest() else { return }
        debugLog(
            "handleApplicationDidBecomeActive trusted=\(permissionCoordinator.isAccessibilityTrusted) triggerKey=\(settings.triggerKey.rawValue) monitorRunning=\(triggerKeyMonitor.isRunning)"
        )
        configureTriggerKeyMonitoringIfNeeded()
    }

    private func setOverlay(text: String, rmsLevel: Float, phase: OverlayPhase) {
        debugLog("setOverlay phase=\(phase) textLength=\(text.count) rms=\(String(format: "%.3f", rmsLevel))")
        currentText = text
        currentPhase = phase
        currentOverlayControls = overlayControls(for: phase)
        overlayController.show(state: OverlayState(text: text, rmsLevel: rmsLevel, phase: phase, controls: currentOverlayControls))
    }

    private func updateRMS(_ newLevel: Float) {
        let attack: Float = 0.40
        let release: Float = 0.15
        let coefficient = newLevel > smoothedRMS ? attack : release
        smoothedRMS = smoothedRMS + ((newLevel - smoothedRMS) * coefficient)

        if currentPhase == .recording || currentPhase == .recordingPartial || currentPhase == .transcribing {
            overlayController.show(
                state: OverlayState(
                    text: currentText,
                    rmsLevel: smoothedRMS,
                    phase: currentPhase,
                    controls: currentOverlayControls
                )
            )
        }
    }

    private func beginRecording(mode: CaptureSessionMode) async {
        guard currentPhase == .idle else { return }
        debugLog("beginRecording mode=\(mode.debugName)")
        if mode == .quickTranslationZhToEn, !settings.isTextRefinementConfigured {
            triggerKeyMonitor.setSessionMode(.idle)
            await showTransientMessage("Set up a text model in Settings first.")
            return
        }

        guard await ensureRecordingPermissions(for: settings.selectedASRProvider) else {
            triggerKeyMonitor.setSessionMode(.idle)
            return
        }

        if settings.interruptSystemMediaPlayback {
            debugLog("System output mute enabled; attempting mute before \(mode.debugName)")
            currentAudioOutputMuteToken = await audioOutputMuteService.muteIfNeeded()
            debugLog("System output mute tokenCreated=\(currentAudioOutputMuteToken != nil)")
        } else {
            currentAudioOutputMuteToken = nil
        }

        currentSessionMode = mode
        currentText = ""
        smoothedRMS = 0
        currentSessionStartedAt = Date()
        currentFirstPartialMs = nil
        currentPartialCount = 0
        currentCaptureAppendError = nil
        realtimeAppendCounter.reset()
        activeASRSession = nil
        triggerKeyMonitor.setSessionMode(mode == .dictation ? .dictating : .translating)
        setOverlay(text: "", rmsLevel: 0, phase: .recording)

        do {
            let selectedASRProvider = settings.selectedASRProvider
            resetRealtimePartialDisplayState()
            let activeASRSession = asrCaptureSessionFactory.makeSession(
                provider: selectedASRProvider,
                languageCode: activeInputLanguageCode,
                config: settings.selectedASRConfig,
                glossaryTerms: settings.effectiveGlossaryItems,
                persistConfig: { [settings] updatedConfig in
                    settings.selectedASRConfig = updatedConfig
                }
            )
            self.activeASRSession = activeASRSession
            debugLog("Recording with ASR provider=\(activeASRSession.provider.rawValue)")
            try await activeASRSession.session.start { [weak self] partialText in
                Task { @MainActor in
                    self?.handleRealtimePartialText(partialText)
                }
            }

            try audioCaptureService.start(
                inputDeviceUID: settings.preferredMicrophoneUID
            ) { [weak self, appendCounter = realtimeAppendCounter, provider = activeASRSession.provider] buffer in
                appendCounter.increment()
                Task { @MainActor in
                    defer { appendCounter.decrement() }
                    guard let self else { return }
                    do {
                        try await self.handleCapturedBuffer(buffer)
                    } catch {
                        self.recordCaptureAppendErrorIfNeeded(error, provider: provider)
                    }
                }
            } onLevel: { [weak self] level in
                Task { @MainActor in
                    self?.updateRMS(level)
                }
            }
        } catch {
            NSLog("Recording start failed: \(error.localizedDescription)")
            await activeASRSession?.session.cancel()
            activeASRSession = nil
            currentCaptureAppendError = nil
            realtimeAppendCounter.reset()
            await restoreAudioOutputIfNeeded()
            currentSessionMode = nil
            currentOverlayControls = .none
            triggerKeyMonitor.setSessionMode(.idle)
            overlayController.hide()
            currentPhase = .idle
            currentSessionStartedAt = nil
        }
    }

    private func finishRecording() async {
        guard currentPhase == .recording || currentPhase == .recordingPartial else { return }
        guard let sessionMode = currentSessionMode else { return }
        debugLog("finishRecording mode=\(sessionMode.debugName)")
        triggerKeyMonitor.setSessionMode(.suspended)

        setOverlay(text: currentText, rmsLevel: smoothedRMS, phase: .transcribing)
        audioCaptureService.stop()
        await waitForPendingRealtimeAppends()

        let recognitionOutcome = await recognizeText()
        let recognizedText = recognitionOutcome.text
        currentText = recognizedText
        let endedAt = Date()

        guard !recognizedText.isEmpty else {
            await cleanupCurrentSession(hideOverlay: true)
            return
        }

        let finalText: String
        let didApplyTextProcessing: Bool
        switch sessionMode {
        case .dictation:
            if settings.textRefinementEnabled && settings.isTextRefinementConfigured {
                setOverlay(text: recognizedText, rmsLevel: 0, phase: .refining)

                do {
                    finalText = try await llmRefinementService.process(
                        TextProcessingRequest(
                            text: recognizedText,
                            languageCode: activeInputLanguageCode,
                            mode: .dictation(skills: settings.enabledDictationSkills)
                        ),
                        settings: settings
                    )
                } catch {
                    NSLog("LLM dictation processing failed: \(error.localizedDescription)")
                    finalText = recognizedText
                }
                didApplyTextProcessing = true
            } else {
                finalText = recognizedText
                didApplyTextProcessing = false
            }
        case .quickTranslationZhToEn:
            setOverlay(text: "", rmsLevel: 0, phase: .translating)

            do {
                finalText = try await llmRefinementService.process(
                    TextProcessingRequest(
                        text: recognizedText,
                        languageCode: SupportedLanguage.simplifiedChinese.rawValue,
                        mode: .translateZhToEn(style: .natural)
                    ),
                    settings: settings
                )
                didApplyTextProcessing = true
            } catch {
                NSLog("LLM translation failed: \(error.localizedDescription)")
                await showTransientMessage("Translation failed. Try again.")
                await cleanupCurrentSession(hideOverlay: true)
                return
            }
        }

        let sessionID = usageStore.recordSession(
            VoiceInputSessionDraft(
                startedAt: currentSessionStartedAt ?? endedAt,
                endedAt: endedAt,
                languageCode: activeInputLanguageCode,
                recognizedText: recognizedText,
                finalText: finalText,
                refinementApplied: didApplyTextProcessing,
                asrProvider: recognitionOutcome.provider.rawValue,
                asrSource: recognitionOutcome.source,
                recognitionTotalMs: recognitionOutcome.totalDurationMs,
                recognitionEngineMs: recognitionOutcome.engineDurationMs,
                recognitionFirstPartialMs: recognitionOutcome.firstPartialMs,
                recognitionPartialCount: recognitionOutcome.partialCount
            )
        )

        setOverlay(text: finalText, rmsLevel: 0, phase: .injecting)
        let injectionResult = await textInjectionService.inject(text: finalText)
        if let sessionID {
            usageStore.markInjectionResult(sessionID: sessionID, succeeded: injectionResult == .success)
        }
        if injectionResult != .success {
            NSLog("Text injection finished with result: \(String(describing: injectionResult))")
            if injectionResult == .accessibilityDenied {
                permissionCoordinator.promptForAccessibilityIfNeeded(force: true)
            }
        }

        try? await Task.sleep(for: .milliseconds(150))
        await cleanupCurrentSession(hideOverlay: true)
    }

    private var activeInputLanguageCode: String {
        switch currentSessionMode {
        case .dictation, .none:
            return settings.selectedLanguageCode
        case .quickTranslationZhToEn:
            return SupportedLanguage.simplifiedChinese.rawValue
        }
    }

    private func overlayControls(for phase: OverlayPhase) -> OverlayControls {
        guard currentSessionMode == .quickTranslationZhToEn else {
            return .none
        }

        switch phase {
        case .recording, .recordingPartial:
            return .confirmCancel
        default:
            return .none
        }
    }

    private func confirmQuickTranslationRecording() async {
        guard currentSessionMode == .quickTranslationZhToEn else { return }
        await finishRecording()
    }

    private func cancelCurrentSession() async {
        guard currentSessionMode == .quickTranslationZhToEn else { return }
        debugLog("cancelCurrentSession()")
        triggerKeyMonitor.setSessionMode(.suspended)
        audioCaptureService.stop()
        await cleanupCurrentSession(hideOverlay: true)
    }

    private func cleanupCurrentSession(hideOverlay: Bool) async {
        debugLog(
            "cleanupCurrentSession hideOverlay=\(hideOverlay) outputMuteTokenPresent=\(currentAudioOutputMuteToken != nil)"
        )
        await activeASRSession?.session.cancel()
        activeASRSession = nil
        resetRealtimePartialDisplayState()
        await restoreAudioOutputIfNeeded()

        currentSessionMode = nil
        currentFirstPartialMs = nil
        currentPartialCount = 0
        currentCaptureAppendError = nil
        realtimeAppendCounter.reset()
        currentOverlayControls = .none
        currentText = ""
        currentPhase = .idle
        currentSessionStartedAt = nil
        smoothedRMS = 0
        triggerKeyMonitor.setSessionMode(.idle)

        if hideOverlay {
            overlayController.hide()
        }
    }

    private var triggerKeySessionMode: TriggerKeySessionMode {
        switch currentPhase {
        case .idle:
            return .idle
        case .recording, .recordingPartial:
            switch currentSessionMode {
            case .dictation:
                return .dictating
            case .quickTranslationZhToEn:
                return .translating
            case .none:
                return .idle
            }
        case .transcribing, .refining, .translating, .injecting:
            return .suspended
        }
    }

    private func showTransientMessage(_ text: String) async {
        overlayController.show(state: OverlayState(text: text, rmsLevel: 0, phase: .translating, controls: .none))
        try? await Task.sleep(for: .milliseconds(1100))
        if currentPhase == .idle {
            overlayController.hide()
        }
    }

    private func showPermissionGuidance(_ text: String) async {
        showSettingsWindow()
        await showTransientMessage(text)
    }

    private func requestSystemPermissionWhileTriggerKeyMonitoringPaused(_ request: @escaping () async -> Bool) async -> Bool {
        debugLog("Pausing trigger key monitoring for system permission prompt")
        triggerKeyMonitor.stop()
        overlayController.hide()
        NSApp.activate(ignoringOtherApps: true)
        try? await Task.sleep(for: .milliseconds(150))

        let granted = await request()

        debugLog("Resuming trigger key monitoring after system permission prompt granted=\(granted)")
        triggerKeyMonitor.start()
        return granted
    }

    private func ensureRecordingPermissions(for provider: ASRProvider) async -> Bool {
        switch permissionCoordinator.microphoneAuthorizationStatus {
        case .authorized:
            break
        case .notDetermined:
            let granted = await requestSystemPermissionWhileTriggerKeyMonitoringPaused { [permissionCoordinator] in
                await permissionCoordinator.requestMicrophoneIfNeeded()
            }
            if !granted {
                await showPermissionGuidance("Enable Microphone access in System Settings to start recording.")
                return false
            }
        case .denied, .restricted:
            await showPermissionGuidance("Enable Microphone access in System Settings to start recording.")
            return false
        @unknown default:
            await showPermissionGuidance("Enable Microphone access in System Settings to start recording.")
            return false
        }

        return true
    }

    private func recognizeText() async -> RecognitionOutcome {
        let provider = activeASRSession?.provider ?? settings.selectedASRProvider
        debugLog("ASR selection provider=\(provider.rawValue)")
        let recognitionStartedAt = Date()
        guard let activeASRSession else {
            let totalDurationMs = Int(Date().timeIntervalSince(recognitionStartedAt) * 1000)
            return RecognitionOutcome(
                text: "",
                provider: provider,
                source: "\(provider.category.rawValue)-failed",
                totalDurationMs: totalDurationMs,
                engineDurationMs: nil,
                firstPartialMs: currentFirstPartialMs,
                partialCount: currentPartialCount
            )
        }

        do {
            let startedAt = Date()
            if let currentCaptureAppendError {
                throw currentCaptureAppendError
            }
            let result = try await activeASRSession.session.finish()
            let durationMs = Int(Date().timeIntervalSince(startedAt) * 1000)
            let totalDurationMs = Int(Date().timeIntervalSince(recognitionStartedAt) * 1000)
            let text = result.text.trimmingCharacters(in: .whitespacesAndNewlines)
            let commandSummary = result.commandSummary ?? ""
            debugLog(
                "ASR finished provider=\(provider.rawValue) source=\(result.source) totalMs=\(totalDurationMs) engineMs=\(durationMs) textLength=\(text.count) command=\(commandSummary)"
            )
            return RecognitionOutcome(
                text: text,
                provider: provider,
                source: result.source,
                totalDurationMs: totalDurationMs,
                engineDurationMs: durationMs,
                firstPartialMs: currentFirstPartialMs,
                partialCount: currentPartialCount
            )
        } catch {
            let totalDurationMs = Int(Date().timeIntervalSince(recognitionStartedAt) * 1000)
            let failedSource = provider.category == .local ? "local-failed" : "cloud-realtime-failed"
            debugLog(
                "ASR finished provider=\(provider.rawValue) source=\(failedSource) totalMs=\(totalDurationMs) reason=\(error.localizedDescription)"
            )
            return RecognitionOutcome(
                text: "",
                provider: provider,
                source: failedSource,
                totalDurationMs: totalDurationMs,
                engineDurationMs: nil,
                firstPartialMs: currentFirstPartialMs,
                partialCount: currentPartialCount
            )
        }
    }

    private func handleCapturedBuffer(_ buffer: AVAudioPCMBuffer) async throws {
        guard currentPhase == .recording || currentPhase == .recordingPartial else { return }
        guard let activeASRSession else { return }
        try await activeASRSession.session.append(buffer)
    }

    private func recordCaptureAppendErrorIfNeeded(_ error: Error, provider: ASRProvider) {
        if currentCaptureAppendError == nil {
            currentCaptureAppendError = error
        }
        debugLog("ASR capture append failed provider=\(provider.rawValue) error=\(error.localizedDescription)")
    }

    private func applyPartialTextToOverlay(_ partialText: String) {
        guard currentPhase == .recording || currentPhase == .recordingPartial else { return }
        let trimmed = partialText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        if trimmed == currentText {
            return
        }
        currentText = trimmed
        currentPhase = .recordingPartial
        if let currentSessionStartedAt, currentFirstPartialMs == nil {
            currentFirstPartialMs = Int(Date().timeIntervalSince(currentSessionStartedAt) * 1000)
        }
        currentPartialCount += 1
        setOverlay(text: trimmed, rmsLevel: smoothedRMS, phase: .recordingPartial)
    }

    private func handleRealtimePartialText(_ partialText: String) {
        let now = CACurrentMediaTime()
        if let throttledText = realtimePartialDisplayThrottle.push(partialText, at: now) {
            realtimePartialFlushTask?.cancel()
            realtimePartialFlushTask = nil
            applyPartialTextToOverlay(throttledText)
            return
        }

        scheduleRealtimePartialFlushIfNeeded(now: now)
    }

    private func scheduleRealtimePartialFlushIfNeeded(now: TimeInterval) {
        guard realtimePartialFlushTask == nil else { return }
        guard let delay = realtimePartialDisplayThrottle.delayUntilNextEmission(at: now) else { return }

        realtimePartialFlushTask = Task { [weak self] in
            if delay > 0 {
                try? await Task.sleep(for: .milliseconds(Int((delay * 1000).rounded())))
            }
            await MainActor.run {
                self?.flushRealtimePartialIfNeeded()
            }
        }
    }

    private func flushRealtimePartialIfNeeded() {
        realtimePartialFlushTask = nil
        guard currentPhase == .recording || currentPhase == .recordingPartial else { return }
        if let text = realtimePartialDisplayThrottle.flush(at: CACurrentMediaTime()) {
            applyPartialTextToOverlay(text)
        }
    }

    private func resetRealtimePartialDisplayState() {
        realtimePartialFlushTask?.cancel()
        realtimePartialFlushTask = nil
        realtimePartialDisplayThrottle.reset()
    }

    private func waitForPendingRealtimeAppends() async {
        guard activeASRSession != nil else { return }
        let deadline = Date().addingTimeInterval(1.5)
        while realtimeAppendCounter.value > 0, Date() < deadline {
            try? await Task.sleep(for: .milliseconds(20))
        }
        let pendingCount = realtimeAppendCounter.value
        if pendingCount > 0 {
            debugLog("Realtime pending appends timed out count=\(pendingCount)")
        }
    }

    private func restoreAudioOutputIfNeeded() async {
        guard let token = currentAudioOutputMuteToken else {
            debugLog("restoreAudioOutputIfNeeded skipped tokenPresent=false")
            return
        }

        debugLog("restoreAudioOutputIfNeeded tokenPresent=true")
        await audioOutputMuteService.restoreIfNeeded(token)
        currentAudioOutputMuteToken = nil
    }

    @objc
    private func openSettings() {
        debugLog("openSettings()")
        showSettingsWindow()
    }

    @objc
    private func quit() {
        debugLog("quit()")
        NSApp.terminate(nil)
    }
}

extension AppController: NSMenuDelegate {
    func menuWillOpen(_ menu: NSMenu) {
        guard menu === statusMenu else { return }
        refreshDashboardMenuItem()
    }
}

private struct MenuDashboardMenuItemView: View {
    let summary: TodayUsageSummary
    let summaries: [DailyUsageSummary]
    private let chartWidth: CGFloat = 160
    private let horizontalPadding: CGFloat = 14

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            VStack(alignment: .leading, spacing: 6) {
                Text("今日概览")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.secondary)

                Text(summaryLine)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }

            MenuMiniSparklineView(summaries: summaries)
                .frame(width: chartWidth, height: 40, alignment: .leading)
        }
        .padding(.horizontal, horizontalPadding)
        .padding(.top, 14)
        .padding(.bottom, 12)
        .frame(width: chartWidth + horizontalPadding * 2, height: 102, alignment: .leading)
        .background(Color.clear)
        .allowsHitTesting(false)
    }

    private var summaryLine: String {
        "\(formattedDuration(summary.totalDurationMs)) · \(summary.sessionCount) 次 · \(summary.totalCharacters) 字"
    }

    private func formattedDuration(_ durationMs: Int) -> String {
        let totalSeconds = max(0, durationMs / 1000)
        let minutes = totalSeconds / 60
        let seconds = totalSeconds % 60

        if minutes > 0 {
            return "\(minutes) 分 \(seconds) 秒"
        }

        return "\(seconds) 秒"
    }
}

private struct MenuMiniSparklineView: View {
    let summaries: [DailyUsageSummary]

    var body: some View {
        let chartData = normalizedChartData
        let maxValue = max(chartData.map(\.value).max() ?? 0, 1)
        let paddedMaxValue = max(1, Int((Double(maxValue) * 1.18).rounded(.up)))

        Chart(chartData) { item in
            AreaMark(
                x: .value("Day", item.date),
                y: .value("Duration", item.value)
            )
            .interpolationMethod(.catmullRom)
            .foregroundStyle(
                .linearGradient(
                    colors: [
                        Color.accentColor.opacity(hasNonZeroValue ? 0.24 : 0.10),
                        Color.accentColor.opacity(0.02)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )

            LineMark(
                x: .value("Day", item.date),
                y: .value("Duration", item.value)
            )
            .interpolationMethod(.catmullRom)
            .foregroundStyle(Color.accentColor.opacity(hasNonZeroValue ? 0.95 : 0.4))
            .lineStyle(StrokeStyle(lineWidth: 2.5, lineCap: .round, lineJoin: .round))

            if item.isLastPoint {
                PointMark(
                    x: .value("Day", item.date),
                    y: .value("Duration", item.value)
                )
                .symbolSize(18)
                .foregroundStyle(Color.accentColor.opacity(hasNonZeroValue ? 0.95 : 0.4))
            }
        }
        .chartXAxis(.hidden)
        .chartYAxis(.hidden)
        .chartLegend(.hidden)
        .chartXScale(range: .plotDimension(startPadding: 10, endPadding: 10))
        .chartPlotStyle { plot in
            plot
                .background(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(Color.primary.opacity(0.05))
                )
        }
        .chartYScale(
            domain: 0...paddedMaxValue,
            range: .plotDimension(startPadding: 6, endPadding: 8)
        )
        .clipped()
        .accessibilityHidden(true)
    }

    private var hasNonZeroValue: Bool {
        summaries.contains(where: { $0.totalDurationMs > 0 })
    }

    private var normalizedChartData: [MenuChartPoint] {
        let base = summaries.isEmpty
            ? [
                MenuChartPoint(date: Date().addingTimeInterval(-86_400), value: 0, isLastPoint: false),
                MenuChartPoint(date: Date(), value: 0, isLastPoint: true),
            ]
            : summaries.enumerated().map { index, summary in
                MenuChartPoint(
                    date: summary.date,
                    value: summary.totalDurationMs,
                    isLastPoint: index == summaries.count - 1
                )
            }

        return base
    }
}

private struct MenuChartPoint: Identifiable {
    let date: Date
    let value: Int
    let isLastPoint: Bool

    var id: Date { date }
}

#Preview("Menu Dashboard") {
    let usageStore = UsageStore()

    MenuDashboardMenuItemView(
        summary: usageStore.todaySummary,
        summaries: usageStore.weeklySummaries
    )
    .padding()
    .frame(width: 320)
    .background(Color(nsColor: .windowBackgroundColor))
}
