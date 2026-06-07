import Foundation
import Observation
import VoilyCore

enum ManagedASRInstallState: Equatable {
    case runtimeUnavailable(String)
    case notInstalled
    case downloading(ManagedASRDownloadProgress)
    case validating(String)
    case installed
    case incomplete(String)
    case failed(String)

    var isInstalled: Bool {
        if case .installed = self {
            return true
        }
        return false
    }

    var isBusy: Bool {
        if case .downloading = self {
            return true
        }
        if case .validating = self {
            return true
        }
        return false
    }

    var statusText: String {
        switch self {
        case let .runtimeUnavailable(message):
            return message
        case .notInstalled:
            return AppLocalization.localized("未导入")
        case let .downloading(progress):
            return progress.message
        case let .validating(message):
            return message
        case .installed:
            return AppLocalization.localized("可用")
        case let .incomplete(message):
            return message
        case let .failed(message):
            return message
        }
    }

    var downloadProgress: ManagedASRDownloadProgress? {
        if case let .downloading(progress) = self {
            return progress
        }
        return nil
    }
}

struct ManagedASRDownloadProgress: Equatable, Sendable {
    let message: String
    let completedBytes: Int64
    let totalBytes: Int64?

    var fractionCompleted: Double? {
        guard let totalBytes, totalBytes > 0 else { return nil }
        return min(max(Double(completedBytes) / Double(totalBytes), 0), 1)
    }

    var byteCountText: String? {
        guard let totalBytes, totalBytes > 0 else { return nil }
        let completedText = ByteCountFormatter.string(fromByteCount: min(completedBytes, totalBytes), countStyle: .file)
        let totalText = ByteCountFormatter.string(fromByteCount: totalBytes, countStyle: .file)
        return String(format: AppLocalization.localized("%@ / %@"), completedText, totalText)
    }
}

struct ManagedASRModelDownloadFile: Equatable, Sendable {
    let relativePath: String
    let url: URL
    let expectedByteCount: Int64?

    init(relativePath: String, url: URL, expectedByteCount: Int64? = nil) {
        self.relativePath = relativePath
        self.url = url
        self.expectedByteCount = expectedByteCount
    }
}

struct ManagedASRModelSource: Identifiable, Equatable, Sendable {
    let id: String
    let displayName: String
    let subtitle: String
    let downloadFiles: [ManagedASRModelDownloadFile]
    let isRecommended: Bool

    var isDownloadAvailable: Bool {
        !downloadFiles.isEmpty
    }
}

struct ManagedASRModelFile: Equatable, Sendable {
    let relativePath: String
    let minimumByteCount: Int64
}

struct ManagedASRModelSpec: Sendable {
    let provider: ASRProvider
    let modelFiles: [ManagedASRModelFile]
    let estimatedDownload: String
}

@MainActor
@Observable
final class ManagedASRModelStore {
    private(set) var states: [ASRProvider: ManagedASRInstallState] = [:]

    private let applicationSupportRoot: URL
    private let runtimeAvailability: () -> Bool
    private let beforeClearingModelCache: (() async -> Void)?
    private let modelSpecs: [ASRProvider: ManagedASRModelSpec]
    private var cacheTasks: [ASRProvider: Task<Void, Never>] = [:]
    private var cacheOperationIDs: [ASRProvider: UUID] = [:]

    convenience init() {
        self.init(
            applicationSupportRoot: nil,
            runtimeAvailability: { true },
            beforeClearingModelCache: nil,
            modelSpecs: nil
        )
    }

