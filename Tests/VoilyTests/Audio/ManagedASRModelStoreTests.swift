import XCTest
@testable import Voily
@testable import VoilyCore

private actor CacheClearRecorder {
    private(set) var callCount = 0

    func record() {
        callCount += 1
    }
}

@MainActor
final class ManagedASRModelStoreTests: XCTestCase {
    private var temporaryRoot: URL!

    override func setUpWithError() throws {
        try super.setUpWithError()
        temporaryRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("VoilyModelStoreTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: temporaryRoot, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        if let temporaryRoot {
            try? FileManager.default.removeItem(at: temporaryRoot)
        }
        temporaryRoot = nil
        try super.tearDownWithError()
    }

    func testReportsRuntimeUnavailableBeforeCheckingModelCache() {
        let store = makeStore(runtimeAvailable: false)

        guard case let .runtimeUnavailable(message) = store.state(for: .senseVoice) else {
            return XCTFail("expected runtime unavailable state")
        }

        XCTAssertTrue(message.contains("SenseVoice"))
    }

    func testReportsNotInstalledWhenRuntimeExistsAndModelCacheIsMissing() {
        let store = makeStore()

        XCTAssertEqual(store.state(for: .senseVoice), .notInstalled)
    }

    func testImportModelCopiesValidatedFilesIntoCache() async throws {
        let sourceRoot = temporaryRoot.appendingPathComponent("DownloadedModel", isDirectory: true)
        try writeModelFiles(at: sourceRoot)
        let store = makeStore()

        store.importModel(provider: .senseVoice, from: sourceRoot)
        await waitUntilIdle(store)

        XCTAssertEqual(store.state(for: .senseVoice), .installed)
        XCTAssertTrue(FileManager.default.fileExists(atPath: cachedModelRoot().appendingPathComponent("model.safetensors").path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: cachedModelRoot().appendingPathComponent("config.json").path))
    }

    func testImportModelFailsWhenRequiredFilesAreMissing() async throws {
        let sourceRoot = temporaryRoot.appendingPathComponent("IncompleteModel", isDirectory: true)
        try writeModelFiles(at: sourceRoot, omittedFiles: ["config.json"])
        let store = makeStore()

        store.importModel(provider: .senseVoice, from: sourceRoot)
        await waitUntilIdle(store)

        guard case let .failed(message) = store.state(for: .senseVoice) else {
            return XCTFail("expected failed state")
        }

        XCTAssertTrue(message.contains("config.json"))
    }

    func testDownloadModelCopiesFilesFromSelectedSourceIntoCache() async throws {
        let sourceRoot = temporaryRoot.appendingPathComponent("RemoteModel", isDirectory: true)
        try writeModelFiles(at: sourceRoot)
        let store = makeStore()

        store.downloadModel(provider: .senseVoice, from: makeSource(id: "local-fixture", root: sourceRoot))
        await waitUntilIdle(store)

        XCTAssertEqual(store.state(for: .senseVoice), .installed)
        XCTAssertTrue(FileManager.default.fileExists(atPath: cachedModelRoot().appendingPathComponent("model.safetensors").path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: cachedModelRoot().appendingPathComponent("config.json").path))
    }

    func testDownloadModelFailsWhenSourceHasNoDownloadFiles() async {
        let store = makeStore()
        let source = ManagedASRModelSource(
            id: "empty",
            displayName: "Empty",
            subtitle: "",
            downloadFiles: [],
            isRecommended: false
        )

        store.downloadModel(provider: .senseVoice, from: source)

        guard case let .failed(message) = store.state(for: .senseVoice) else {
            return XCTFail("expected failed state")
        }

        XCTAssertTrue(message.contains("Empty"))
    }

    func testBuiltInDownloadSourcesExposeExpectedByteCountsForProgress() {
        let store = makeStore()

        for source in store.modelSources(for: .senseVoice) {
            let totalByteCount = source.downloadFiles.reduce(Int64(0)) { partialResult, file in
                partialResult + (file.expectedByteCount ?? 0)
            }

            XCTAssertTrue(source.downloadFiles.allSatisfy { $0.expectedByteCount != nil })
            XCTAssertGreaterThan(totalByteCount, 936_000_000)
        }
    }

