import AppKit
import AVFoundation
import Foundation

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
final class AppController: NSObject {
    private let settings = AppSettings()
    private let usageStore = UsageStore()
    private let permissionCoordinator = PermissionCoordinator()
    private let fnKeyMonitor = FnKeyMonitor()
    private let audioCaptureService = AudioCaptureService()
    private let speechService = SpeechTranscriptionService()
    private let localASRService = LocalASRService()
    private let senseVoiceResidentService = SenseVoiceResidentService()
    private let qwenRealtimeASRService = QwenRealtimeASRService()
    private let managedASRModels = ManagedASRModelStore()
    private let overlayController = OverlayPanelController()
    private let textInjectionService = TextInjectionService()
    private let llmRefinementService = LLMRefinementService()

    private lazy var settingsWindowController = SettingsWindowController(
        settings: settings,
        usageStore: usageStore,
        llmService: llmRefinementService,
        managedASRModels: managedASRModels
    )

    private var statusItem: NSStatusItem?
    private var languageMenuItems: [SupportedLanguage: NSMenuItem] = [:]
    private var textRefinementMenuItem: NSMenuItem?
    private var currentPhase: OverlayPhase = .idle
    private var currentOverlayControls: OverlayControls = .none
    private var currentText = ""
    private var smoothedRMS: Float = 0
    private var currentSessionStartedAt: Date?
    private var currentSessionMode: CaptureSessionMode?
    private var localAudioWriter: TemporaryAudioCaptureWriter?
    private var currentResidentSession: SenseVoiceResidentSession?
    private var partialPollingTask: Task<Void, Never>?
    private var partialPollingInFlight = false
    private var currentFirstPartialMs: Int?
    private var currentPartialCount = 0
    private var currentSpeechCaptureEnabled = false
    private var currentPendingRealtimeAppendCount = 0

    func start() {
        debugLog("AppController.start()")
        configureStatusItem()
        configureOverlayActions()
        permissionCoordinator.requestStartupPermissions()
        configureAccessibilityFeatures()
    }

    func stop() {
        debugLog("AppController.stop()")
        fnKeyMonitor.stop()
        audioCaptureService.stop()
        speechService.cancel()
        partialPollingTask?.cancel()
        Task {
            if let currentResidentSession {
                await senseVoiceResidentService.cancelSession(currentResidentSession)
            }
            try? await qwenRealtimeASRService.cancelSession()
            await senseVoiceResidentService.stop()
        }
        currentSessionMode = nil
        currentOverlayControls = .none
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
        item.menu = makeMenu()
        statusItem = item
    }

