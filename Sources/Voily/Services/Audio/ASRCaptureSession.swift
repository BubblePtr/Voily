import AVFoundation
import Foundation

struct ASRCaptureSessionFinalResult: Equatable {
    let text: String
    let source: String
    let commandSummary: String?
}

enum ASRCaptureSessionError: LocalizedError {
    case noAudioCaptured

    var errorDescription: String? {
        switch self {
        case .noAudioCaptured:
            return "没有采集到可用于识别的音频。"
        }
    }
}

@MainActor
protocol ASRCaptureSession: AnyObject {
    func start(onPartial: @escaping @Sendable (String) -> Void) async throws
    func append(_ buffer: AVAudioPCMBuffer) async throws
    func finish() async throws -> ASRCaptureSessionFinalResult
    func cancel() async
}

@MainActor
struct ActiveASRCaptureSession {
    let provider: ASRProvider
    let session: any ASRCaptureSession
}

@MainActor
protocol ASRCaptureSessionBuilding {
    func makeSession(
        provider: ASRProvider,
        languageCode: String,
        config: ASRProviderConfig,
        glossaryTerms: [String],
        persistConfig: @escaping (ASRProviderConfig) async -> Void
    ) -> ActiveASRCaptureSession
}

@MainActor
struct LiveASRCaptureSessionFactory: ASRCaptureSessionBuilding {
    let senseVoiceResidentService: SenseVoiceResidentService
    let funASRRealtimeService: FunASRRealtimeService
    let funASRVocabularyService: FunASRVocabularyService
    let qwenRealtimeASRService: QwenRealtimeASRService
    let stepRealtimeASRService: StepRealtimeASRService
    let doubaoStreamingASRService: DoubaoStreamingASRService

    func makeSession(
        provider: ASRProvider,
        languageCode: String,
        config: ASRProviderConfig,
        glossaryTerms: [String],
        persistConfig: @escaping (ASRProviderConfig) async -> Void
    ) -> ActiveASRCaptureSession {
        let session: any ASRCaptureSession

        switch provider {
        case .senseVoice:
            session = SenseVoiceCaptureSession(
                service: senseVoiceResidentService,
                languageCode: languageCode
            )
        case .funASR:
            session = FunASRCaptureSession(
                realtimeService: funASRRealtimeService,
                vocabularyService: funASRVocabularyService,
                languageCode: languageCode,
                initialConfig: config,
                glossaryTerms: glossaryTerms,
                persistConfig: persistConfig
            )
        case .qwenASR:
            session = QwenCaptureSession(
                service: qwenRealtimeASRService,
                config: config,
                languageCode: languageCode
            )
        case .stepfunASR:
            session = StepCaptureSession(
                service: stepRealtimeASRService,
                config: config,
                languageCode: languageCode
            )
        case .doubaoStreaming:
            session = DoubaoCaptureSession(
                service: doubaoStreamingASRService,
                config: config,
                languageCode: languageCode
            )
        }

        return ActiveASRCaptureSession(provider: provider, session: session)
    }
}

struct LocalASRTranscriptionResult: Equatable {
    let text: String
    let duration: TimeInterval
    let commandSummary: String
}

enum AudioPCMConverter {
    static func pcm16MonoData(from buffer: AVAudioPCMBuffer, targetSampleRate: Double) throws -> Data {
        var data = Data()
        if abs(buffer.format.sampleRate - targetSampleRate) > 1 {
            try appendResampledPCM16Samples(from: buffer, targetSampleRate: targetSampleRate, to: &data)
        } else {
            try appendPCM16Samples(from: buffer, to: &data)
        }
        return data
    }

    private static func appendResampledPCM16Samples(from buffer: AVAudioPCMBuffer, targetSampleRate: Double, to data: inout Data) throws {
        let monoSamples = try monoFloatSamples(from: buffer)
        guard !monoSamples.isEmpty else { return }

        let sourceSampleRate = buffer.format.sampleRate
        let outputFrameCount = max(Int(round(Double(monoSamples.count) * targetSampleRate / sourceSampleRate)), 1)
        let step = sourceSampleRate / targetSampleRate

        for index in 0..<outputFrameCount {
            let sourcePosition = Double(index) * step
            let lowerIndex = min(Int(sourcePosition), monoSamples.count - 1)
            let upperIndex = min(lowerIndex + 1, monoSamples.count - 1)
            let fraction = Float(sourcePosition - Double(lowerIndex))
            let lowerSample = monoSamples[lowerIndex]
            let upperSample = monoSamples[upperIndex]
            let interpolated = lowerSample + ((upperSample - lowerSample) * fraction)
            append(int16Sample: int16Sample(from: interpolated), to: &data)
        }
    }