    init(
        applicationSupportRoot: URL?,
        runtimeAvailability: @escaping () -> Bool,
        beforeClearingModelCache: (() async -> Void)?,
        modelSpecs: [ASRProvider: ManagedASRModelSpec]?
    ) {
        let baseURL = applicationSupportRoot ?? FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)
            .first!
            .appending(path: "Voily")
        self.applicationSupportRoot = baseURL
        self.runtimeAvailability = runtimeAvailability
        self.beforeClearingModelCache = beforeClearingModelCache
        self.modelSpecs = modelSpecs ?? Self.defaultSpecs
        removeLegacyWhisperInstallIfNeeded()
        refreshStates()
    }

    func state(for provider: ASRProvider) -> ManagedASRInstallState {
        states[provider] ?? .notInstalled
    }

    func refresh(provider: ASRProvider) {
        guard provider.category == .local else { return }
        states[provider] = refreshedState(for: provider)
    }

    func importModel(provider: ASRProvider, from sourceDirectory: URL) {
        guard provider.category == .local, let spec = modelSpecs[provider] else { return }
        guard cacheTasks[provider] == nil else { return }

        let operationID = UUID()
        cacheOperationIDs[provider] = operationID
        states[provider] = .validating(AppLocalization.localized("正在校验模型文件..."))
        let destinationModelRoot = modelRoot(for: provider)
        let task = Task { [weak self] in
            do {
                try await Task.detached(priority: .userInitiated) {
                    try Self.importModelFiles(
                        spec: spec,
                        sourceDirectory: sourceDirectory,
                        destinationModelRoot: destinationModelRoot
                    )
                }.value
                self?.finishCacheTask(provider: provider, operationID: operationID)
            } catch {
                self?.failCacheTask(provider: provider, operationID: operationID, error: error)
            }
        }
        cacheTasks[provider] = task
    }

    func downloadModel(provider: ASRProvider, from source: ManagedASRModelSource) {
        guard provider.category == .local, let spec = modelSpecs[provider] else { return }
        guard cacheTasks[provider] == nil else { return }
        guard source.isDownloadAvailable else {
            states[provider] = .failed(
                String(
                    format: AppLocalization.localized("%@ 暂无可用的一键下载地址。"),
                    source.displayName
                )
            )
            return
        }

        let operationID = UUID()
        cacheOperationIDs[provider] = operationID
        let totalExpectedBytes = Self.totalExpectedDownloadBytes(spec: spec, source: source)
        states[provider] = .downloading(
            ManagedASRDownloadProgress(
                message: String(
                    format: AppLocalization.localized("正在准备从 %@ 下载..."),
                    source.displayName
                ),
                completedBytes: 0,
                totalBytes: totalExpectedBytes
            )
        )
        let destinationModelRoot = modelRoot(for: provider)
        let task = Task { [weak self] in
            do {
                try await Self.downloadModelFiles(
                    spec: spec,
                    source: source,
                    destinationModelRoot: destinationModelRoot,
                    progress: { progress in
                        await MainActor.run {
                            guard self?.cacheOperationIDs[provider] == operationID else { return }
                            self?.states[provider] = .downloading(progress)
                        }
                    }
                )
                await MainActor.run {
                    self?.finishCacheTask(provider: provider, operationID: operationID)
                }
            } catch {
                await MainActor.run {
                    self?.failCacheTask(provider: provider, operationID: operationID, error: error)
                }
            }
        }
        cacheTasks[provider] = task
    }

    func clearModelCache(provider: ASRProvider) {
        guard provider.category == .local else { return }
        guard cacheTasks[provider] == nil else { return }

        let operationID = UUID()
        cacheOperationIDs[provider] = operationID
        states[provider] = .validating(AppLocalization.localized("正在清除模型缓存..."))
        let modelRoot = modelRoot(for: provider)
        let manifestURL = modelCacheRoot(for: provider).appending(path: "model-manifest.json")
        let beforeClearingModelCache = beforeClearingModelCache
        let task = Task { [weak self] in
            await beforeClearingModelCache?()
            do {
                try await Task.detached(priority: .userInitiated) {
                    try? FileManager.default.removeItem(at: manifestURL)
                    if FileManager.default.fileExists(atPath: modelRoot.path) {
                        try FileManager.default.removeItem(at: modelRoot)
                    }
                }.value
                self?.finishCacheTask(provider: provider, operationID: operationID)
            } catch {
                self?.failCacheTask(provider: provider, operationID: operationID, error: error)
            }
        }
        cacheTasks[provider] = task
    }

    func modelSources(for provider: ASRProvider) -> [ManagedASRModelSource] {
        guard provider == .senseVoice else { return [] }
        let recommendsModelScope = TimeZone.autoupdatingCurrent.secondsFromGMT() == 8 * 60 * 60

        return [
            ManagedASRModelSource(
                id: "modelscope",
                displayName: "ModelScope",
                subtitle: AppLocalization.localized("大陆访问更稳定；下载 mlx-community/SenseVoiceSmall 的 MLX 文件集。"),
                downloadFiles: Self.modelScopeSenseVoiceFiles,
                isRecommended: recommendsModelScope
            ),
            ManagedASRModelSource(
                id: "huggingface",
                displayName: "Hugging Face",
                subtitle: AppLocalization.localized("直接下载 mlx-community/SenseVoiceSmall 的 MLX 文件集。"),
                downloadFiles: Self.huggingFaceSenseVoiceFiles,
                isRecommended: !recommendsModelScope
            ),
        ]
    }

    func estimatedDownload(for provider: ASRProvider) -> String {
        modelSpecs[provider]?.estimatedDownload ?? ""
    }

    func hasModelCache(for provider: ASRProvider) -> Bool {
        FileManager.default.fileExists(atPath: modelRoot(for: provider).path)
    }

    func modelCacheSizeDescription(for provider: ASRProvider) -> String {
        let byteCount = Self.directoryByteCount(at: modelRoot(for: provider))
        guard byteCount > 0 else {
            return AppLocalization.localized("无缓存")
        }
        return ByteCountFormatter.string(fromByteCount: byteCount, countStyle: .file)
    }

    private func finishCacheTask(provider: ASRProvider, operationID: UUID) {
        guard cacheOperationIDs[provider] == operationID else { return }
        cacheTasks[provider] = nil
        cacheOperationIDs[provider] = nil
        states[provider] = refreshedState(for: provider)
    }

    private func failCacheTask(provider: ASRProvider, operationID: UUID, error: Error) {
        guard cacheOperationIDs[provider] == operationID else { return }
        cacheTasks[provider] = nil
        cacheOperationIDs[provider] = nil
        debugLog("Managed local model cache failed provider=\(provider.rawValue) error=\(error.localizedDescription)")
        states[provider] = .failed(error.localizedDescription)
    }

    private func refreshStates() {
        for provider in ASRProvider.allCases where provider.category == .local {
            states[provider] = refreshedState(for: provider)
        }
    }

    private func refreshedState(for provider: ASRProvider) -> ManagedASRInstallState {
        guard let spec = modelSpecs[provider] else { return .notInstalled }

        guard runtimeAvailability() else {
            return .runtimeUnavailable(AppLocalization.localized("当前 SenseVoice 本地运行时不可用。"))
        }

        let modelRoot = modelRoot(for: provider)
        guard FileManager.default.fileExists(atPath: modelRoot.path) else {
            return .notInstalled
        }

        do {
            try Self.validate(modelRoot: modelRoot, spec: spec)
            return .installed
        } catch {
            return .incomplete(error.localizedDescription)
        }
    }

    private func modelCacheRoot(for provider: ASRProvider) -> URL {
        modelCacheRoot(rawValue: provider.rawValue)
    }

    private func modelRoot(for provider: ASRProvider) -> URL {
        modelCacheRoot(for: provider).appending(path: "model")
    }

    private func modelCacheRoot(rawValue: String) -> URL {
        applicationSupportRoot
            .appending(path: "LocalModels")
            .appending(path: rawValue)
    }

    private func removeLegacyWhisperInstallIfNeeded() {
        let legacyInstallRoot = modelCacheRoot(rawValue: "whisperCpp")
        guard FileManager.default.fileExists(atPath: legacyInstallRoot.path) else {
            return
        }
        try? FileManager.default.removeItem(at: legacyInstallRoot)
    }

    nonisolated private static let defaultSpecs: [ASRProvider: ManagedASRModelSpec] = [
        .senseVoice: ManagedASRModelSpec(
            provider: .senseVoice,
            modelFiles: [
                ManagedASRModelFile(relativePath: "model.safetensors", minimumByteCount: 900_000_000),
                ManagedASRModelFile(relativePath: "config.json", minimumByteCount: 100),
                ManagedASRModelFile(relativePath: "am.mvn", minimumByteCount: 1_000),
                ManagedASRModelFile(relativePath: "chn_jpn_yue_eng_ko_spectok.bpe.model", minimumByteCount: 100_000),
            ],
            estimatedDownload: AppLocalization.localized("约 950 MB")
        ),
    ]

    nonisolated private static let huggingFaceSenseVoiceFiles: [ManagedASRModelDownloadFile] = {
        let baseURL = URL(string: "https://huggingface.co/mlx-community/SenseVoiceSmall/resolve/main/")!
        return senseVoiceDownloadFiles.map { file in
            ManagedASRModelDownloadFile(
                relativePath: file.relativePath,
                url: baseURL.appending(path: file.relativePath),
                expectedByteCount: file.expectedByteCount
            )
        }
    }()

    nonisolated private static let modelScopeSenseVoiceFiles: [ManagedASRModelDownloadFile] = {
        let baseURL = URL(string: "https://modelscope.cn/models/mlx-community/SenseVoiceSmall/resolve/master/")!
        return senseVoiceDownloadFiles.map { file in
            ManagedASRModelDownloadFile(
                relativePath: file.relativePath,
                url: baseURL.appending(path: file.relativePath),
                expectedByteCount: file.expectedByteCount
            )
        }
    }()

    nonisolated private static let senseVoiceDownloadFiles: [(relativePath: String, expectedByteCount: Int64)] = [
        ("model.safetensors", 936_100_124),
        ("config.json", 517),
        ("am.mvn", 11_203),
        ("chn_jpn_yue_eng_ko_spectok.bpe.model", 377_341),
    ]

    nonisolated private static func importModelFiles(
        spec: ManagedASRModelSpec,
        sourceDirectory: URL,
        destinationModelRoot: URL
    ) throws {
        let sourceModelRoot = try resolvedSourceModelRoot(in: sourceDirectory, spec: spec)
        try validate(modelRoot: sourceModelRoot, spec: spec)

        if sourceModelRoot.standardizedFileURL == destinationModelRoot.standardizedFileURL {
            return
        }

        let fileManager = FileManager.default
        let cacheRoot = destinationModelRoot.deletingLastPathComponent()
        let stagingRoot = cacheRoot.appending(path: ".model-staging-\(UUID().uuidString)")
        let stagingModelRoot = stagingRoot.appending(path: "model")
        let backupRoot = cacheRoot.appending(path: ".model-backup-\(UUID().uuidString)")

        do {
            try fileManager.createDirectory(at: stagingModelRoot, withIntermediateDirectories: true)
            for modelFile in spec.modelFiles {
                let sourceURL = sourceModelRoot.appending(path: modelFile.relativePath)
                let destinationURL = stagingModelRoot.appending(path: modelFile.relativePath)
                try fileManager.createDirectory(at: destinationURL.deletingLastPathComponent(), withIntermediateDirectories: true)
                try fileManager.copyItem(at: sourceURL, to: destinationURL)
            }

            try validate(modelRoot: stagingModelRoot, spec: spec)
            try fileManager.createDirectory(at: cacheRoot, withIntermediateDirectories: true)

            if fileManager.fileExists(atPath: destinationModelRoot.path) {
                try fileManager.moveItem(at: destinationModelRoot, to: backupRoot)
            }

            do {
                try fileManager.moveItem(at: stagingModelRoot, to: destinationModelRoot)
            } catch {
                if fileManager.fileExists(atPath: backupRoot.path) {
                    try? fileManager.moveItem(at: backupRoot, to: destinationModelRoot)
                }
                throw error
            }

            try? fileManager.removeItem(at: backupRoot)
            try? fileManager.removeItem(at: stagingRoot)
        } catch {
            try? fileManager.removeItem(at: stagingRoot)
            throw error
        }
    }

    nonisolated private static func downloadModelFiles(
        spec: ManagedASRModelSpec,
        source: ManagedASRModelSource,
        destinationModelRoot: URL,
        progress: @escaping @Sendable (ManagedASRDownloadProgress) async -> Void
    ) async throws {
        let fileDownloads = Dictionary(uniqueKeysWithValues: source.downloadFiles.map { ($0.relativePath, $0.url) })
        let downloadFilesByPath = Dictionary(uniqueKeysWithValues: source.downloadFiles.map { ($0.relativePath, $0) })
        let missingDownloadURLs = spec.modelFiles.compactMap { modelFile in
            fileDownloads[modelFile.relativePath] == nil ? modelFile.relativePath : nil
        }
        if !missingDownloadURLs.isEmpty {
            throw ManagedASRModelError.missingDownloadURLs(missingDownloadURLs)
        }

        let fileManager = FileManager.default
        let cacheRoot = destinationModelRoot.deletingLastPathComponent()
        let stagingRoot = cacheRoot.appending(path: ".model-download-\(UUID().uuidString)")
        let stagingModelRoot = stagingRoot.appending(path: "model")
        let backupRoot = cacheRoot.appending(path: ".model-backup-\(UUID().uuidString)")
        let totalExpectedBytes = totalExpectedDownloadBytes(spec: spec, source: source)
        var completedBytes: Int64 = 0

        do {
            try fileManager.createDirectory(at: stagingModelRoot, withIntermediateDirectories: true)
            for modelFile in spec.modelFiles {
                guard let sourceURL = fileDownloads[modelFile.relativePath] else {
                    throw ManagedASRModelError.missingDownloadURLs([modelFile.relativePath])
                }
                let completedBeforeFile = completedBytes
                let fileProgressMessage = String(
                    format: AppLocalization.localized("正在下载 %@..."),
                    modelFile.relativePath
                )
                await progress(
                    ManagedASRDownloadProgress(
                        message: fileProgressMessage,
                        completedBytes: completedBeforeFile,
                        totalBytes: totalExpectedBytes
                    )
                )
                let destinationURL = stagingModelRoot.appending(path: modelFile.relativePath)
                try fileManager.createDirectory(at: destinationURL.deletingLastPathComponent(), withIntermediateDirectories: true)
                try await downloadFile(from: sourceURL, to: destinationURL) { fileCompletedBytes, fileExpectedByteCount in
                    let currentTotalBytes = totalExpectedBytes ?? fileExpectedByteCount.map { completedBeforeFile + $0 }
                    await progress(
                        ManagedASRDownloadProgress(
                            message: fileProgressMessage,
                            completedBytes: completedBeforeFile + fileCompletedBytes,
                            totalBytes: currentTotalBytes
                        )
                    )
                }
                let downloadedByteCount = fileByteCount(at: destinationURL)
                let expectedByteCount = downloadFilesByPath[modelFile.relativePath]?.expectedByteCount
                completedBytes += max(downloadedByteCount, expectedByteCount ?? 0)
            }

            await progress(
                ManagedASRDownloadProgress(
                    message: AppLocalization.localized("正在安装模型文件..."),
                    completedBytes: totalExpectedBytes ?? completedBytes,
                    totalBytes: totalExpectedBytes ?? max(completedBytes, 1)
                )
            )
            try validate(modelRoot: stagingModelRoot, spec: spec)
            try fileManager.createDirectory(at: cacheRoot, withIntermediateDirectories: true)

            if fileManager.fileExists(atPath: destinationModelRoot.path) {
                try fileManager.moveItem(at: destinationModelRoot, to: backupRoot)
            }

            do {
                try fileManager.moveItem(at: stagingModelRoot, to: destinationModelRoot)
            } catch {
                if fileManager.fileExists(atPath: backupRoot.path) {
                    try? fileManager.moveItem(at: backupRoot, to: destinationModelRoot)
                }
                throw error
            }

            try? fileManager.removeItem(at: backupRoot)
            try? fileManager.removeItem(at: stagingRoot)
        } catch {
            try? fileManager.removeItem(at: stagingRoot)
            throw error
        }
    }

    nonisolated private static func downloadFile(
        from sourceURL: URL,
        to destinationURL: URL,
        progress: @escaping @Sendable (Int64, Int64?) async -> Void
    ) async throws {
        let fileManager = FileManager.default
        if sourceURL.isFileURL {
            let byteCount = fileByteCount(at: sourceURL)
            await progress(0, byteCount > 0 ? byteCount : nil)
            if fileManager.fileExists(atPath: destinationURL.path) {
                try fileManager.removeItem(at: destinationURL)
            }
            try fileManager.copyItem(at: sourceURL, to: destinationURL)
            await progress(byteCount, byteCount > 0 ? byteCount : nil)
            return
        }

        let temporaryURL = destinationURL.deletingLastPathComponent()
            .appending(path: ".download-\(UUID().uuidString)")
        let downloader = ManagedASRHTTPDownloader(
            temporaryURL: temporaryURL,
            progress: { completedBytes, expectedBytes in
                Task {
                    await progress(completedBytes, expectedBytes)
                }
            }
        )
        let (downloadedURL, response) = try await downloader.download(from: sourceURL)
        defer {
            try? fileManager.removeItem(at: downloadedURL)
        }
        guard let httpResponse = response as? HTTPURLResponse else {
            throw ManagedASRModelError.downloadFailed(sourceURL.lastPathComponent)
        }
        guard (200..<300).contains(httpResponse.statusCode) else {
            throw ManagedASRModelError.downloadFailed("\(sourceURL.lastPathComponent) (\(httpResponse.statusCode))")
        }

        if fileManager.fileExists(atPath: destinationURL.path) {
            try fileManager.removeItem(at: destinationURL)
        }
        try fileManager.copyItem(at: downloadedURL, to: destinationURL)
    }

    nonisolated private static func totalExpectedDownloadBytes(
        spec: ManagedASRModelSpec,
        source: ManagedASRModelSource
    ) -> Int64? {
        let downloadFilesByPath = Dictionary(uniqueKeysWithValues: source.downloadFiles.map { ($0.relativePath, $0) })
        var totalBytes: Int64 = 0
        for modelFile in spec.modelFiles {
            guard let expectedByteCount = downloadFilesByPath[modelFile.relativePath]?.expectedByteCount else {
                return nil
            }
            totalBytes += expectedByteCount
        }
        return totalBytes
    }

    nonisolated private static func resolvedSourceModelRoot(
        in sourceDirectory: URL,
        spec: ManagedASRModelSpec
    ) throws -> URL {
        let fileManager = FileManager.default
        var candidates = [
            sourceDirectory,
            sourceDirectory.appending(path: "model"),
        ]

        if let childURLs = try? fileManager.contentsOfDirectory(
            at: sourceDirectory,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) {
            for childURL in childURLs {
                guard (try? childURL.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true else {
                    continue
                }
                candidates.append(childURL)
                candidates.append(childURL.appending(path: "model"))
            }
        }

        for candidate in candidates {
            if containsAllRequiredFiles(at: candidate, spec: spec) {
                return candidate
            }
        }

        throw ManagedASRModelError.missingRequiredFiles(spec.modelFiles.map(\.relativePath))
    }

    nonisolated private static func containsAllRequiredFiles(at modelRoot: URL, spec: ManagedASRModelSpec) -> Bool {
        spec.modelFiles.allSatisfy { modelFile in
            FileManager.default.fileExists(atPath: modelRoot.appending(path: modelFile.relativePath).path)
        }
    }

    nonisolated private static func validate(modelRoot: URL, spec: ManagedASRModelSpec) throws {
        var missingFiles: [String] = []
        for modelFile in spec.modelFiles {
            let fileURL = modelRoot.appending(path: modelFile.relativePath)
            guard FileManager.default.fileExists(atPath: fileURL.path) else {
                missingFiles.append(modelFile.relativePath)
                continue
            }

            let attributes = try FileManager.default.attributesOfItem(atPath: fileURL.path)
            let byteCount = (attributes[.size] as? NSNumber)?.int64Value ?? 0
            guard byteCount >= modelFile.minimumByteCount else {
                throw ManagedASRModelError.modelFileTooSmall(modelFile.relativePath)
            }
        }

        if !missingFiles.isEmpty {
            throw ManagedASRModelError.missingRequiredFiles(missingFiles)
        }
    }

    nonisolated private static func directoryByteCount(at rootURL: URL) -> Int64 {
        guard let enumerator = FileManager.default.enumerator(
            at: rootURL,
            includingPropertiesForKeys: [.fileSizeKey, .isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else {
            return 0
        }

        var byteCount: Int64 = 0
        for case let fileURL as URL in enumerator {
            guard let resourceValues = try? fileURL.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey]),
                  resourceValues.isRegularFile == true else {
                continue
            }
            byteCount += Int64(resourceValues.fileSize ?? 0)
        }
        return byteCount
    }

    nonisolated private static func fileByteCount(at fileURL: URL) -> Int64 {
        let attributes = try? FileManager.default.attributesOfItem(atPath: fileURL.path)
        return (attributes?[.size] as? NSNumber)?.int64Value ?? 0
    }
}

