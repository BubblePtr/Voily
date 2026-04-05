import Foundation
import Observation

enum ManagedASRInstallState: Equatable {
    case notInstalled
    case installing(String)
    case installed
    case failed(String)

    var isInstalled: Bool {
        if case .installed = self {
            return true
        }
        return false
    }

    var statusText: String {
        switch self {
        case .notInstalled:
            return "未下载"
        case let .installing(message):
            return message
        case .installed:
            return "已下载"
        case let .failed(message):
            return message
        }
    }
}

struct ManagedASRDownloadFile {
    let sourceURL: String
    let relativePath: String
}

struct ManagedASRInstallSpec {
    let provider: ASRProvider
    let runtimePackageURL: String?
    let runtimeArchiveName: String?
    let executableRelativePath: String?
    let modelFiles: [ManagedASRDownloadFile]
    let defaultArguments: String
    let estimatedDownload: String
}

@MainActor
@Observable
final class ManagedASRModelStore {
    private(set) var states: [ASRProvider: ManagedASRInstallState] = [:]
    private let fileManager: FileManager
    private var installTasks: [ASRProvider: Task<Void, Never>] = [:]

    init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
        refreshStates()
    }

    func state(for provider: ASRProvider) -> ManagedASRInstallState {
        states[provider] ?? .notInstalled
    }

    func install(provider: ASRProvider) {
        guard provider.category == .local else { return }
        guard installTasks[provider] == nil else { return }

        let task = Task { [weak self] in
            guard let self else { return }
            await self.performInstall(for: provider)
        }
        installTasks[provider] = task
    }

    func uninstall(provider: ASRProvider) {
        guard provider.category == .local else { return }
        installTasks[provider]?.cancel()
        installTasks[provider] = nil

        try? fileManager.removeItem(at: installRoot(for: provider))
        states[provider] = .notInstalled
    }

    func managedConfig(for provider: ASRProvider) -> ASRProviderConfig? {
        guard let spec = Self.spec(for: provider) else { return nil }
        guard let executableRelativePath = spec.executableRelativePath else { return nil }

        let executableURL = installRoot(for: provider).appending(path: executableRelativePath)
        let modelURL = installRoot(for: provider).appending(path: spec.modelFiles[0].relativePath)
        guard fileManager.fileExists(atPath: executableURL.path), fileManager.fileExists(atPath: modelURL.path) else {
            return nil
        }

        return ASRProviderConfig(
            executablePath: executableURL.path,
            modelPath: modelURL.path,
            additionalArguments: spec.defaultArguments,
            baseURL: "",
            apiKey: "",
            model: ""
        )
    }

    func estimatedDownload(for provider: ASRProvider) -> String {
        Self.spec(for: provider)?.estimatedDownload ?? ""
    }

    func modelDirectory(for provider: ASRProvider) -> URL? {
        guard let spec = Self.spec(for: provider), !spec.modelFiles.isEmpty else { return nil }
        return installRoot(for: provider).appending(path: "model")
    }

    func runtimeDirectory(for provider: ASRProvider) -> URL? {
        let runtimeDirectory = installRoot(for: provider).appending(path: "runtime")
        guard fileManager.fileExists(atPath: runtimeDirectory.path) else { return nil }
        return runtimeDirectory
    }

    private func refreshStates() {
        for provider in ASRProvider.allCases where provider.category == .local {
            states[provider] = isInstalled(provider: provider) ? .installed : .notInstalled
        }
    }

    private func isInstalled(provider: ASRProvider) -> Bool {
        guard let spec = Self.spec(for: provider) else { return false }
        let installRoot = installRoot(for: provider)

        if let executableRelativePath = spec.executableRelativePath {
            let executableURL = installRoot.appending(path: executableRelativePath)
            guard fileManager.fileExists(atPath: executableURL.path) else {
                return false
            }
        }

        for modelFile in spec.modelFiles {
            let fileURL = installRoot.appending(path: modelFile.relativePath)
            guard fileManager.fileExists(atPath: fileURL.path) else {
                return false
            }
        }

        return true
    }

    private func performInstall(for provider: ASRProvider) async {
        guard let spec = Self.spec(for: provider) else { return }

        do {
            try Task.checkCancellation()
            let installRoot = installRoot(for: provider)
            try? fileManager.removeItem(at: installRoot)
            try fileManager.createDirectory(at: installRoot, withIntermediateDirectories: true)

            if let runtimePackageURL = spec.runtimePackageURL, let runtimeArchiveName = spec.runtimeArchiveName {
                states[provider] = .installing("正在下载运行时...")
                let runtimeArchiveURL = installRoot.appending(path: runtimeArchiveName)
                try await Self.downloadFile(from: runtimePackageURL, to: runtimeArchiveURL)

                try Task.checkCancellation()
                states[provider] = .installing("正在安装运行时...")
                try await Self.extractArchive(at: runtimeArchiveURL, to: installRoot)
                try? fileManager.removeItem(at: runtimeArchiveURL)
            }

            for (index, modelFile) in spec.modelFiles.enumerated() {
                try Task.checkCancellation()
                let message = spec.modelFiles.count == 1
                    ? "正在下载模型..."
                    : "正在下载模型文件 \(index + 1)/\(spec.modelFiles.count)..."
                states[provider] = .installing(message)
                let destination = installRoot.appending(path: modelFile.relativePath)
                try fileManager.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
                try await Self.downloadFile(from: modelFile.sourceURL, to: destination)
            }

            guard isInstalled(provider: provider) else {
                throw ManagedASRModelError.installationIncomplete
            }

            states[provider] = .installed
        } catch is CancellationError {
            states[provider] = .notInstalled
        } catch {
            debugLog("Managed local model install failed provider=\(provider.rawValue) error=\(error.localizedDescription)")
            states[provider] = .failed(error.localizedDescription)
        }

        installTasks[provider] = nil
    }

    private func installRoot(for provider: ASRProvider) -> URL {
        let baseURL = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return baseURL
            .appending(path: "Voily")
            .appending(path: "LocalModels")
            .appending(path: provider.rawValue)
    }

    private static func spec(for provider: ASRProvider) -> ManagedASRInstallSpec? {
        switch provider {
        case .whisperCpp:
            return ManagedASRInstallSpec(
                provider: provider,
                runtimePackageURL: "https://downloads.voily.app/local-asr/whisper-cpp/macos-arm64/whisper-cpp-runtime.zip",
                runtimeArchiveName: "whisper-cpp-runtime.zip",
                executableRelativePath: "runtime/whisper-cli",
                modelFiles: [
                    ManagedASRDownloadFile(
                        sourceURL: "https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-base.bin?download=true",
                        relativePath: "model/ggml-base.bin"
                    )
                ],
                defaultArguments: "--no-timestamps",
                estimatedDownload: "约 150 MB"
            )
        case .senseVoice:
            return ManagedASRInstallSpec(
                provider: provider,
                runtimePackageURL: nil,
                runtimeArchiveName: nil,
                executableRelativePath: nil,
                modelFiles: [
                    ManagedASRDownloadFile(
                        sourceURL: "https://huggingface.co/mlx-community/SenseVoiceSmall/resolve/main/model.safetensors?download=true",
                        relativePath: "model/model.safetensors"
                    ),
                    ManagedASRDownloadFile(
                        sourceURL: "https://huggingface.co/mlx-community/SenseVoiceSmall/resolve/main/config.json?download=true",
                        relativePath: "model/config.json"
                    ),
                    ManagedASRDownloadFile(
                        sourceURL: "https://huggingface.co/mlx-community/SenseVoiceSmall/resolve/main/am.mvn?download=true",
                        relativePath: "model/am.mvn"
                    ),
                    ManagedASRDownloadFile(
                        sourceURL: "https://huggingface.co/mlx-community/SenseVoiceSmall/resolve/main/chn_jpn_yue_eng_ko_spectok.bpe.model?download=true",
                        relativePath: "model/chn_jpn_yue_eng_ko_spectok.bpe.model"
                    )
                ],
                defaultArguments: "",
                estimatedDownload: "约 950 MB"
            )
        case .doubaoStreaming, .qwenASR:
            return nil
        }
    }

    private static func extractArchive(at archiveURL: URL, to directoryURL: URL) async throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
        process.arguments = ["-x", "-k", archiveURL.path, directoryURL.path]
        process.currentDirectoryURL = directoryURL

        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        do {
            try process.run()
        } catch {
            throw ManagedASRModelError.commandFailed("解压运行时失败：\(error.localizedDescription)")
        }

        return try await withCheckedThrowingContinuation { continuation in
            process.terminationHandler = { process in
                let stderr = String(data: stderrPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
                let stdout = String(data: stdoutPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""

                if process.terminationStatus == 0 {
                    continuation.resume()
                } else {
                    let message = [stderr, stdout]
                        .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                        .first { !$0.isEmpty } ?? "解压运行时失败，退出码 \(process.terminationStatus)"
                    continuation.resume(throwing: ManagedASRModelError.commandFailed(message))
                }
            }
        }
    }

    private static func downloadFile(from source: String, to destination: URL) async throws {
        guard let url = URL(string: source) else {
            throw ManagedASRModelError.invalidDownloadURL
        }

        let (temporaryURL, response) = try await URLSession.shared.download(from: url)
        guard let httpResponse = response as? HTTPURLResponse, (200 ..< 300).contains(httpResponse.statusCode) else {
            throw ManagedASRModelError.commandFailed("模型下载失败。")
        }

        try? FileManager.default.removeItem(at: destination)
        try FileManager.default.moveItem(at: temporaryURL, to: destination)
    }
}

enum ManagedASRModelError: LocalizedError {
    case invalidDownloadURL
    case commandFailed(String)
    case installationIncomplete

    var errorDescription: String? {
        switch self {
        case .invalidDownloadURL:
            return "模型下载地址无效。"
        case let .commandFailed(message):
            return message
        case .installationIncomplete:
            return "模型安装完成，但关键文件缺失。"
        }
    }
}