    private static func monoFloatSamples(from buffer: AVAudioPCMBuffer) throws -> [Float] {
        let frameCount = Int(buffer.frameLength)
        guard frameCount > 0 else { return [] }

        if let channelData = buffer.floatChannelData {
            let channelCount = Int(buffer.format.channelCount)
            var samples: [Float] = []
            samples.reserveCapacity(frameCount)
            for frame in 0..<frameCount {
                var sample: Float = 0
                for channel in 0..<channelCount {
                    sample += channelData[channel][frame]
                }
                samples.append(sample / Float(max(channelCount, 1)))
            }
            return samples
        }

        if let channelData = buffer.int16ChannelData {
            let channelCount = Int(buffer.format.channelCount)
            var samples: [Float] = []
            samples.reserveCapacity(frameCount)
            for frame in 0..<frameCount {
                var sample: Int32 = 0
                for channel in 0..<channelCount {
                    sample += Int32(channelData[channel][frame])
                }
                let averaged = Float(sample) / Float(max(channelCount, 1))
                samples.append(max(-1.0, min(1.0, averaged / 32768.0)))
            }
            return samples
        }

        throw NSError(domain: "AudioPCMConverter", code: -1, userInfo: [
            NSLocalizedDescriptionKey: "unsupported audio buffer format"
        ])
    }

    private static func appendPCM16Samples(from buffer: AVAudioPCMBuffer, to data: inout Data) throws {
        let frameCount = Int(buffer.frameLength)
        guard frameCount > 0 else { return }

        if let channelData = buffer.floatChannelData {
            let channelCount = Int(buffer.format.channelCount)
            for frame in 0..<frameCount {
                var sample: Float = 0
                for channel in 0..<channelCount {
                    sample += channelData[channel][frame]
                }
                sample /= Float(max(channelCount, 1))
                append(int16Sample: int16Sample(from: sample), to: &data)
            }
            return
        }

        if let channelData = buffer.int16ChannelData {
            let channelCount = Int(buffer.format.channelCount)
            for frame in 0..<frameCount {
                var sample: Int32 = 0
                for channel in 0..<channelCount {
                    sample += Int32(channelData[channel][frame])
                }
                let averaged = Int16(sample / Int32(max(channelCount, 1)))
                append(int16Sample: averaged, to: &data)
            }
            return
        }

        throw NSError(domain: "AudioPCMConverter", code: -1, userInfo: [
            NSLocalizedDescriptionKey: "unsupported audio buffer format"
        ])
    }

    private static func append(int16Sample: Int16, to data: inout Data) {
        var littleEndianSample = int16Sample.littleEndian
        withUnsafeBytes(of: &littleEndianSample) { bytes in
            data.append(contentsOf: bytes)
        }
    }

    private static func int16Sample(from value: Float) -> Int16 {
        let clipped = max(-1.0, min(1.0, value))
        if clipped >= 0 {
            return Int16(clipped * Float(Int16.max))
        }
        return Int16(clipped * 32768.0)
    }
}

@MainActor
final class SenseVoiceCaptureSession: ASRCaptureSession {
    private let languageCode: String
    private let startResidentSession: (Double, String) async throws -> SenseVoiceResidentSession
    private let appendAudio: (String, Data) async throws -> Void
    private let finalizeSession: (SenseVoiceResidentSession) async throws -> LocalASRTranscriptionResult
    private let cancelResidentSession: (SenseVoiceResidentSession) async -> Void

    private var residentSession: SenseVoiceResidentSession?

    init(
        languageCode: String,
        startResidentSession: @escaping (Double, String) async throws -> SenseVoiceResidentSession,
        appendAudio: @escaping (String, Data) async throws -> Void,
        finalizeSession: @escaping (SenseVoiceResidentSession) async throws -> LocalASRTranscriptionResult,
        cancelResidentSession: @escaping (SenseVoiceResidentSession) async -> Void
    ) {
        self.languageCode = languageCode
        self.startResidentSession = startResidentSession
        self.appendAudio = appendAudio
        self.finalizeSession = finalizeSession
        self.cancelResidentSession = cancelResidentSession
    }

