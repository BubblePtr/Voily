import XCTest
import AVFoundation
@testable import Voily

private actor SessionRecorder {
    private(set) var startCalls: [(sampleRate: Double, languageCode: String)] = []
    private(set) var appendCalls: [(sessionID: String, byteCount: Int)] = []
    private(set) var cancelCalls: [String] = []
    private(set) var startedConfigs: [ASRProviderConfig] = []
    private(set) var startedLanguages: [String] = []
    private(set) var persistedConfigs: [ASRProviderConfig] = []
    private(set) var qwenAppendByteCounts: [Int] = []
    private(set) var qwenCancelCount = 0

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
        await session.append(makeBuffer(sampleRate: 44_100, samples: [0.2, -0.2, 0.1, -0.1]))
        await session.append(makeBuffer(sampleRate: 44_100, samples: [0.3, -0.3, 0.2, -0.2]))

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
        await session.append(makeBuffer(sampleRate: 16_000, samples: [0.2, -0.2, 0.1, -0.1]))
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
        await session.append(makeBuffer(sampleRate: 48_000, samples: [0.25, -0.25, 0.5, -0.5]))
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