private final class ManagedASRHTTPDownloader: NSObject, URLSessionDownloadDelegate, @unchecked Sendable {
    private let temporaryURL: URL
    private let progress: @Sendable (Int64, Int64?) -> Void
    private var continuation: CheckedContinuation<(URL, URLResponse), Error>?
    private var session: URLSession?
    private var didResume = false

    init(
        temporaryURL: URL,
        progress: @escaping @Sendable (Int64, Int64?) -> Void
    ) {
        self.temporaryURL = temporaryURL
        self.progress = progress
    }

    func download(from sourceURL: URL) async throws -> (URL, URLResponse) {
        try await withCheckedThrowingContinuation { continuation in
            self.continuation = continuation
            let delegateQueue = OperationQueue()
            delegateQueue.maxConcurrentOperationCount = 1
            let session = URLSession(configuration: .ephemeral, delegate: self, delegateQueue: delegateQueue)
            self.session = session
            session.downloadTask(with: sourceURL).resume()
        }
    }

    func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didWriteData bytesWritten: Int64,
        totalBytesWritten: Int64,
        totalBytesExpectedToWrite: Int64
    ) {
        progress(totalBytesWritten, totalBytesExpectedToWrite > 0 ? totalBytesExpectedToWrite : nil)
    }

    func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didFinishDownloadingTo location: URL
    ) {
        do {
            if FileManager.default.fileExists(atPath: temporaryURL.path) {
                try FileManager.default.removeItem(at: temporaryURL)
            }
            try FileManager.default.copyItem(at: location, to: temporaryURL)
            resumeOnce(returning: (temporaryURL, downloadTask.response ?? URLResponse()))
        } catch {
            resumeOnce(throwing: error)
        }
    }

    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        didCompleteWithError error: Error?
    ) {
        if let error {
            resumeOnce(throwing: error)
        }
        session.finishTasksAndInvalidate()
        self.session = nil
    }

    private func resumeOnce(returning value: (URL, URLResponse)) {
        guard !didResume else { return }
        didResume = true
        continuation?.resume(returning: value)
        continuation = nil
    }

    private func resumeOnce(throwing error: Error) {
        guard !didResume else { return }
        didResume = true
        continuation?.resume(throwing: error)
        continuation = nil
    }
}

enum ManagedASRModelError: LocalizedError {
    case missingRequiredFiles([String])
    case missingDownloadURLs([String])
    case modelFileTooSmall(String)
    case downloadFailed(String)

    var errorDescription: String? {
        switch self {
        case let .missingRequiredFiles(files):
            return String(
                format: AppLocalization.localized("模型文件缺失：%@"),
                files.joined(separator: ", ")
            )
        case let .missingDownloadURLs(files):
            return String(
                format: AppLocalization.localized("模型源缺少下载地址：%@"),
                files.joined(separator: ", ")
            )
        case let .modelFileTooSmall(file):
            return String(
                format: AppLocalization.localized("模型文件不完整：%@"),
                file
            )
        case let .downloadFailed(file):
            return String(
                format: AppLocalization.localized("模型下载失败：%@"),
                file
            )
        }
    }
}