    func testClearModelCacheCallsStopHookAndPreservesRuntimeDirectory() async throws {
        let sourceRoot = temporaryRoot.appendingPathComponent("DownloadedModel", isDirectory: true)
        try writeModelFiles(at: sourceRoot)
        let runtimeRoot = temporaryRoot
            .appendingPathComponent("LocalModels", isDirectory: true)
            .appendingPathComponent(ASRProvider.senseVoice.rawValue, isDirectory: true)
            .appendingPathComponent("runtime", isDirectory: true)
        try FileManager.default.createDirectory(at: runtimeRoot, withIntermediateDirectories: true)

        let recorder = CacheClearRecorder()
        let store = makeStore(beforeClearingModelCache: {
            await recorder.record()
        })
        store.importModel(provider: .senseVoice, from: sourceRoot)
        await waitUntilIdle(store)
        XCTAssertEqual(store.state(for: .senseVoice), .installed)

        store.clearModelCache(provider: .senseVoice)
        await waitUntilIdle(store)

        let callCount = await recorder.callCount
        XCTAssertEqual(callCount, 1)
        XCTAssertEqual(store.state(for: .senseVoice), .notInstalled)
        XCTAssertFalse(FileManager.default.fileExists(atPath: cachedModelRoot().path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: runtimeRoot.path))
    }

    private func makeStore(
        runtimeAvailable: Bool = true,
        beforeClearingModelCache: (() async -> Void)? = nil
    ) -> ManagedASRModelStore {
        ManagedASRModelStore(
            applicationSupportRoot: temporaryRoot,
            runtimeAvailability: { runtimeAvailable },
            beforeClearingModelCache: beforeClearingModelCache,
            modelSpecs: [
                .senseVoice: ManagedASRModelSpec(
                    provider: .senseVoice,
                    modelFiles: [
                        ManagedASRModelFile(relativePath: "model.safetensors", minimumByteCount: 4),
                        ManagedASRModelFile(relativePath: "config.json", minimumByteCount: 2),
                        ManagedASRModelFile(relativePath: "am.mvn", minimumByteCount: 4),
                        ManagedASRModelFile(relativePath: "chn_jpn_yue_eng_ko_spectok.bpe.model", minimumByteCount: 4),
                    ],
                    estimatedDownload: "4 KB"
                ),
            ]
        )
    }

    private func writeModelFiles(at root: URL, omittedFiles: Set<String> = []) throws {
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let contents: [String: String] = [
            "model.safetensors": "model-bytes",
            "config.json": "{}",
            "am.mvn": "mvn-bytes",
            "chn_jpn_yue_eng_ko_spectok.bpe.model": "bpe-bytes",
        ]

        for (relativePath, content) in contents where !omittedFiles.contains(relativePath) {
            try content.data(using: .utf8)?.write(to: root.appendingPathComponent(relativePath))
        }
    }

    private func makeSource(id: String, root: URL) -> ManagedASRModelSource {
        ManagedASRModelSource(
            id: id,
            displayName: "Local Fixture",
            subtitle: "",
            downloadFiles: [
                "model.safetensors",
                "config.json",
                "am.mvn",
                "chn_jpn_yue_eng_ko_spectok.bpe.model",
            ].map { relativePath in
                ManagedASRModelDownloadFile(relativePath: relativePath, url: root.appendingPathComponent(relativePath))
            },
            isRecommended: true
        )
    }

    private func cachedModelRoot() -> URL {
        temporaryRoot
            .appendingPathComponent("LocalModels", isDirectory: true)
            .appendingPathComponent(ASRProvider.senseVoice.rawValue, isDirectory: true)
            .appendingPathComponent("model", isDirectory: true)
    }

    private func waitUntilIdle(_ store: ManagedASRModelStore) async {
        for _ in 0..<100 {
            if !store.state(for: .senseVoice).isBusy {
                return
            }
            try? await Task.sleep(for: .milliseconds(10))
        }
    }
}
