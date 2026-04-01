import AppKit
import Foundation

@MainActor
final class AppController: NSObject {
    private let settings = AppSettings()
    private let permissionCoordinator = PermissionCoordinator()
    private let fnKeyMonitor = FnKeyMonitor()
    private let audioCaptureService = AudioCaptureService()
    private let speechService = SpeechTranscriptionService()
    private let overlayController = OverlayPanelController()
    private let textInjectionService = TextInjectionService()
    private let llmRefinementService = LLMRefinementService()

    private lazy var settingsWindowController = SettingsWindowController(settings: settings, llmService: llmRefinementService)

    private var statusItem: NSStatusItem?
    private var languageMenuItems: [SupportedLanguage: NSMenuItem] = [:]
    private var llmEnabledMenuItem: NSMenuItem?
    private var currentPhase: OverlayPhase = .idle
    private var currentText = ""
    private var smoothedRMS: Float = 0

    func start() {
        permissionCoordinator.requestStartupPermissions()
        configureStatusItem()
        configureFnMonitoring()
        permissionCoordinator.promptForAccessibilityIfNeeded()
    }

    func stop() {
        fnKeyMonitor.stop()
        audioCaptureService.stop()
        speechService.cancel()
    }

    private func configureStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.button?.title = "Voily"
        item.menu = makeMenu()
        statusItem = item
    }

    private func makeMenu() -> NSMenu {
        let menu = NSMenu()

        let languageItem = NSMenuItem(title: "Language", action: nil, keyEquivalent: "")
        languageItem.submenu = makeLanguageMenu()
        menu.addItem(languageItem)

        let llmItem = NSMenuItem(title: "LLM Refinement", action: nil, keyEquivalent: "")
        llmItem.submenu = makeLLMMenu()
        menu.addItem(llmItem)

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

    private func makeLLMMenu() -> NSMenu {
        let menu = NSMenu()

        let toggle = NSMenuItem(title: "Enable Refinement", action: #selector(toggleLLM), keyEquivalent: "")
        toggle.target = self
        toggle.state = settings.llmEnabled ? .on : .off
        llmEnabledMenuItem = toggle
        menu.addItem(toggle)

        let settingsItem = NSMenuItem(title: "Settings…", action: #selector(openSettings), keyEquivalent: "")
        settingsItem.target = self
        menu.addItem(settingsItem)

        return menu
    }

    private func configureFnMonitoring() {
        fnKeyMonitor.onPress = { [weak self] in
            Task { @MainActor in
                await self?.beginRecording()
            }
        }

        fnKeyMonitor.onRelease = { [weak self] in
            Task { @MainActor in
                await self?.finishRecording()
            }
        }

        fnKeyMonitor.start()
    }

    private func setOverlay(text: String, rmsLevel: Float, phase: OverlayPhase) {
        currentText = text
        currentPhase = phase
        overlayController.show(state: OverlayState(text: text, rmsLevel: rmsLevel, phase: phase))
    }

    private func updateRMS(_ newLevel: Float) {
        let attack: Float = 0.40
        let release: Float = 0.15
        let coefficient = newLevel > smoothedRMS ? attack : release
        smoothedRMS = smoothedRMS + ((newLevel - smoothedRMS) * coefficient)

        if currentPhase == .recording || currentPhase == .transcribing {
            overlayController.show(state: OverlayState(text: currentText, rmsLevel: smoothedRMS, phase: currentPhase))
        }
    }

    private func beginRecording() async {
        guard currentPhase == .idle else { return }
        currentText = ""
        smoothedRMS = 0
        setOverlay(text: "", rmsLevel: 0, phase: .recording)

        do {
            try speechService.start(localeIdentifier: settings.selectedLanguageCode) { [weak self] text in
                guard let self else { return }
                self.currentText = text
                self.currentPhase = .recording
                self.overlayController.show(state: OverlayState(text: text, rmsLevel: self.smoothedRMS, phase: .recording))
            }

            try audioCaptureService.start { [weak self] buffer in
                Task { @MainActor in
                    self?.speechService.append(buffer)
                }
            } onLevel: { [weak self] level in
                Task { @MainActor in
                    self?.updateRMS(level)
                }
            }
        } catch {
            NSLog("Recording start failed: \(error.localizedDescription)")
            overlayController.hide()
            currentPhase = .idle
        }
    }

    private func finishRecording() async {
        guard currentPhase == .recording else { return }

        currentPhase = .transcribing
        overlayController.show(state: OverlayState(text: currentText, rmsLevel: smoothedRMS, phase: .transcribing))
        audioCaptureService.stop()

        let recognizedText = await speechService.finish().trimmingCharacters(in: .whitespacesAndNewlines)
        currentText = recognizedText

        guard !recognizedText.isEmpty else {
            overlayController.hide()
            currentPhase = .idle
            return
        }

        let finalText: String
        if settings.llmEnabled && settings.isLLMConfigured {
            currentPhase = .refining
            overlayController.show(state: OverlayState(text: recognizedText, rmsLevel: 0, phase: .refining))

            do {
                finalText = try await llmRefinementService.refine(
                    RefinementRequest(text: recognizedText, languageCode: settings.selectedLanguageCode),
                    settings: settings
                )
            } catch {
                NSLog("LLM refinement failed: \(error.localizedDescription)")
                finalText = recognizedText
            }
        } else {
            finalText = recognizedText
        }

        currentPhase = .injecting
        overlayController.show(state: OverlayState(text: finalText, rmsLevel: 0, phase: .injecting))
        let injectionResult = await textInjectionService.inject(text: finalText)
        if injectionResult != .success {
            NSLog("Text injection finished with result: \(String(describing: injectionResult))")
        }

        try? await Task.sleep(for: .milliseconds(150))
        overlayController.hide()
        currentPhase = .idle
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
        settings.llmEnabled.toggle()
        llmEnabledMenuItem?.state = settings.llmEnabled ? .on : .off
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
