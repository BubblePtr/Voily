import XCTest
import AVFoundation
@testable import Voily
@testable import VoilyCore

private enum TestCaptureSessionError: Error, Equatable {
    case expected
}

private actor SessionRecorder {
    private(set) var startCalls: [(sampleRate: Double, languageCode: String)] = []
    private(set) var appendCalls: [(sessionID: String, byteCount: Int)] = []
    private(set) var cancelCalls: [String] = []
    private(set) var startedConfigs: [ASRProviderConfig] = []
    private(set) var startedLanguages: [String] = []
    private(set) var persistedConfigs: [ASRProviderConfig] = []
    private(set) var qwenAppendByteCounts: [Int] = []
    private(set) var qwenCancelCount = 0
    private(set) var nativeTranscribeByteCounts: [Int] = []
    private(set) var nativePrepareCount = 0
    private(set) var nativePartials: [String] = []

    func recordStart(sampleRate: Double, languageCode: String) {
        startCalls.append((sampleRate, languageCode))
    }

    func recordAppend(sessionID: String, byteCount: Int) {
        appendCalls.append((sessionID, byteCount))
    }

    func recordCancel(sessionID: String) {
        cancelCalls.append(sessionID)
    }

    func recordStartedConfig(_ config: ASRProviderConfig, languageCode: String) {
        startedConfigs.append(config)
        startedLanguages.append(languageCode)
    }

    func recordPersistedConfig(_ config: ASRProviderConfig) {
        persistedConfigs.append(config)
    }

    func recordQwenAppend(byteCount: Int) {
        qwenAppendByteCounts.append(byteCount)
    }

    func recordQwenCancel() {
        qwenCancelCount += 1
    }

    func recordNativeTranscribe(byteCount: Int) {
        nativeTranscribeByteCounts.append(byteCount)
    }

    func recordNativePrepare() {
        nativePrepareCount += 1
    }

    func recordNativePartial(_ text: String) -> Int {
        nativePartials.append(text)
        return nativePartials.count
    }
}

@MainActor
final class ASRCaptureSessionTests: XCTestCase {
    func testSenseVoiceSessionStartsResidentSessionOnFirstAppendAndReusesIt() async throws {
        let recorder = SessionRecorder()
        let session = SenseVoiceCaptureSession(
            languageCode: "zh-Hans",
            startResidentSession: { sampleRate, languageCode in
                await recorder.recordStart(sampleRate: sampleRate, languageCode: languageCode)
                return SenseVoiceResidentSession(id: "resident-session", language: languageCode, sampleRate: sampleRate)
            },
            appendAudio: { sessionID, pcmData in
                await recorder.recordAppend(sessionID: sessionID, byteCount: pcmData.count)
            },
            finalizeSession: { _ in
                LocalASRTranscriptionResult(
                    text: "你好世界",
                    duration: 0.4,
                    commandSummary: "sensevoice finalize"
                )
            },
            cancelResidentSession: { residentSession in
                await recorder.recordCancel(sessionID: residentSession.id)
            }
        )

        try await session.start(onPartial: { _ in })
        try await session.append(makeBuffer(sampleRate: 44_100, samples: [0.2, -0.2, 0.1, -0.1]))
        try await session.append(makeBuffer(sampleRate: 44_100, samples: [0.3, -0.3, 0.2, -0.2]))

        let startCalls = await recorder.startCalls
        let appendCalls = await recorder.appendCalls
        XCTAssertEqual(startCalls.count, 1)
        XCTAssertEqual(startCalls.first?.languageCode, "zh-Hans")
        XCTAssertEqual(startCalls.first?.sampleRate, 44_100)
        XCTAssertEqual(appendCalls.count, 2)
        XCTAssertEqual(appendCalls.map(\.sessionID), ["resident-session", "resident-session"])
    }