    convenience init(service: SenseVoiceResidentService, languageCode: String) {
        self.init(
            languageCode: languageCode,
            startResidentSession: { sampleRate, languageCode in
                try await service.startSession(sampleRate: sampleRate, languageCode: languageCode)
            },
            appendAudio: { sessionID, pcm16MonoData in
                try await service.appendAudio(sessionID: sessionID, pcm16MonoData: pcm16MonoData)
            },
            finalizeSession: { residentSession in
                try await service.finalizeSession(residentSession)
            },
            cancelResidentSession: { residentSession in
                await service.cancelSession(residentSession)
            }
        )
    }

    func start(onPartial _: @escaping @Sendable (String) -> Void) async throws {}

    func append(_ buffer: AVAudioPCMBuffer) async throws {
        if residentSession == nil {
            residentSession = try await startResidentSession(buffer.format.sampleRate, languageCode)
            debugLog("SenseVoice capture session started")
        }

        guard let residentSession else { return }
        let pcmData = try AudioPCMConverter.pcm16MonoData(from: buffer, targetSampleRate: buffer.format.sampleRate)
        try await appendAudio(residentSession.id, pcmData)
    }

    func finish() async throws -> ASRCaptureSessionFinalResult {
        guard let residentSession else {
            throw ASRCaptureSessionError.noAudioCaptured
        }
        let result = try await finalizeSession(residentSession)
        return ASRCaptureSessionFinalResult(
            text: result.text,
            source: "local",
            commandSummary: result.commandSummary
        )
    }

    func cancel() async {
        guard let residentSession else { return }
        await cancelResidentSession(residentSession)
        self.residentSession = nil
    }
}

@MainActor
final class FunASRCaptureSession: ASRCaptureSession {
    private let languageCode: String
    private let initialConfig: ASRProviderConfig
    private let glossaryTerms: [String]
    private let syncVocabulary: (ASRProviderConfig, [String]) async throws -> ASRProviderConfig
    private let persistConfig: (ASRProviderConfig) async -> Void
    private let startRealtimeSession: (ASRProviderConfig, String, @escaping @Sendable (String) -> Void) async throws -> Void
    private let appendAudioChunk: (Data) async throws -> Void
    private let finishRealtimeSession: () async throws -> FunASRRealtimeASRResult
    private let cancelRealtimeSession: () async -> Void

    init(
        languageCode: String,
        initialConfig: ASRProviderConfig,
        glossaryTerms: [String],
        syncVocabulary: @escaping (ASRProviderConfig, [String]) async throws -> ASRProviderConfig,
        persistConfig: @escaping (ASRProviderConfig) async -> Void,
        startRealtimeSession: @escaping (ASRProviderConfig, String, @escaping @Sendable (String) -> Void) async throws -> Void,
        appendAudioChunk: @escaping (Data) async throws -> Void,
        finishRealtimeSession: @escaping () async throws -> FunASRRealtimeASRResult,
        cancelRealtimeSession: @escaping () async -> Void
    ) {
        self.languageCode = languageCode
        self.initialConfig = initialConfig
        self.glossaryTerms = glossaryTerms
        self.syncVocabulary = syncVocabulary
        self.persistConfig = persistConfig
        self.startRealtimeSession = startRealtimeSession
        self.appendAudioChunk = appendAudioChunk
        self.finishRealtimeSession = finishRealtimeSession
        self.cancelRealtimeSession = cancelRealtimeSession
    }

    convenience init(
        realtimeService: FunASRRealtimeService,
        vocabularyService: FunASRVocabularyService,
        languageCode: String,
        initialConfig: ASRProviderConfig,
        glossaryTerms: [String],
        persistConfig: @escaping (ASRProviderConfig) async -> Void
    ) {
        self.init(
            languageCode: languageCode,
            initialConfig: initialConfig,
            glossaryTerms: glossaryTerms,
            syncVocabulary: { config, glossaryTerms in
                try await vocabularyService.syncVocabularyIfNeeded(config: config, glossaryTerms: glossaryTerms)
            },
            persistConfig: persistConfig,
            startRealtimeSession: { config, languageCode, onPartial in
                try await realtimeService.startSession(config: config, languageCode: languageCode, onPartialText: onPartial)
            },
            appendAudioChunk: { pcmData in
                try await realtimeService.appendAudioChunk(pcmData)
            },
            finishRealtimeSession: {
                try await realtimeService.finishSession()
            },
            cancelRealtimeSession: {
                try? await realtimeService.cancelSession()
            }
        )
    }