    private func makeMenu() -> NSMenu {
        let menu = NSMenu()

        let languageItem = NSMenuItem(title: "Language", action: nil, keyEquivalent: "")
        languageItem.submenu = makeLanguageMenu()
        menu.addItem(languageItem)

        let textRefinementItem = NSMenuItem(title: "Text Processing", action: nil, keyEquivalent: "")
        textRefinementItem.submenu = makeTextRefinementMenu()
        menu.addItem(textRefinementItem)

        let hintItem = NSMenuItem(title: "Hold Fn to Dictate · Double Fn to Translate", action: nil, keyEquivalent: "")
        hintItem.isEnabled = false
        menu.addItem(hintItem)

        menu.addItem(.separator())

        let settingsItem = NSMenuItem(title: "Settings", action: #selector(openSettings), keyEquivalent: ",")
        settingsItem.target = self
        menu.addItem(settingsItem)

        menu.addItem(.separator())

        let quitItem = NSMenuItem(title: "Quit Voily", action: #selector(quit), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)

        return menu
    }

    private func makeLanguageMenu() -> NSMenu {
        let menu = NSMenu()
        languageMenuItems.removeAll()

        for language in SupportedLanguage.allCases {
            let item = NSMenuItem(title: language.displayName, action: #selector(selectLanguage(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = language.rawValue
            item.state = settings.selectedLanguage == language ? .on : .off
            languageMenuItems[language] = item
            menu.addItem(item)
        }

        return menu
    }

    private func makeTextRefinementMenu() -> NSMenu {
        let menu = NSMenu()

        let toggle = NSMenuItem(title: "Enable Dictation Processing", action: #selector(toggleLLM), keyEquivalent: "")
        toggle.target = self
        toggle.state = settings.textRefinementEnabled ? .on : .off
        textRefinementMenuItem = toggle
        menu.addItem(toggle)

        let settingsItem = NSMenuItem(title: "Settings…", action: #selector(openSettings), keyEquivalent: "")
        settingsItem.target = self
        menu.addItem(settingsItem)

        return menu
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

        currentSessionMode = mode
        currentText = ""
        smoothedRMS = 0
        currentSessionStartedAt = Date()
        currentFirstPartialMs = nil
        currentPartialCount = 0
        currentResidentSession = nil
        partialPollingTask?.cancel()
        partialPollingTask = nil
        partialPollingInFlight = false
        currentSpeechCaptureEnabled = false
        currentPendingRealtimeAppendCount = 0
        setOverlay(text: "", rmsLevel: 0, phase: .recording)

        do {
            let selectedASRProvider = settings.selectedASRProvider
            if selectedASRProvider.category == .local {
                debugLog("Recording with local ASR provider=\(selectedASRProvider.rawValue)")
                localAudioWriter = TemporaryAudioCaptureWriter()

                if selectedASRProvider == .senseVoice {
                    startSenseVoicePartialPolling()
                } else if selectedASRProvider == .qwenASR {
                    try await startQwenRealtimeSession()
                } else {
                    do {
                        try speechService.start(localeIdentifier: activeInputLanguageCode) { _ in }
                        currentSpeechCaptureEnabled = true
                    } catch {
                        debugLog("System Speech fallback unavailable for local provider=\(selectedASRProvider.rawValue) error=\(error.localizedDescription)")
                    }
                }
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

            try audioCaptureService.start { [weak self] buffer in
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
            partialPollingTask?.cancel()
            partialPollingTask = nil
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

        partialPollingTask?.cancel()
        partialPollingTask = nil
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
        partialPollingTask?.cancel()
        partialPollingTask = nil

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
        partialPollingInFlight = false

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

    private func recognizeText() async -> RecognitionOutcome {
        let provider = settings.selectedASRProvider
        debugLog("ASR selection provider=\(provider.rawValue)")
        let recognitionStartedAt = Date()

        switch provider.category {
        case .local:
            let fallbackTask: Task<(text: String, durationMs: Int), Never>? = if provider == .senseVoice {
                nil
            } else {
                Task { [speechService] in
                    let fallbackStartedAt = Date()
                    let text = await speechService.finish().trimmingCharacters(in: .whitespacesAndNewlines)
                    let fallbackDurationMs = Int(Date().timeIntervalSince(fallbackStartedAt) * 1000)
                    return (text: text, durationMs: fallbackDurationMs)
                }
            }

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
                let result = try await transcribeLocally(
                    provider: provider,
                    audioFileURL: audioFileURL
                )
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
                if provider == .senseVoice {
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

                let fallbackResult = await fallbackTask!.value
                let totalDurationMs = Int(Date().timeIntervalSince(recognitionStartedAt) * 1000)
                debugLog(
                    "ASR finished provider=\(provider.rawValue) source=speech-fallback totalMs=\(totalDurationMs) fallbackMs=\(fallbackResult.durationMs) textLength=\(fallbackResult.text.count) reason=\(error.localizedDescription)"
                )
                return RecognitionOutcome(
                    text: fallbackResult.text,
                    provider: provider,
                    source: "speech-fallback",
                    totalDurationMs: totalDurationMs,
                    engineDurationMs: fallbackResult.durationMs,
                    firstPartialMs: nil,
                    partialCount: 0
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

    private func transcribeLocally(provider: ASRProvider, audioFileURL: URL) async throws -> LocalASRTranscriptionResult {
        if provider == .senseVoice {
            guard let currentResidentSession else {
                throw SenseVoiceResidentServiceError.serverUnavailable
            }
            let result = try await senseVoiceResidentService.finalizeSession(currentResidentSession)
            debugLog("SenseVoice resident succeeded durationMs=\(Int(result.duration * 1000))")
            return result
        }

        return try await localASRService.transcribe(
            provider: provider,
            config: managedASRModels.managedConfig(for: provider) ?? settings.selectedASRConfig,
            audioFileURL: audioFileURL,
            languageCode: activeInputLanguageCode
        )
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

    private func startSenseVoicePartialPolling() {
        partialPollingTask?.cancel()
        partialPollingTask = Task { [weak self] in
            guard let self else { return }
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(500))
                await self.pollSenseVoicePartialIfNeeded()
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

    private func pollSenseVoicePartialIfNeeded() async {
        guard !partialPollingInFlight else { return }
        guard currentPhase == .recording || currentPhase == .recordingPartial else { return }
        guard let currentResidentSession, let currentSessionStartedAt else { return }

        let elapsedMs = Int(Date().timeIntervalSince(currentSessionStartedAt) * 1000)
        guard senseVoiceResidentService.shouldFetchPartial(elapsedMs: elapsedMs) else { return }

        partialPollingInFlight = true
        defer { partialPollingInFlight = false }

        do {
            guard let partialText = try await senseVoiceResidentService.fetchPartial(sessionID: currentResidentSession.id) else {
                return
            }
            guard shouldDisplayPartial(partialText) else {
                return
            }
            currentText = partialText
            currentPhase = .recordingPartial
            if currentFirstPartialMs == nil {
                currentFirstPartialMs = elapsedMs
            }
            currentPartialCount += 1
            setOverlay(text: partialText, rmsLevel: smoothedRMS, phase: .recordingPartial)
        } catch {
            debugLog("SenseVoice resident partial failed error=\(error.localizedDescription)")
        }
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

    private func shouldDisplayPartial(_ candidate: String) -> Bool {
        let trimmed = candidate.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= 4 else { return false }
        guard trimmed != "。" && trimmed != "，" && trimmed != "." && trimmed != "," else { return false }
        if currentText.isEmpty {
            return true
        }
        return trimmed.count > currentText.count && trimmed.hasPrefix(currentText)
    }

    @objc
    private func selectLanguage(_ sender: NSMenuItem) {
        guard
            let rawValue = sender.representedObject as? String,
            let language = SupportedLanguage(rawValue: rawValue)
        else {
            return
        }

        settings.selectedLanguage = language
        for (key, item) in languageMenuItems {
            item.state = key == language ? .on : .off
        }
    }

    @objc
    private func toggleLLM() {
        settings.textRefinementEnabled.toggle()
        textRefinementMenuItem?.state = settings.textRefinementEnabled ? .on : .off
    }

    @objc
    private func openSettings() {
        settingsWindowController.show()
    }

    @objc
    private func quit() {
        NSApp.terminate(nil)
    }
}