    func testSenseVoiceSessionFinishMapsUnifiedFinalResult() async throws {
        let session = SenseVoiceCaptureSession(
            languageCode: "en-US",
            startResidentSession: { sampleRate, languageCode in
                SenseVoiceResidentSession(id: "resident-session", language: languageCode, sampleRate: sampleRate)
            },
            appendAudio: { _, _ in },
            finalizeSession: { _ in
                LocalASRTranscriptionResult(
                    text: "hello world",
                    duration: 0.8,
                    commandSummary: "sensevoice http://127.0.0.1/finalize"
                )
            },
            cancelResidentSession: { _ in }
        )

        try await session.start(onPartial: { _ in })
        try await session.append(makeBuffer(sampleRate: 16_000, samples: [0.2, -0.2, 0.1, -0.1]))
        let result = try await session.finish()

        XCTAssertEqual(
            result,
            ASRCaptureSessionFinalResult(
                text: "hello world",
                source: "local",
                commandSummary: "sensevoice http://127.0.0.1/finalize"
            )
        )
    }

    func testFunASRSessionSyncsVocabularyBeforeStartAndPersistsUpdatedConfig() async throws {
        let recorder = SessionRecorder()
        let initialConfig = ASRProviderConfig(
            executablePath: "",
            modelPath: "",
            additionalArguments: "",
            baseURL: "wss://dashscope.aliyuncs.com/api-ws/v1/inference",
            apiKey: "dashscope-key",
            model: "fun-asr-realtime"
        )
        let syncedConfig = initialConfig.updatingFunASRVocabulary(
            vocabularyID: "voily-hotwords",
            vocabularyTargetModel: "fun-asr-realtime",
            vocabularyRevision: "revision-1"
        )

        let session = FunASRCaptureSession(
            languageCode: "zh-Hans",
            initialConfig: initialConfig,
            glossaryTerms: ["Voily", "SenseVoice"],
            syncVocabulary: { config, _ in
                XCTAssertEqual(config, initialConfig)
                return syncedConfig
            },
            persistConfig: { config in
                await recorder.recordPersistedConfig(config)
            },
            startRealtimeSession: { config, languageCode, _ in
                await recorder.recordStartedConfig(config, languageCode: languageCode)
            },
            appendAudioChunk: { _ in },
            finishRealtimeSession: {
                FunASRRealtimeASRResult(text: "热词已命中", duration: 0.5, commandSummary: "funasr finish")
            },
            cancelRealtimeSession: {}
        )

        try await session.start(onPartial: { _ in })

        let persistedConfigs = await recorder.persistedConfigs
        let startedConfigs = await recorder.startedConfigs
        let startedLanguages = await recorder.startedLanguages
        XCTAssertEqual(persistedConfigs, [syncedConfig])
        XCTAssertEqual(startedConfigs, [syncedConfig])
        XCTAssertEqual(startedLanguages, ["zh-Hans"])
    }

    func testQwenSessionFinishMapsUnifiedFinalResultAndCancelCallsBackend() async throws {
        let recorder = SessionRecorder()
        let config = ASRProviderConfig(
            executablePath: "",
            modelPath: "",
            additionalArguments: "",
            baseURL: "wss://dashscope.aliyuncs.com/api-ws/v1/realtime",
            apiKey: "dashscope-key",
            model: "qwen3-asr-flash-realtime"
        )
        let session = QwenCaptureSession(
            config: config,
            languageCode: "en-US",
            startRealtimeSession: { receivedConfig, languageCode, _ in
                XCTAssertEqual(receivedConfig, config)
                XCTAssertEqual(languageCode, "en-US")
            },
            appendAudioChunk: { pcmData in
                await recorder.recordQwenAppend(byteCount: pcmData.count)
            },
            finishRealtimeSession: {
                QwenRealtimeASRResult(
                    text: "hello world",
                    duration: 0.6,
                    commandSummary: "qwen finish"
                )
            },
            cancelRealtimeSession: {
                await recorder.recordQwenCancel()
            }
        )

        try await session.start(onPartial: { _ in })
        try await session.append(makeBuffer(sampleRate: 48_000, samples: [0.25, -0.25, 0.5, -0.5]))
        let result = try await session.finish()
        await session.cancel()

        let appendByteCounts = await recorder.qwenAppendByteCounts
        let cancelCount = await recorder.qwenCancelCount
        XCTAssertEqual(appendByteCounts, [2])
        XCTAssertEqual(cancelCount, 1)
        XCTAssertEqual(
            result,
            ASRCaptureSessionFinalResult(
                text: "hello world",
                source: "cloud-realtime",
                commandSummary: "qwen finish"
            )
        )
    }