    func start(onPartial: @escaping @Sendable (String) -> Void) async throws {
        let config: ASRProviderConfig

        do {
            let syncedConfig = try await syncVocabulary(initialConfig, glossaryTerms)
            if syncedConfig != initialConfig {
                await persistConfig(syncedConfig)
            }
            config = syncedConfig
        } catch {
            debugLog("Fun-ASR hotword sync failed error=\(error.localizedDescription)")
            let clearedConfig = initialConfig.clearingFunASRVocabulary()
            await persistConfig(clearedConfig)
            config = clearedConfig
        }

        try await startRealtimeSession(config, languageCode, onPartial)
    }

    func append(_ buffer: AVAudioPCMBuffer) async throws {
        let pcmData = try AudioPCMConverter.pcm16MonoData(from: buffer, targetSampleRate: 16_000)
        try await appendAudioChunk(pcmData)
    }

    func finish() async throws -> ASRCaptureSessionFinalResult {
        let result = try await finishRealtimeSession()
        return ASRCaptureSessionFinalResult(
            text: result.text,
            source: "cloud-realtime",
            commandSummary: result.commandSummary
        )
    }

    func cancel() async {
        await cancelRealtimeSession()
    }
}

@MainActor
final class QwenCaptureSession: ASRCaptureSession {
    private let config: ASRProviderConfig
    private let languageCode: String
    private let startRealtimeSession: (ASRProviderConfig, String, @escaping @Sendable (String) -> Void) async throws -> Void
    private let appendAudioChunk: (Data) async throws -> Void
    private let finishRealtimeSession: () async throws -> QwenRealtimeASRResult
    private let cancelRealtimeSession: () async -> Void

    init(
        config: ASRProviderConfig,
        languageCode: String,
        startRealtimeSession: @escaping (ASRProviderConfig, String, @escaping @Sendable (String) -> Void) async throws -> Void,
        appendAudioChunk: @escaping (Data) async throws -> Void,
        finishRealtimeSession: @escaping () async throws -> QwenRealtimeASRResult,
        cancelRealtimeSession: @escaping () async -> Void
    ) {
        self.config = config
        self.languageCode = languageCode
        self.startRealtimeSession = startRealtimeSession
        self.appendAudioChunk = appendAudioChunk
        self.finishRealtimeSession = finishRealtimeSession
        self.cancelRealtimeSession = cancelRealtimeSession
    }

    convenience init(service: QwenRealtimeASRService, config: ASRProviderConfig, languageCode: String) {
        self.init(
            config: config,
            languageCode: languageCode,
            startRealtimeSession: { config, languageCode, onPartial in
                try await service.startSession(config: config, languageCode: languageCode, onPartialText: onPartial)
            },
            appendAudioChunk: { pcmData in
                try await service.appendAudioChunk(pcmData)
            },
            finishRealtimeSession: {
                try await service.finishSession()
            },
            cancelRealtimeSession: {
                try? await service.cancelSession()
            }
        )
    }

    func start(onPartial: @escaping @Sendable (String) -> Void) async throws {
        try await startRealtimeSession(config, languageCode, onPartial)
    }

    func append(_ buffer: AVAudioPCMBuffer) async throws {
        let pcmData = try AudioPCMConverter.pcm16MonoData(from: buffer, targetSampleRate: 16_000)
        try await appendAudioChunk(pcmData)
    }

    func finish() async throws -> ASRCaptureSessionFinalResult {
        let result = try await finishRealtimeSession()
        return ASRCaptureSessionFinalResult(
            text: result.text,
            source: "cloud-realtime",
            commandSummary: result.commandSummary
        )
    }

    func cancel() async {
        await cancelRealtimeSession()
    }
}

@MainActor
final class StepCaptureSession: ASRCaptureSession {
    private let config: ASRProviderConfig
    private let languageCode: String
    private let startRealtimeSession: (ASRProviderConfig, String, @escaping @Sendable (String) -> Void) async throws -> Void
    private let appendAudioChunk: (Data) async throws -> Void
    private let finishRealtimeSession: () async throws -> StepRealtimeASRResult
    private let cancelRealtimeSession: () async -> Void

