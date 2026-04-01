import AppKit
import SwiftUI

@MainActor
final class SettingsWindowController: NSWindowController {
    init(settings: AppSettings, llmService: LLMRefinementService) {
        let view = SettingsView(settings: settings, llmService: llmService)
        let hostingController = NSHostingController(rootView: view)
        let window = NSWindow(contentViewController: hostingController)
        window.title = "Voily Settings"
        window.setContentSize(NSSize(width: 520, height: 280))
        window.styleMask = [.titled, .closable, .miniaturizable]
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

private struct SettingsView: View {
    @Bindable var settings: AppSettings
    let llmService: LLMRefinementService

    @State private var draftBaseURL: String = ""
    @State private var draftAPIKey: String = ""
    @State private var draftModel: String = ""
    @State private var statusMessage: String = ""
    @State private var isTesting = false

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            formRow(title: "API Base URL", text: $draftBaseURL)
            formRow(title: "API Key", text: $draftAPIKey)
            formRow(title: "Model", text: $draftModel)

            HStack(spacing: 12) {
                Button("Test") {
                    testConnection()
                }
                .disabled(isTesting)

                Button("Save") {
                    save()
                }

                Text(statusMessage)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }

            Spacer()
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .onAppear {
            draftBaseURL = settings.llmBaseURL
            draftAPIKey = settings.llmAPIKey
            draftModel = settings.llmModel
        }
    }

    private func formRow(title: String, text: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.secondary)

            TextField("", text: text)
                .textFieldStyle(.roundedBorder)
        }
    }

    private func save() {
        settings.llmBaseURL = draftBaseURL
        settings.llmAPIKey = draftAPIKey
        settings.llmModel = draftModel
        statusMessage = "Saved"
    }

    private func testConnection() {
        save()
        statusMessage = "Testing..."
        isTesting = true

        Task {
            defer { isTesting = false }

            do {
                try await llmService.testConnection(settings: settings)
                statusMessage = "Connection OK"
            } catch {
                statusMessage = "Test failed: \(error.localizedDescription)"
            }
        }
    }
}