    func testFunASRSessionAppendRethrowsChunkFailure() async throws {
        let config = ASRProviderConfig(
            executablePath: "",
            modelPath: "",
            additionalArguments: "",
            baseURL: "wss://dashscope.aliyuncs.com/api-ws/v1/inference",
            apiKey: "dashscope-key",
            model: "fun-asr-realtime"
        )
        let session = FunASRCaptureSession(
            languageCode: "zh-Hans",
            initialConfig: config,
            glossaryTerms: [],
            syncVocabulary: { config, _ in config },
            persistConfig: { _ in },
            startRealtimeSession: { _, _, _ in },
            appendAudioChunk: { _ in
                throw TestCaptureSessionError.expected
            },
            finishRealtimeSession: {
                FunASRRealtimeASRResult(text: "", duration: 0, commandSummary: "")
            },
            cancelRealtimeSession: {}
        )

        try await session.start(onPartial: { _ in })

        do {
            try await session.append(makeBuffer(sampleRate: 16_000, samples: [0.1, -0.1]))
            XCTFail("Expected append to throw")
        } catch {
            XCTAssertEqual(error as? TestCaptureSessionError, .expected)
        }
    }

    func testSenseVoiceSessionAppendRethrowsBackendFailure() async throws {
        let session = SenseVoiceCaptureSession(
            languageCode: "en-US",
            startResidentSession: { sampleRate, languageCode in
                SenseVoiceResidentSession(id: "resident-session", language: languageCode, sampleRate: sampleRate)
            },
            appendAudio: { _, _ in
                throw TestCaptureSessionError.expected
            },
            finalizeSession: { _ in
                LocalASRTranscriptionResult(text: "", duration: 0, commandSummary: "")
            },
            cancelResidentSession: { _ in }
        )

        try await session.start(onPartial: { _ in })

        do {
            try await session.append(makeBuffer(sampleRate: 16_000, samples: [0.1, -0.1]))
            XCTFail("Expected append to throw")
        } catch {
            XCTAssertEqual(error as? TestCaptureSessionError, .expected)
        }
    }

    func testSenseVoiceNativeSessionFinalizesAccumulatedAudio() async throws {
        let session = SenseVoiceNativeCaptureSession(
            languageCode: "en-US",
            transcribe: { pcm16MonoData, sampleRate, languageCode in
                XCTAssertFalse(pcm16MonoData.isEmpty)
                XCTAssertEqual(sampleRate, 16_000)
                XCTAssertEqual(languageCode, "en-US")
                return LocalASRTranscriptionResult(
                    text: "native result",
                    duration: 0.01,
                    commandSummary: "sensevoice-native-test"
                )
            }
        )

        try await session.start(onPartial: { _ in })
        try await session.append(makeBuffer(sampleRate: 48_000, samples: [0.1, -0.1, 0.2, -0.2]))

        let result = try await session.finish()

        XCTAssertEqual(result.text, "native result")
        XCTAssertEqual(result.source, "local")
        XCTAssertEqual(result.commandSummary, "sensevoice-native-test")
    }

    func testSenseVoiceNativeServiceReturnsCancellationBeforeModelLoad() async {
        let service = SenseVoiceNativeService()
        let task = Task {
            while !Task.isCancelled {
                await Task.yield()
            }
            return try await service.transcribe(
                pcm16MonoData: Data(repeating: 0, count: 2),
                sampleRate: 16_000,
                languageCode: "zh-Hans"
            )
        }

        task.cancel()

        do {
            _ = try await task.value
            XCTFail("Expected transcribe to throw CancellationError")
        } catch is CancellationError {
            // Expected.
        } catch {
            XCTFail("Expected CancellationError, got \(error)")
        }
    }