    init(
        config: ASRProviderConfig,
        languageCode: String,
        startRealtimeSession: @escaping (ASRProviderConfig, String, @escaping @Sendable (String) -> Void) async throws -> Void,
        appendAudioChunk: @escaping (Data) async throws -> Void,
        finishRealtimeSession: @escaping () async throws -> StepRealtimeASRResult,
        cancelRealtimeSession: @escaping () async -> Void
    ) {
        self.config = config
        self.languageCode = languageCode
        self.startRealtimeSession = startRealtimeSession
        self.appendAudioChunk = appendAudioChunk
        self.finishRealtimeSession = finishRealtimeSession
        self.cancelRealtimeSession = cancelRealtimeSession
    }

    convenience init(service: StepRealtimeASRService, config: ASRProviderConfig, languageCode: String) {
        self.init(
            config: config,
            languageCode: languageCode,
            startRealtimeSession: { config, languageCode, onPartial in
                try await service.startSession(config: config, languageCode: languageCode, onPartialText: onPartial)
            },
            appendAudioChunk: { pcmData in
                try await service.appendAudioChunk(pcmData)
            },
            finishRealtimeSession: {
                try await service.finishSession()
            },
            cancelRealtimeSession: {
                try? await service.cancelSession()
            }
        )
    }

    func start(onPartial: @escaping @Sendable (String) -> Void) async throws {
        try await startRealtimeSession(config, languageCode, onPartial)
    }

    func append(_ buffer: AVAudioPCMBuffer) async throws {
        let pcmData = try AudioPCMConverter.pcm16MonoData(from: buffer, targetSampleRate: 16_000)
        try await appendAudioChunk(pcmData)
    }

    func finish() async throws -> ASRCaptureSessionFinalResult {
        let result = try await finishRealtimeSession()
        return ASRCaptureSessionFinalResult(
            text: result.text,
            source: "cloud-realtime",
            commandSummary: result.commandSummary
        )
    }

    func cancel() async {
        await cancelRealtimeSession()
    }
}

@MainActor
final class DoubaoCaptureSession: ASRCaptureSession {
    private let config: ASRProviderConfig
    private let languageCode: String
    private let startRealtimeSession: (ASRProviderConfig, String, @escaping @Sendable (String) -> Void) async throws -> Void
    private let appendAudioChunk: (Data) async throws -> Void
    private let finishRealtimeSession: () async throws -> DoubaoStreamingASRResult
    private let cancelRealtimeSession: () async -> Void

    init(
        config: ASRProviderConfig,
        languageCode: String,
        startRealtimeSession: @escaping (ASRProviderConfig, String, @escaping @Sendable (String) -> Void) async throws -> Void,
        appendAudioChunk: @escaping (Data) async throws -> Void,
        finishRealtimeSession: @escaping () async throws -> DoubaoStreamingASRResult,
        cancelRealtimeSession: @escaping () async -> Void
    ) {
        self.config = config
        self.languageCode = languageCode
        self.startRealtimeSession = startRealtimeSession
        self.appendAudioChunk = appendAudioChunk
        self.finishRealtimeSession = finishRealtimeSession
        self.cancelRealtimeSession = cancelRealtimeSession
    }

    convenience init(service: DoubaoStreamingASRService, config: ASRProviderConfig, languageCode: String) {
        self.init(
            config: config,
            languageCode: languageCode,
            startRealtimeSession: { config, languageCode, onPartial in
                try await service.startSession(config: config, languageCode: languageCode, onPartialText: onPartial)
            },
            appendAudioChunk: { pcmData in
                try await service.appendAudioChunk(pcmData)
            },
            finishRealtimeSession: {
                try await service.finishSession()
            },
            cancelRealtimeSession: {
                try? await service.cancelSession()
            }
        )
    }

    func start(onPartial: @escaping @Sendable (String) -> Void) async throws {
        try await startRealtimeSession(config, languageCode, onPartial)
    }

    func append(_ buffer: AVAudioPCMBuffer) async throws {
        let pcmData = try AudioPCMConverter.pcm16MonoData(from: buffer, targetSampleRate: 16_000)
        try await appendAudioChunk(pcmData)
    }

    func finish() async throws -> ASRCaptureSessionFinalResult {
        let result = try await finishRealtimeSession()
        return ASRCaptureSessionFinalResult(
            text: result.text,
            source: "cloud-realtime",
            commandSummary: result.commandSummary
        )
    }

    func cancel() async {
        await cancelRealtimeSession()
    }
}
