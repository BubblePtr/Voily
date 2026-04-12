import AppKit
import AVFoundation
import Charts
import Foundation
import Observation
import SwiftUI

func isRunningInXcodePreview() -> Bool {
    ProcessInfo.processInfo.environment["XCODE_RUNNING_FOR_PREVIEWS"] == "1"
}

func debugLog(_ message: String) {
    let line = "[Voily] \(message)\n"
    let data = Data(line.utf8)
    let url = URL(fileURLWithPath: "/tmp/voily.log")

    if FileManager.default.fileExists(atPath: url.path) {
        if let handle = try? FileHandle(forWritingTo: url) {
            defer { try? handle.close() }
            _ = try? handle.seekToEnd()
            try? handle.write(contentsOf: data)
        }
    } else {
        try? data.write(to: url)
    }
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

@available(macOS 26.0, *)
@MainActor
final class WindowActions {
    var showSettingsWindow: () -> Void = {}
}

@available(macOS 26.0, *)
@MainActor
final class AppController: NSObject {
    private let windowActions: WindowActions
    private let settings = AppSettings()
    private let usageStore = UsageStore()
    private let permissionCoordinator = PermissionCoordinator()
    private let fnKeyMonitor = FnKeyMonitor()
    private let audioCaptureService = AudioCaptureService()
    private let speechService = SpeechTranscriptionService()
    private let senseVoiceResidentService = SenseVoiceResidentService()
    private let qwenRealtimeASRService = QwenRealtimeASRService()
    private let managedASRModels = ManagedASRModelStore()
    private let overlayController = OverlayPanelController()
    private let textInjectionService = TextInjectionService()
    private let llmRefinementService = LLMRefinementService()

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
    private var localAudioWriter: TemporaryAudioCaptureWriter?
    private var currentResidentSession: SenseVoiceResidentSession?
    private var currentFirstPartialMs: Int?
    private var currentPartialCount = 0
    private var currentSpeechCaptureEnabled = false
    private var currentPendingRealtimeAppendCount = 0
    private var hasStopped = false

    init(windowActions: WindowActions) {
        self.windowActions = windowActions
    }

    func start() {
        debugLog("AppController.start()")
        configureMainMenu()
        configureStatusItem()
        observeDockIconPreference()
        observeAppIconPreference()
        configureOverlayActions()
        configureAccessibilityFeatures()
    }

    func stop() async {
        guard !hasStopped else { return }
        hasStopped = true

        debugLog("AppController.stop()")
        fnKeyMonitor.stop()
        audioCaptureService.stop()
        speechService.cancel()
        if let currentResidentSession {
            await senseVoiceResidentService.cancelSession(currentResidentSession)
        }
        try? await qwenRealtimeASRService.cancelSession()
        await senseVoiceResidentService.stop()
        currentResidentSession = nil
        localAudioWriter?.cancel()
        localAudioWriter = nil
        currentSessionMode = nil
        currentOverlayControls = .none
    }

    func showSettingsWindow() {
        NSApp.activate(ignoringOtherApps: true)
        windowActions.showSettingsWindow()
    }

    func handleReopen(hasVisibleWindows: Bool) -> Bool {
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
                debugLog("Accessibility granted, starting fn monitoring")
                self?.configureFnMonitoring()
            }
            return
        }

        debugLog("Accessibility already trusted, starting fn monitoring")
        configureFnMonitoring()
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

    func registerShowSettingsWindowAction(_ action: @escaping () -> Void) {
        windowActions.showSettingsWindow = action
    }

    func makeSettingsWindowSceneView() -> some View {
        SettingsWindowSceneView(
            settings: settings,
            usageStore: usageStore,
            llmService: llmRefinementService,
            managedASRModels: managedASRModels,
            registerShowWindowAction: registerShowSettingsWindowAction(_:)
        )
    }

    private func applyDockIconVisibility() {
        let policy: NSApplication.ActivationPolicy = settings.dockIconVisible ? .regular : .accessory
        guard NSApp.activationPolicy() != policy else { return }
        NSApp.setActivationPolicy(policy)
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

    private func configureFnMonitoring() {
        debugLog("configureFnMonitoring()")
        fnKeyMonitor.onDictationStart = { [weak self] in
            debugLog("Fn dictation start callback")
            Task { @MainActor in
                await self?.beginRecording(mode: .dictation)
            }
        }

        fnKeyMonitor.onDictationFinish = { [weak self] in
            debugLog("Fn dictation finish callback")
            Task { @MainActor in
                await self?.finishRecording()
            }
        }

        fnKeyMonitor.onQuickTranslation = { [weak self] in
            debugLog("Fn quick translation callback")
            Task { @MainActor in
                await self?.beginRecording(mode: .quickTranslationZhToEn)
            }
        }

        fnKeyMonitor.start()
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
            await showTransientMessage("Set up a text model in Settings first.")
            return
        }

        guard await ensureRecordingPermissions(for: settings.selectedASRProvider) else {
            return
        }

        currentSessionMode = mode
        currentText = ""
        smoothedRMS = 0
        currentSessionStartedAt = Date()
        currentFirstPartialMs = nil
        currentPartialCount = 0
        currentResidentSession = nil
        currentSpeechCaptureEnabled = false
        currentPendingRealtimeAppendCount = 0
        setOverlay(text: "", rmsLevel: 0, phase: .recording)

        do {
            let selectedASRProvider = settings.selectedASRProvider
            if selectedASRProvider.category == .local {
                debugLog("Recording with local ASR provider=\(selectedASRProvider.rawValue)")
                localAudioWriter = TemporaryAudioCaptureWriter()
            } else {
                if selectedASRProvider == .qwenASR {
                    try await startQwenRealtimeSession()
                } else if selectedASRProvider.category == .cloud {
                    debugLog("Cloud ASR provider not implemented provider=\(selectedASRProvider.rawValue) fallback=true")
                    try speechService.start(localeIdentifier: activeInputLanguageCode) { [weak self] text in
                        guard let self else { return }
                        self.setOverlay(text: text, rmsLevel: self.smoothedRMS, phase: .recording)
                    }
                    currentSpeechCaptureEnabled = true
                }
            }

            try audioCaptureService.start(inputDeviceUID: settings.preferredMicrophoneUID) { [weak self] buffer in
                self?.handleCapturedBuffer(buffer)
                Task { @MainActor in
                    if self?.currentSpeechCaptureEnabled == true {
                        self?.speechService.append(buffer)
                    }
                }
            } onLevel: { [weak self] level in
                Task { @MainActor in
                    self?.updateRMS(level)
                }
            }
        } catch {
            NSLog("Recording start failed: \(error.localizedDescription)")
            speechService.cancel()
            localAudioWriter?.cancel()
            localAudioWriter = nil
            if let currentResidentSession {
                Task {
                    await self.senseVoiceResidentService.cancelSession(currentResidentSession)
                }
            }
            currentResidentSession = nil
            currentPendingRealtimeAppendCount = 0
            currentSessionMode = nil
            currentOverlayControls = .none
            overlayController.hide()
            currentPhase = .idle
            currentSessionStartedAt = nil
        }
    }

    private func finishRecording() async {
        guard currentPhase == .recording || currentPhase == .recordingPartial else { return }
        guard let sessionMode = currentSessionMode else { return }
        debugLog("finishRecording mode=\(sessionMode.debugName)")

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
        audioCaptureService.stop()
        await cleanupCurrentSession(hideOverlay: true)
    }

    private func cleanupCurrentSession(hideOverlay: Bool) async {
        speechService.cancel()
        localAudioWriter?.cancel()
        localAudioWriter = nil

        if let currentResidentSession {
            await senseVoiceResidentService.cancelSession(currentResidentSession)
        }
        currentResidentSession = nil
        try? await qwenRealtimeASRService.cancelSession()

        currentSessionMode = nil
        currentSpeechCaptureEnabled = false
        currentFirstPartialMs = nil
        currentPartialCount = 0
        currentPendingRealtimeAppendCount = 0
        currentOverlayControls = .none
        currentText = ""
        currentPhase = .idle
        currentSessionStartedAt = nil
        smoothedRMS = 0

        if hideOverlay {
            overlayController.hide()
        }
    }

    private func showTransientMessage(_ text: String) async {
        overlayController.show(state: OverlayState(text: text, rmsLevel: 0, phase: .translating, controls: .none))
        try? await Task.sleep(for: .milliseconds(1100))
        if currentPhase == .idle {
            overlayController.hide()
        }
    }

    private func requestSystemPermissionWhileFnMonitoringPaused(_ request: @escaping () async -> Bool) async -> Bool {
        debugLog("Pausing Fn monitoring for system permission prompt")
        fnKeyMonitor.stop()
        overlayController.hide()
        NSApp.activate(ignoringOtherApps: true)
        try? await Task.sleep(for: .milliseconds(150))

        let granted = await request()

        debugLog("Resuming Fn monitoring after system permission prompt granted=\(granted)")
        fnKeyMonitor.start()
        return granted
    }

    private func ensureRecordingPermissions(for provider: ASRProvider) async -> Bool {
        switch permissionCoordinator.microphoneAuthorizationStatus {
        case .authorized:
            break
        case .notDetermined:
            let granted = await requestSystemPermissionWhileFnMonitoringPaused { [permissionCoordinator] in
                await permissionCoordinator.requestMicrophoneIfNeeded()
            }
            if granted {
                await showTransientMessage("Microphone access granted. Hold Fn again to start recording.")
            } else {
                await showTransientMessage("Allow microphone access to start recording.")
            }
            return false
        case .denied, .restricted:
            await showTransientMessage("Allow microphone access to start recording.")
            return false
        @unknown default:
            await showTransientMessage("Allow microphone access to start recording.")
            return false
        }

        guard provider == .doubaoStreaming else {
            return true
        }

        switch permissionCoordinator.speechRecognitionAuthorizationStatus {
        case .authorized:
            return true
        case .notDetermined:
            let granted = await requestSystemPermissionWhileFnMonitoringPaused { [permissionCoordinator] in
                await permissionCoordinator.requestSpeechRecognitionIfNeeded()
            }
            if granted {
                await showTransientMessage("Speech Recognition access granted. Hold Fn again to start recording.")
            } else {
                await showTransientMessage("Allow Speech Recognition to use the system transcription fallback.")
            }
            return false
        case .denied, .restricted:
            await showTransientMessage("Allow Speech Recognition to use the system transcription fallback.")
            return false
        @unknown default:
            await showTransientMessage("Allow Speech Recognition to use the system transcription fallback.")
            return false
        }
    }

    private func recognizeText() async -> RecognitionOutcome {
        let provider = settings.selectedASRProvider
        debugLog("ASR selection provider=\(provider.rawValue)")
        let recognitionStartedAt = Date()

        switch provider.category {
        case .local:
            defer {
                localAudioWriter?.cancel()
                localAudioWriter = nil
            }

            do {
                guard let localAudioWriter else {
                    throw LocalASRError.noAudioCaptured
                }

                let audioFinalizeStartedAt = Date()
                let audioFileURL = try localAudioWriter.finalize()
                let audioFinalizeDurationMs = Int(Date().timeIntervalSince(audioFinalizeStartedAt) * 1000)
                defer { try? FileManager.default.removeItem(at: audioFileURL) }

                let localTranscriptionStartedAt = Date()
                let result = try await transcribeLocally(audioFileURL: audioFileURL)
                let localTranscriptionDurationMs = Int(Date().timeIntervalSince(localTranscriptionStartedAt) * 1000)
                let totalDurationMs = Int(Date().timeIntervalSince(recognitionStartedAt) * 1000)
                let text = result.text.trimmingCharacters(in: .whitespacesAndNewlines)
                debugLog(
                    "ASR finished provider=\(provider.rawValue) source=local totalMs=\(totalDurationMs) audioFinalizeMs=\(audioFinalizeDurationMs) localTranscribeMs=\(localTranscriptionDurationMs) textLength=\(text.count) command=\(result.commandSummary)"
                )
                return RecognitionOutcome(
                    text: text,
                    provider: provider,
                    source: "local",
                    totalDurationMs: totalDurationMs,
                    engineDurationMs: localTranscriptionDurationMs,
                    firstPartialMs: currentFirstPartialMs,
                    partialCount: currentPartialCount
                )
            } catch {
                let totalDurationMs = Int(Date().timeIntervalSince(recognitionStartedAt) * 1000)
                debugLog(
                    "ASR finished provider=\(provider.rawValue) source=local-failed totalMs=\(totalDurationMs) reason=\(error.localizedDescription)"
                )
                return RecognitionOutcome(
                    text: "",
                    provider: provider,
                    source: "local-failed",
                    totalDurationMs: totalDurationMs,
                    engineDurationMs: nil,
                    firstPartialMs: currentFirstPartialMs,
                    partialCount: currentPartialCount
                )
            }
        case .cloud:
            if provider == .qwenASR {
                do {
                    let startedAt = Date()
                    let result = try await qwenRealtimeASRService.finishSession()
                    let durationMs = Int(Date().timeIntervalSince(startedAt) * 1000)
                    let totalDurationMs = Int(Date().timeIntervalSince(recognitionStartedAt) * 1000)
                    let text = result.text.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)
                    debugLog(
                        "ASR finished provider=\(provider.rawValue) source=cloud-realtime totalMs=\(totalDurationMs) realtimeMs=\(durationMs) textLength=\(text.count) command=\(result.commandSummary)"
                    )
                    return RecognitionOutcome(
                        text: text,
                        provider: provider,
                        source: "cloud-realtime",
                        totalDurationMs: totalDurationMs,
                        engineDurationMs: durationMs,
                        firstPartialMs: currentFirstPartialMs,
                        partialCount: currentPartialCount
                    )
                } catch {
                    let totalDurationMs = Int(Date().timeIntervalSince(recognitionStartedAt) * 1000)
                    debugLog(
                        "ASR finished provider=\(provider.rawValue) source=cloud-realtime-failed totalMs=\(totalDurationMs) reason=\(error.localizedDescription)"
                    )
                    return RecognitionOutcome(
                        text: "",
                        provider: provider,
                        source: "cloud-realtime-failed",
                        totalDurationMs: totalDurationMs,
                        engineDurationMs: nil,
                        firstPartialMs: currentFirstPartialMs,
                        partialCount: currentPartialCount
                    )
                }
            }

            let speechStartedAt = Date()
            let text = await speechService.finish().trimmingCharacters(in: .whitespacesAndNewlines)
            let speechDurationMs = Int(Date().timeIntervalSince(speechStartedAt) * 1000)
            let totalDurationMs = Int(Date().timeIntervalSince(recognitionStartedAt) * 1000)
            debugLog(
                "ASR finished provider=\(provider.rawValue) source=system-speech totalMs=\(totalDurationMs) speechMs=\(speechDurationMs) textLength=\(text.count)"
            )
            return RecognitionOutcome(
                text: text,
                provider: provider,
                source: "system-speech",
                totalDurationMs: totalDurationMs,
                engineDurationMs: speechDurationMs,
                firstPartialMs: nil,
                partialCount: 0
            )
        }
    }

    private func transcribeLocally(audioFileURL _: URL) async throws -> LocalASRTranscriptionResult {
        guard let currentResidentSession else {
            throw SenseVoiceResidentServiceError.serverUnavailable
        }
        let result = try await senseVoiceResidentService.finalizeSession(currentResidentSession)
        debugLog("SenseVoice resident succeeded durationMs=\(Int(result.duration * 1000))")
        return result
    }

    private func handleCapturedBuffer(_ buffer: AVAudioPCMBuffer) {
        localAudioWriter?.append(buffer)

        let provider = settings.selectedASRProvider
        guard provider == .senseVoice || provider == .qwenASR else {
            return
        }

        let pcmData: Data
        do {
            let targetSampleRate = provider == .qwenASR ? 16_000.0 : buffer.format.sampleRate
            pcmData = try TemporaryAudioCaptureWriter.pcm16MonoData(from: buffer, targetSampleRate: targetSampleRate)
        } catch {
            debugLog("\(provider.rawValue) chunk encode failed error=\(error.localizedDescription)")
            return
        }

        Task { @MainActor in
            if provider == .senseVoice {
                await appendSenseVoiceChunk(pcmData, sampleRate: buffer.format.sampleRate)
            } else {
                await appendQwenRealtimeChunk(pcmData)
            }
        }
    }

    private func appendSenseVoiceChunk(_ pcmData: Data, sampleRate: Double) async {
        guard currentPhase == .recording || currentPhase == .recordingPartial else { return }
        currentPendingRealtimeAppendCount += 1
        defer { currentPendingRealtimeAppendCount = max(0, currentPendingRealtimeAppendCount - 1) }

        do {
            if currentResidentSession == nil {
                currentResidentSession = try await senseVoiceResidentService.startSession(
                    sampleRate: sampleRate,
                    languageCode: activeInputLanguageCode
                )
                debugLog("SenseVoice resident session started")
            }

            guard let currentResidentSession else { return }
            try await senseVoiceResidentService.appendAudio(
                sessionID: currentResidentSession.id,
                pcm16MonoData: pcmData
            )
        } catch {
            debugLog("SenseVoice resident append failed error=\(error.localizedDescription)")
        }
    }

    private func startQwenRealtimeSession() async throws {
        try await qwenRealtimeASRService.startSession(
            config: settings.selectedASRConfig,
            languageCode: activeInputLanguageCode
        ) { [weak self] partialText in
            Task { @MainActor in
                self?.handleQwenPartialText(partialText)
            }
        }
        debugLog("Qwen realtime session started")
    }

    private func appendQwenRealtimeChunk(_ pcmData: Data) async {
        guard currentPhase == .recording || currentPhase == .recordingPartial else { return }
        currentPendingRealtimeAppendCount += 1
        defer { currentPendingRealtimeAppendCount = max(0, currentPendingRealtimeAppendCount - 1) }

        do {
            try await qwenRealtimeASRService.appendAudioChunk(pcmData)
        } catch {
            debugLog("Qwen realtime append failed error=\(error.localizedDescription)")
        }
    }

    private func handleQwenPartialText(_ partialText: String) {
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

    private func waitForPendingRealtimeAppends() async {
        guard settings.selectedASRProvider == .senseVoice || settings.selectedASRProvider == .qwenASR else { return }
        let deadline = Date().addingTimeInterval(1.5)
        while currentPendingRealtimeAppendCount > 0, Date() < deadline {
            try? await Task.sleep(for: .milliseconds(20))
        }
        if currentPendingRealtimeAppendCount > 0 {
            debugLog("Realtime pending appends timed out count=\(currentPendingRealtimeAppendCount)")
        }
    }

    @objc
    private func openSettings() {
        showSettingsWindow()
    }

    @objc
    private func quit() {
        NSApp.terminate(nil)
    }
}

@available(macOS 26.0, *)
extension AppController: NSMenuDelegate {
    func menuWillOpen(_ menu: NSMenu) {
        guard menu === statusMenu else { return }
        refreshDashboardMenuItem()
    }
}

@available(macOS 26.0, *)
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

@available(macOS 26.0, *)
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

@available(macOS 26.0, *)
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