    func testSenseVoiceNativeSessionEmitsProgressivePartialPreview() async throws {
        let partialExpectation = expectation(description: "native partial preview")
        let recorder = SessionRecorder()
        let session = SenseVoiceNativeCaptureSession(
            languageCode: "zh-Hans",
            partialPreviewWindowSeconds: 0,
            partialPreviewMinimumInterval: 0,
            transcribe: { pcm16MonoData, _, _ in
                await recorder.recordNativeTranscribe(byteCount: pcm16MonoData.count)
                return LocalASRTranscriptionResult(
                    text: "渐进结果",
                    duration: 0.01,
                    commandSummary: "sensevoice-native-partial-test"
                )
            }
        )

        try await session.start(onPartial: { partialText in
            XCTAssertEqual(partialText, "渐进结果")
            partialExpectation.fulfill()
        })
        try await session.append(makeBuffer(sampleRate: 16_000, samples: [0.1, -0.1, 0.2, -0.2]))

        await fulfillment(of: [partialExpectation], timeout: 1)
        let transcribeByteCounts = await recorder.nativeTranscribeByteCounts
        XCTAssertFalse(transcribeByteCounts.isEmpty)

        await session.cancel()
    }

    func testSenseVoiceNativeSessionUsesIncrementalPartialWindows() async throws {
        let firstPartialExpectation = expectation(description: "first native partial preview")
        let secondPartialExpectation = expectation(description: "second native partial preview")
        let recorder = SessionRecorder()
        let session = SenseVoiceNativeCaptureSession(
            languageCode: "zh-Hans",
            partialPreviewWindowSeconds: 0.000125,
            partialPreviewOverlapSeconds: 0,
            partialPreviewMinimumInterval: 0,
            prepare: {
                await recorder.recordNativePrepare()
            },
            transcribe: { pcm16MonoData, _, _ in
                await recorder.recordNativeTranscribe(byteCount: pcm16MonoData.count)
                let callCount = await recorder.nativeTranscribeByteCounts.count
                return LocalASRTranscriptionResult(
                    text: callCount == 1 ? "第一段" : "第二段",
                    duration: 0.01,
                    commandSummary: "sensevoice-native-window-test"
                )
            }
        )

        try await session.start(onPartial: { partialText in
            Task {
                let partialCount = await recorder.recordNativePartial(partialText)
                if partialCount == 1 {
                    firstPartialExpectation.fulfill()
                } else if partialCount == 2 {
                    secondPartialExpectation.fulfill()
                }
            }
        })

        try await session.append(makeBuffer(sampleRate: 16_000, samples: [0.1, -0.1]))
        await fulfillment(of: [firstPartialExpectation], timeout: 1)
        try await session.append(makeBuffer(sampleRate: 16_000, samples: [0.2, -0.2]))
        await fulfillment(of: [secondPartialExpectation], timeout: 1)

        let transcribeByteCounts = await recorder.nativeTranscribeByteCounts
        let prepareCount = await recorder.nativePrepareCount
        let partials = await recorder.nativePartials
        XCTAssertEqual(prepareCount, 1)
        XCTAssertEqual(transcribeByteCounts, [4, 4])
        XCTAssertEqual(partials, ["第一段", "第一段第二段"])

        await session.cancel()
    }

    func testLiveFactoryReturnsProviderBoundSession() async {
        let factory = LiveASRCaptureSessionFactory(
            senseVoiceResidentService: SenseVoiceResidentService(),
            funASRRealtimeService: FunASRRealtimeService(),
            funASRVocabularyService: FunASRVocabularyService(),
            qwenRealtimeASRService: QwenRealtimeASRService(),
            stepRealtimeASRService: StepRealtimeASRService(),
            doubaoStreamingASRService: DoubaoStreamingASRService()
        )
        let session = factory.makeSession(
            provider: .funASR,
            languageCode: "zh-Hans",
            config: ASRProviderConfig.empty,
            glossaryTerms: [],
            persistConfig: { _ in }
        )

        XCTAssertEqual(session.provider, .funASR)
        XCTAssertTrue(session.session is FunASRCaptureSession)
    }

    private func makeBuffer(sampleRate: Double, samples: [Float]) -> AVAudioPCMBuffer {
        let format = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: sampleRate,
            channels: 1,
            interleaved: false
        )!
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(samples.count))!
        buffer.frameLength = AVAudioFrameCount(samples.count)
        for (index, sample) in samples.enumerated() {
            buffer.floatChannelData?[0][index] = sample
        }
        return buffer
    }
}
