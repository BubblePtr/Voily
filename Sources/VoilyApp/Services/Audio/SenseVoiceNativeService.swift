import AVFoundation
import Foundation
import MLX
import MLXNN
import VoilyCore

enum SenseVoiceNativeError: LocalizedError {
    case modelDirectoryMissing(URL)
    case missingModelFile(String)
    case invalidConfiguration(String)
    case missingWeight(String)
    case invalidTokenizer
    case invalidAudio
    case emptyTranscript

    var errorDescription: String? {
        switch self {
        case let .modelDirectoryMissing(url):
            return String(format: AppLocalization.localized("未找到 SenseVoice 模型目录：%@"), url.path)
        case let .missingModelFile(name):
            return String(format: AppLocalization.localized("SenseVoice 模型文件缺失：%@"), name)
        case let .invalidConfiguration(message):
            return String(format: AppLocalization.localized("SenseVoice 配置无效：%@"), message)
        case let .missingWeight(name):
            return String(format: AppLocalization.localized("SenseVoice 权重缺失：%@"), name)
        case .invalidTokenizer:
            return AppLocalization.localized("SenseVoice tokenizer 无效。")
        case .invalidAudio:
            return AppLocalization.localized("没有可用于识别的 SenseVoice 音频。")
        case .emptyTranscript:
            return AppLocalization.localized("SenseVoice 未返回可用文本。")
        }
    }
}

actor SenseVoiceNativeService {
    private var loadedModelDirectory: URL?
    private var model: SenseVoiceNativeModel?

    func prepare() async throws {
        try Task.checkCancellation()
        _ = try loadModelIfNeeded(modelDirectory: defaultModelDirectory())
    }

    func transcribe(
        pcm16MonoData: Data,
        sampleRate: Double,
        languageCode: String
    ) async throws -> LocalASRTranscriptionResult {
        try Task.checkCancellation()
        let startedAt = Date()
        let modelDirectory = defaultModelDirectory()
        let model = try loadModelIfNeeded(modelDirectory: modelDirectory)
        try Task.checkCancellation()
        let samples = SenseVoicePCM.decodePCM16Mono(pcm16MonoData)
        guard !samples.isEmpty else {
            throw SenseVoiceNativeError.invalidAudio
        }
        try Task.checkCancellation()

        let normalizedLanguage = Self.normalizedLanguageCode(languageCode)
        let text = try model.transcribe(
            samples: samples,
            sampleRate: Int(sampleRate.rounded()),
            language: normalizedLanguage,
            useITN: true
        ).trimmingCharacters(in: .whitespacesAndNewlines)
        try Task.checkCancellation()

        guard !text.isEmpty else {
            throw SenseVoiceNativeError.emptyTranscript
        }

        return LocalASRTranscriptionResult(
            text: text,
            duration: Date().timeIntervalSince(startedAt),
            commandSummary: "sensevoice-native-mlx \(modelDirectory.path)"
        )
    }

    func resetLoadedModel() {
        loadedModelDirectory = nil
        model = nil
    }

    private func loadModelIfNeeded(modelDirectory: URL) throws -> SenseVoiceNativeModel {
        if let model, loadedModelDirectory?.standardizedFileURL == modelDirectory.standardizedFileURL {
            return model
        }

        let loaded = try SenseVoiceNativeModel(modelDirectory: modelDirectory)
        model = loaded
        loadedModelDirectory = modelDirectory
        return loaded
    }

    private func defaultModelDirectory() -> URL {
        FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)
            .first!
            .appending(path: "Voily")
            .appending(path: "LocalModels")
            .appending(path: ASRProvider.senseVoice.rawValue)
            .appending(path: "model")
    }

    private static func normalizedLanguageCode(_ languageCode: String) -> String {
        if languageCode.hasPrefix("zh") {
            return "zh"
        }
        if languageCode.hasPrefix("ja") {
            return "ja"
        }
        if languageCode.hasPrefix("ko") {
            return "ko"
        }
        if languageCode.hasPrefix("yue") {
            return "yue"
        }
        if languageCode.hasPrefix("en") {
            return "en"
        }
        return "auto"
    }
}

@MainActor
final class SenseVoiceNativeCaptureSession: ASRCaptureSession {
    private let languageCode: String
    private let prepare: () async throws -> Void
    private let transcribe: (Data, Double, String) async throws -> LocalASRTranscriptionResult
    private let partialPreviewWindowBytes: Int
    private let partialPreviewOverlapBytes: Int
    private let partialPreviewMinimumInterval: TimeInterval
    private var pcm16MonoData = Data()
    private let targetSampleRate = 16_000.0
    private var onPartialText: (@Sendable (String) -> Void)?
    private var prepareTask: Task<Void, Error>?
    private var partialPreviewTask: Task<Void, Never>?
    private var lastPartialPreviewStartedAt: Date?
    private var nextPartialPreviewStartByte = 0
    private var transcriptAccumulator = TranscriptAccumulator()
    private var lastDeliveredPartialText = ""
    private var isClosed = false

    init(
        languageCode: String,
        partialPreviewWindowSeconds: TimeInterval = 1.2,
        partialPreviewOverlapSeconds: TimeInterval = 0.35,
        partialPreviewMinimumInterval: TimeInterval = 1.0,
        prepare: @escaping () async throws -> Void = {},
        transcribe: @escaping (Data, Double, String) async throws -> LocalASRTranscriptionResult
    ) {
        self.languageCode = languageCode
        self.prepare = prepare
        self.transcribe = transcribe
        partialPreviewWindowBytes = Self.pcm16ByteCount(
            seconds: partialPreviewWindowSeconds,
            sampleRate: targetSampleRate
        )
        partialPreviewOverlapBytes = Self.pcm16ByteCount(
            seconds: partialPreviewOverlapSeconds,
            sampleRate: targetSampleRate
        )
        self.partialPreviewMinimumInterval = partialPreviewMinimumInterval
    }

    convenience init(service: SenseVoiceNativeService, languageCode: String) {
        self.init(
            languageCode: languageCode,
            prepare: {
                try await service.prepare()
            },
            transcribe: { pcm16MonoData, sampleRate, languageCode in
                try await service.transcribe(
                    pcm16MonoData: pcm16MonoData,
                    sampleRate: sampleRate,
                    languageCode: languageCode
                )
            }
        )
    }

    func start(onPartial: @escaping @Sendable (String) -> Void) async throws {
        onPartialText = onPartial
        prepareTask = Task { [prepare] in
            try await prepare()
        }
    }

    func append(_ buffer: AVAudioPCMBuffer) async throws {
        let chunk = try AudioPCMConverter.pcm16MonoData(from: buffer, targetSampleRate: targetSampleRate)
        pcm16MonoData.append(chunk)
        schedulePartialPreviewIfNeeded()
    }

    func finish() async throws -> ASRCaptureSessionFinalResult {
        guard !pcm16MonoData.isEmpty else {
            throw ASRCaptureSessionError.noAudioCaptured
        }
        isClosed = true
        partialPreviewTask?.cancel()
        partialPreviewTask = nil
        try await prepareTask?.value

        let result = try await transcribe(pcm16MonoData, targetSampleRate, languageCode)
        return ASRCaptureSessionFinalResult(
            text: result.text,
            source: "local",
            commandSummary: result.commandSummary
        )
    }

    func cancel() async {
        isClosed = true
        partialPreviewTask?.cancel()
        partialPreviewTask = nil
        pcm16MonoData.removeAll(keepingCapacity: false)
        transcriptAccumulator.reset()
    }

    private func schedulePartialPreviewIfNeeded() {
        guard !isClosed else { return }
        guard onPartialText != nil else { return }
        guard partialPreviewTask == nil else { return }
        guard pcm16MonoData.count > nextPartialPreviewStartByte else { return }
        guard pcm16MonoData.count - nextPartialPreviewStartByte >= partialPreviewWindowBytes else { return }

        let now = Date()
        if let lastPartialPreviewStartedAt,
           now.timeIntervalSince(lastPartialPreviewStartedAt) < partialPreviewMinimumInterval {
            return
        }

        let snapshotEnd = pcm16MonoData.count
        let snapshotStart = max(0, nextPartialPreviewStartByte - partialPreviewOverlapBytes)
        let snapshot = Data(pcm16MonoData[snapshotStart ..< snapshotEnd])
        lastPartialPreviewStartedAt = now
        nextPartialPreviewStartByte = snapshotEnd

        partialPreviewTask = Task { [weak self] in
            guard let self else { return }
            do {
                try await prepareTask?.value
                guard !Task.isCancelled else { return }
                let result = try await transcribe(snapshot, targetSampleRate, languageCode)
                guard !Task.isCancelled else { return }
                deliverPartialPreview(result.text)
            } catch is CancellationError {
                finishPartialPreview()
            } catch SenseVoiceNativeError.emptyTranscript {
                finishPartialPreview()
            } catch {
                debugLog("SenseVoice native partial preview failed: \(error.localizedDescription)")
                finishPartialPreview()
            }
        }
    }

    private func deliverPartialPreview(_ text: String) {
        partialPreviewTask = nil
        guard !isClosed else { return }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let displayText = transcriptAccumulator.commit(trimmed)
        guard displayText != lastDeliveredPartialText else { return }
        lastDeliveredPartialText = displayText
        onPartialText?(displayText)
        schedulePartialPreviewIfNeeded()
    }

    private func finishPartialPreview() {
        partialPreviewTask = nil
        guard !isClosed else { return }
        schedulePartialPreviewIfNeeded()
    }

    private static func pcm16ByteCount(seconds: TimeInterval, sampleRate: Double) -> Int {
        max(0, Int(seconds * sampleRate) * 2)
    }
}

private final class SenseVoiceNativeModel {
    private let configuration: SenseVoiceModelConfiguration
    private let encoder: SenseVoiceEncoder
    private let ctcProjection: SenseVoiceLinear
    private let embedding: SenseVoiceEmbedding
    private let tokenizer: SenseVoicePieceDecoder
    private let cmvnMeans: [Float]
    private let cmvnInverseStd: [Float]

    private let languageIDs = [
        "auto": 0,
        "zh": 3,
        "en": 4,
        "yue": 7,
        "ja": 11,
        "ko": 12,
        "nospeech": 13,
    ]
    private let textNormIDs = [
        "withitn": 14,
        "woitn": 15,
    ]
    private let blankID = Int32(0)

    init(modelDirectory: URL) throws {
        guard FileManager.default.fileExists(atPath: modelDirectory.path) else {
            throw SenseVoiceNativeError.modelDirectoryMissing(modelDirectory)
        }

        let configurationURL = modelDirectory.appending(path: "config.json")
        let weightsURL = modelDirectory.appending(path: "model.safetensors")
        let tokenizerURL = modelDirectory.appending(path: "chn_jpn_yue_eng_ko_spectok.bpe.model")
        let cmvnURL = modelDirectory.appending(path: "am.mvn")

        for fileURL in [configurationURL, weightsURL, tokenizerURL, cmvnURL] where !FileManager.default.fileExists(atPath: fileURL.path) {
            throw SenseVoiceNativeError.missingModelFile(fileURL.lastPathComponent)
        }

        configuration = try SenseVoiceModelConfiguration.load(from: configurationURL)
        let weights = SenseVoiceWeightStore(rawWeights: try loadArrays(url: weightsURL))
        encoder = try SenseVoiceEncoder(configuration: configuration, weights: weights)
        ctcProjection = try SenseVoiceLinear(prefix: "ctc_lo", weights: weights)
        embedding = try SenseVoiceEmbedding(prefix: "embed", weights: weights)
        tokenizer = try SenseVoicePieceDecoder(modelURL: tokenizerURL)
        let cmvn = try SenseVoiceCMVN.load(from: cmvnURL)
        cmvnMeans = cmvn.means
        cmvnInverseStd = cmvn.inverseStd
    }

    func transcribe(
        samples: [Float],
        sampleRate: Int,
        language: String,
        useITN: Bool
    ) throws -> String {
        try Task.checkCancellation()
        let features = try SenseVoiceFeatureExtractor.extract(
            samples: samples,
            sampleRate: sampleRate,
            configuration: configuration.frontend,
            cmvnMeans: cmvnMeans,
            cmvnInverseStd: cmvnInverseStd
        )
        guard features.dim(0) > 0 else {
            throw SenseVoiceNativeError.invalidAudio
        }
        try Task.checkCancellation()

        let networkOutput = try callAsFunction(
            features[.newAxis],
            language: language,
            useITN: useITN
        )
        try Task.checkCancellation()
        let logProbabilities = networkOutput[0]
        let transcriptProbabilities = logProbabilities[4...]
        let tokenIDs = greedyCTCDecode(transcriptProbabilities)
        try Task.checkCancellation()
        return tokenizer.decode(tokenIDs)
    }

    private func callAsFunction(
        _ features: MLXArray,
        language: String,
        useITN: Bool
    ) throws -> MLXArray {
        try Task.checkCancellation()
        let batchSize = features.dim(0)
        let (textNormQuery, inputQuery) = buildQuery(
            batchSize: batchSize,
            language: language,
            useITN: useITN
        )
        var speech = concatenated([textNormQuery, features], axis: 1)
        speech = concatenated([inputQuery, speech], axis: 1)
        try Task.checkCancellation()
        let encoderOutput = try encoder(speech)
        try Task.checkCancellation()
        let logits = ctcProjection(encoderOutput)
        return logSoftmax(logits, axis: -1)
    }

    private func buildQuery(
        batchSize: Int,
        language: String,
        useITN: Bool
    ) -> (MLXArray, MLXArray) {
        let languageID = languageIDs[language] ?? 0
        var languageQuery = embedding(MLXArray([languageID], [1, 1]))
        let textNormID = textNormIDs[useITN ? "withitn" : "woitn"] ?? 15
        var textNormQuery = embedding(MLXArray([textNormID], [1, 1]))
        var eventEmotionQuery = embedding(MLXArray([1, 2], [1, 2]))

        if batchSize > 1 {
            languageQuery = broadcast(languageQuery, to: [batchSize, 1, configuration.inputSize])
            textNormQuery = broadcast(textNormQuery, to: [batchSize, 1, configuration.inputSize])
            eventEmotionQuery = broadcast(eventEmotionQuery, to: [batchSize, 2, configuration.inputSize])
        }

        return (textNormQuery, concatenated([languageQuery, eventEmotionQuery], axis: 1))
    }

    private func greedyCTCDecode(_ logProbabilities: MLXArray) -> [Int32] {
        let predicted = argMax(logProbabilities, axis: -1).asArray(Int32.self)
        var deduped: [Int32] = []
        var previous: Int32?

        for tokenID in predicted {
            if tokenID != previous {
                deduped.append(tokenID)
                previous = tokenID
            }
        }

        return deduped.filter { $0 != blankID }
    }
}

private struct SenseVoiceModelConfiguration: Decodable {
    let vocabSize: Int
    let inputSize: Int
    let encoder: SenseVoiceEncoderConfiguration
    let frontend: SenseVoiceFrontendConfiguration

    enum CodingKeys: String, CodingKey {
        case vocabSize = "vocab_size"
        case inputSize = "input_size"
        case encoder = "encoder_conf"
        case frontend = "frontend_conf"
    }

    static func load(from url: URL) throws -> Self {
        do {
            let data = try Data(contentsOf: url)
            return try JSONDecoder().decode(Self.self, from: data)
        } catch {
            throw SenseVoiceNativeError.invalidConfiguration(error.localizedDescription)
        }
    }
}

private struct SenseVoiceEncoderConfiguration: Decodable {
    let outputSize: Int
    let attentionHeads: Int
    let linearUnits: Int
    let numBlocks: Int
    let tpBlocks: Int
    let kernelSize: Int
    let sanmShift: Int
    let normalizeBefore: Bool

    enum CodingKeys: String, CodingKey {
        case outputSize = "output_size"
        case attentionHeads = "attention_heads"
        case linearUnits = "linear_units"
        case numBlocks = "num_blocks"
        case tpBlocks = "tp_blocks"
        case kernelSize = "kernel_size"
        case sanmShift = "sanm_shift"
        case sanmShiftTypo = "sanm_shfit"
        case normalizeBefore = "normalize_before"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        outputSize = try container.decodeIfPresent(Int.self, forKey: .outputSize) ?? 512
        attentionHeads = try container.decodeIfPresent(Int.self, forKey: .attentionHeads) ?? 4
        linearUnits = try container.decodeIfPresent(Int.self, forKey: .linearUnits) ?? 2048
        numBlocks = try container.decodeIfPresent(Int.self, forKey: .numBlocks) ?? 50
        tpBlocks = try container.decodeIfPresent(Int.self, forKey: .tpBlocks) ?? 20
        kernelSize = try container.decodeIfPresent(Int.self, forKey: .kernelSize) ?? 11
        sanmShift = try container.decodeIfPresent(Int.self, forKey: .sanmShift)
            ?? container.decodeIfPresent(Int.self, forKey: .sanmShiftTypo)
            ?? 0
        normalizeBefore = try container.decodeIfPresent(Bool.self, forKey: .normalizeBefore) ?? true
    }
}

private struct SenseVoiceFrontendConfiguration: Decodable {
    let sampleRate: Int
    let window: String
    let melCount: Int
    let frameLength: Int
    let frameShift: Int
    let lfrM: Int
    let lfrN: Int

    enum CodingKeys: String, CodingKey {
        case sampleRate = "fs"
        case window
        case melCount = "n_mels"
        case frameLength = "frame_length"
        case frameShift = "frame_shift"
        case lfrM = "lfr_m"
        case lfrN = "lfr_n"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        sampleRate = try container.decodeIfPresent(Int.self, forKey: .sampleRate) ?? 16_000
        window = try container.decodeIfPresent(String.self, forKey: .window) ?? "hamming"
        melCount = try container.decodeIfPresent(Int.self, forKey: .melCount) ?? 80
        frameLength = try container.decodeIfPresent(Int.self, forKey: .frameLength) ?? 25
        frameShift = try container.decodeIfPresent(Int.self, forKey: .frameShift) ?? 10
        lfrM = try container.decodeIfPresent(Int.self, forKey: .lfrM) ?? 7
        lfrN = try container.decodeIfPresent(Int.self, forKey: .lfrN) ?? 6
    }
}

private struct SenseVoiceWeightStore {
    let rawWeights: [String: MLXArray]

    func array(_ key: String) throws -> MLXArray {
        let storageKey: String
        if key.hasPrefix("ctc_lo.") {
            storageKey = key.replacingOccurrences(of: "ctc_lo.", with: "ctc.ctc_lo.")
        } else {
            storageKey = key
        }

        guard var value = rawWeights[storageKey] ?? rawWeights[key] else {
            throw SenseVoiceNativeError.missingWeight(key)
        }

        if key.contains("fsmn_block.weight"), value.shape.count == 3, value.shape[1] == 1 {
            value = value.transposed(0, 2, 1)
        }

        return value
    }
}

private struct SenseVoiceLinear {
    let weight: MLXArray
    let bias: MLXArray?

    init(prefix: String, weights: SenseVoiceWeightStore, bias: Bool = true) throws {
        weight = try weights.array("\(prefix).weight")
        self.bias = bias ? try weights.array("\(prefix).bias") : nil
    }

    func callAsFunction(_ input: MLXArray) -> MLXArray {
        var output = matmul(input, weight.T)
        if let bias {
            output = output + bias
        }
        return output
    }
}

private struct SenseVoiceEmbedding {
    let weight: MLXArray

    init(prefix: String, weights: SenseVoiceWeightStore) throws {
        weight = try weights.array("\(prefix).weight")
    }

    func callAsFunction(_ input: MLXArray) -> MLXArray {
        weight[input]
    }
}

private struct SenseVoiceLayerNorm {
    let weight: MLXArray
    let bias: MLXArray

    init(prefix: String, weights: SenseVoiceWeightStore) throws {
        weight = try weights.array("\(prefix).weight")
        bias = try weights.array("\(prefix).bias")
    }

    func callAsFunction(_ input: MLXArray) -> MLXArray {
        layerNorm(input, weight: weight, bias: bias, eps: 1e-5)
    }
}

private struct SenseVoiceFeedForward {
    let first: SenseVoiceLinear
    let second: SenseVoiceLinear

    init(prefix: String, weights: SenseVoiceWeightStore) throws {
        first = try SenseVoiceLinear(prefix: "\(prefix).w_1", weights: weights)
        second = try SenseVoiceLinear(prefix: "\(prefix).w_2", weights: weights)
    }

    func callAsFunction(_ input: MLXArray) -> MLXArray {
        second(relu(first(input)))
    }
}

private struct SenseVoiceSANMAttention {
    let headCount: Int
    let headDimension: Int
    let featureDimension: Int
    let linearQKV: SenseVoiceLinear
    let linearOutput: SenseVoiceLinear
    let fsmnWeight: MLXArray
    let leftPadding: Int
    let rightPadding: Int

    init(
        prefix: String,
        inputFeatureDimension: Int,
        outputFeatureDimension: Int,
        configuration: SenseVoiceEncoderConfiguration,
        weights: SenseVoiceWeightStore
    ) throws {
        guard outputFeatureDimension % configuration.attentionHeads == 0 else {
            throw SenseVoiceNativeError.invalidConfiguration("attention head count does not divide output size")
        }
        headCount = configuration.attentionHeads
        headDimension = outputFeatureDimension / configuration.attentionHeads
        featureDimension = outputFeatureDimension
        linearQKV = try SenseVoiceLinear(prefix: "\(prefix).linear_q_k_v", weights: weights)
        linearOutput = try SenseVoiceLinear(prefix: "\(prefix).linear_out", weights: weights)
        fsmnWeight = try weights.array("\(prefix).fsmn_block.weight")

        var left = (configuration.kernelSize - 1) / 2
        if configuration.sanmShift > 0 {
            left += configuration.sanmShift
        }
        leftPadding = left
        rightPadding = configuration.kernelSize - 1 - left
        _ = inputFeatureDimension
    }

    func callAsFunction(_ input: MLXArray) -> MLXArray {
        let batchSize = input.dim(0)
        let timeSteps = input.dim(1)
        let qkv = linearQKV(input)
        let parts = split(qkv, parts: 3, axis: -1)
        let query = parts[0]
        let key = parts[1]
        let value = parts[2]

        let fsmnInput = padded(
            value,
            widths: [
                IntOrPair((0, 0)),
                IntOrPair((leftPadding, rightPadding)),
                IntOrPair((0, 0)),
            ]
        )
        let fsmnMemory = conv1d(fsmnInput, fsmnWeight, groups: featureDimension) + value

        let q = query
            .reshaped(batchSize, timeSteps, headCount, headDimension)
            .transposed(0, 2, 1, 3)
        let k = key
            .reshaped(batchSize, timeSteps, headCount, headDimension)
            .transposed(0, 2, 1, 3)
        let v = value
            .reshaped(batchSize, timeSteps, headCount, headDimension)
            .transposed(0, 2, 1, 3)

        let scores = matmul(q * Float(pow(Double(headDimension), -0.5)), k.transposed(0, 1, 3, 2))
        let attention = softmax(scores, axis: -1)
        let attentionOutput = matmul(attention, v)
            .transposed(0, 2, 1, 3)
            .reshaped(batchSize, timeSteps, featureDimension)

        return linearOutput(attentionOutput) + fsmnMemory
    }
}

private struct SenseVoiceEncoderLayer {
    let inputSize: Int
    let outputSize: Int
    let normalizeBefore: Bool
    let attention: SenseVoiceSANMAttention
    let feedForward: SenseVoiceFeedForward
    let firstNorm: SenseVoiceLayerNorm
    let secondNorm: SenseVoiceLayerNorm

    init(
        prefix: String,
        inputSize: Int,
        outputSize: Int,
        configuration: SenseVoiceEncoderConfiguration,
        weights: SenseVoiceWeightStore
    ) throws {
        self.inputSize = inputSize
        self.outputSize = outputSize
        normalizeBefore = configuration.normalizeBefore
        attention = try SenseVoiceSANMAttention(
            prefix: "\(prefix).self_attn",
            inputFeatureDimension: inputSize,
            outputFeatureDimension: outputSize,
            configuration: configuration,
            weights: weights
        )
        feedForward = try SenseVoiceFeedForward(prefix: "\(prefix).feed_forward", weights: weights)
        firstNorm = try SenseVoiceLayerNorm(prefix: "\(prefix).norm1", weights: weights)
        secondNorm = try SenseVoiceLayerNorm(prefix: "\(prefix).norm2", weights: weights)
    }

    func callAsFunction(_ input: MLXArray) throws -> MLXArray {
        try Task.checkCancellation()
        let residual = input
        var x = input
        if normalizeBefore {
            x = firstNorm(x)
        }

        let attentionOutput = attention(x)
        try Task.checkCancellation()
        if inputSize == outputSize {
            x = residual + attentionOutput
        } else {
            x = attentionOutput
        }

        let feedForwardResidual = x
        if normalizeBefore {
            x = secondNorm(x)
        }

        try Task.checkCancellation()
        return feedForwardResidual + feedForward(x)
    }
}

private struct SenseVoiceEncoder {
    let outputSize: Int
    let firstLayers: [SenseVoiceEncoderLayer]
    let layers: [SenseVoiceEncoderLayer]
    let afterNorm: SenseVoiceLayerNorm
    let tpLayers: [SenseVoiceEncoderLayer]
    let tpNorm: SenseVoiceLayerNorm

    init(configuration: SenseVoiceModelConfiguration, weights: SenseVoiceWeightStore) throws {
        let encoderConfiguration = configuration.encoder
        outputSize = encoderConfiguration.outputSize
        firstLayers = [
            try SenseVoiceEncoderLayer(
                prefix: "encoder.encoders0.0",
                inputSize: configuration.inputSize,
                outputSize: encoderConfiguration.outputSize,
                configuration: encoderConfiguration,
                weights: weights
            ),
        ]
        layers = try (0 ..< max(encoderConfiguration.numBlocks - 1, 0)).map { index in
            try SenseVoiceEncoderLayer(
                prefix: "encoder.encoders.\(index)",
                inputSize: encoderConfiguration.outputSize,
                outputSize: encoderConfiguration.outputSize,
                configuration: encoderConfiguration,
                weights: weights
            )
        }
        afterNorm = try SenseVoiceLayerNorm(prefix: "encoder.after_norm", weights: weights)
        tpLayers = try (0 ..< encoderConfiguration.tpBlocks).map { index in
            try SenseVoiceEncoderLayer(
                prefix: "encoder.tp_encoders.\(index)",
                inputSize: encoderConfiguration.outputSize,
                outputSize: encoderConfiguration.outputSize,
                configuration: encoderConfiguration,
                weights: weights
            )
        }
        tpNorm = try SenseVoiceLayerNorm(prefix: "encoder.tp_norm", weights: weights)
    }

    func callAsFunction(_ input: MLXArray) throws -> MLXArray {
        try Task.checkCancellation()
        var x = input * Float(sqrt(Double(outputSize)))
        x = SenseVoicePositionEncoding.apply(to: x)
        for layer in firstLayers {
            try Task.checkCancellation()
            x = try layer(x)
        }
        for layer in layers {
            try Task.checkCancellation()
            x = try layer(x)
        }
        x = afterNorm(x)
        for layer in tpLayers {
            try Task.checkCancellation()
            x = try layer(x)
        }
        try Task.checkCancellation()
        return tpNorm(x)
    }
}

private enum SenseVoicePositionEncoding {
    static func apply(to input: MLXArray) -> MLXArray {
        let timeSteps = input.dim(1)
        guard timeSteps > 0 else { return input }

        let featureDimension = input.dim(2)
        let halfDimension = featureDimension / 2
        let increment = Float(log(10_000.0) / Double(max(halfDimension - 1, 1)))

        var values: [Float] = []
        values.reserveCapacity(timeSteps * featureDimension)
        for timeStep in 1 ... timeSteps {
            for dimension in 0 ..< halfDimension {
                let inverse = Foundation.exp(Float(dimension) * -increment)
                values.append(Foundation.sin(Float(timeStep) * inverse))
            }
            for dimension in 0 ..< halfDimension {
                let inverse = Foundation.exp(Float(dimension) * -increment)
                values.append(Foundation.cos(Float(timeStep) * inverse))
            }
        }

        return input + MLXArray(values, [1, timeSteps, featureDimension])
    }
}

private enum SenseVoiceFeatureExtractor {
    static func extract(
        samples: [Float],
        sampleRate: Int,
        configuration: SenseVoiceFrontendConfiguration,
        cmvnMeans: [Float],
        cmvnInverseStd: [Float]
    ) throws -> MLXArray {
        try Task.checkCancellation()
        let expectedSampleRate = configuration.sampleRate
        let normalizedSamples = sampleRate == expectedSampleRate
            ? samples
            : resampled(samples: samples, sourceSampleRate: sampleRate, targetSampleRate: expectedSampleRate)
        try Task.checkCancellation()

        let fbank = computeFbank(
            samples: normalizedSamples,
            sampleRate: expectedSampleRate,
            melCount: configuration.melCount,
            frameLengthMs: configuration.frameLength,
            frameShiftMs: configuration.frameShift,
            windowType: configuration.window
        )
        guard !fbank.isEmpty else {
            return MLXArray([Float](), [0, configuration.melCount * configuration.lfrM])
        }
        try Task.checkCancellation()

        let lfr = applyLFR(
            fbank: fbank,
            melCount: configuration.melCount,
            lfrM: configuration.lfrM,
            lfrN: configuration.lfrN
        )
        try Task.checkCancellation()
        let normalized = applyCMVN(lfr, means: cmvnMeans, inverseStd: cmvnInverseStd)
        let frameCount = normalized.count / (configuration.melCount * configuration.lfrM)
        return MLXArray(normalized, [frameCount, configuration.melCount * configuration.lfrM])
    }

    private static func resampled(
        samples: [Float],
        sourceSampleRate: Int,
        targetSampleRate: Int
    ) -> [Float] {
        guard sourceSampleRate > 0, targetSampleRate > 0, sourceSampleRate != targetSampleRate else {
            return samples
        }
        let outputCount = max(Int(round(Double(samples.count) * Double(targetSampleRate) / Double(sourceSampleRate))), 1)
        let step = Double(sourceSampleRate) / Double(targetSampleRate)
        return (0 ..< outputCount).map { index in
            let position = Double(index) * step
            let lower = min(Int(position), samples.count - 1)
            let upper = min(lower + 1, samples.count - 1)
            let fraction = Float(position - Double(lower))
            return samples[lower] + ((samples[upper] - samples[lower]) * fraction)
        }
    }

    private static func computeFbank(
        samples: [Float],
        sampleRate: Int,
        melCount: Int,
        frameLengthMs: Int,
        frameShiftMs: Int,
        windowType: String
    ) -> [Float] {
        let windowSize = Int(Double(sampleRate * frameLengthMs) * 0.001)
        let windowShift = Int(Double(sampleRate * frameShiftMs) * 0.001)
        guard windowSize > 0, windowShift > 0, samples.count >= windowSize else {
            return []
        }

        let paddedWindowSize = nextPowerOfTwo(windowSize)
        let frameCount = 1 + (samples.count - windowSize) / windowShift
        let window = makeWindow(type: windowType, size: windowSize)
        var frames = Array(repeating: Float(0), count: frameCount * paddedWindowSize)

        for frameIndex in 0 ..< frameCount {
            let start = frameIndex * windowShift
            let offset = frameIndex * paddedWindowSize
            var frame = Array(repeating: Float(0), count: windowSize)
            var mean: Float = 0

            for index in 0 ..< windowSize {
                let sample = samples[start + index] * Float(1 << 15)
                frame[index] = sample
                mean += sample
            }
            mean /= Float(windowSize)

            for index in 0 ..< windowSize {
                frame[index] -= mean
            }

            if windowSize > 1 {
                for index in stride(from: windowSize - 1, through: 1, by: -1) {
                    frame[index] -= 0.97 * frame[index - 1]
                }
            }

            for index in 0 ..< windowSize {
                frames[offset + index] = frame[index] * window[index]
            }
        }

        let frameArray = MLXArray(frames, [frameCount, paddedWindowSize])
        let fftResult = MLXFFT.rfft(frameArray, n: paddedWindowSize, axis: 1)
        let magnitude = MLX.abs(fftResult)
        let spectrum = magnitude * magnitude
        let melBanks = makeMelBanks(
            melCount: melCount,
            paddedWindowSize: paddedWindowSize,
            sampleRate: sampleRate,
            lowFrequency: 20,
            highFrequency: 0
        )
        let melMatrix = MLXArray(melBanks, [melCount, (paddedWindowSize / 2) + 1])
        let melFeatures = MLX.log(MLX.maximum(matmul(spectrum, melMatrix.T), Float(1e-8)))
        return melFeatures.asArray(Float.self)
    }

    private static func applyLFR(
        fbank: [Float],
        melCount: Int,
        lfrM: Int,
        lfrN: Int
    ) -> [Float] {
        let frameCount = fbank.count / melCount
        let lfrFrameCount = Int(ceil(Double(frameCount) / Double(lfrN)))
        let leftPadding = (lfrM - 1) / 2
        var output = Array(repeating: Float(0), count: lfrFrameCount * melCount * lfrM)

        for outputFrame in 0 ..< lfrFrameCount {
            for stackedFrame in 0 ..< lfrM {
                var sourceFrame = outputFrame * lfrN + stackedFrame - leftPadding
                if sourceFrame < 0 {
                    sourceFrame = 0
                } else if sourceFrame >= frameCount {
                    sourceFrame = frameCount - 1
                }

                let sourceOffset = sourceFrame * melCount
                let targetOffset = (outputFrame * melCount * lfrM) + (stackedFrame * melCount)
                output[targetOffset ..< targetOffset + melCount] = fbank[sourceOffset ..< sourceOffset + melCount]
            }
        }

        return output
    }

    private static func applyCMVN(
        _ features: [Float],
        means: [Float],
        inverseStd: [Float]
    ) -> [Float] {
        guard !means.isEmpty, means.count == inverseStd.count else {
            return features
        }
        let dimension = means.count
        return features.enumerated().map { index, value in
            let featureIndex = index % dimension
            return (value + means[featureIndex]) * inverseStd[featureIndex]
        }
    }

    private static func makeWindow(type: String, size: Int) -> [Float] {
        guard size > 1 else { return [1] }
        return (0 ..< size).map { index in
            let phase = 2 * Double.pi * Double(index) / Double(size - 1)
            switch type {
            case "hanning":
                return Float(0.5 - 0.5 * Foundation.cos(phase))
            case "povey":
                let hann = 0.5 - 0.5 * Foundation.cos(phase)
                return Float(Foundation.pow(hann, 0.85))
            case "rectangular":
                return 1
            default:
                return Float(0.54 - 0.46 * Foundation.cos(phase))
            }
        }
    }

    private static func makeMelBanks(
        melCount: Int,
        paddedWindowSize: Int,
        sampleRate: Int,
        lowFrequency: Double,
        highFrequency: Double
    ) -> [Float] {
        let fftBinCount = paddedWindowSize / 2
        let nyquist = 0.5 * Double(sampleRate)
        let high = highFrequency <= 0 ? highFrequency + nyquist : highFrequency
        let fftBinWidth = Double(sampleRate) / Double(paddedWindowSize)
        let lowMel = melScale(lowFrequency)
        let highMel = melScale(high)
        let melDelta = (highMel - lowMel) / Double(melCount + 1)
        var banks = Array(repeating: Float(0), count: melCount * (fftBinCount + 1))

        for melIndex in 0 ..< melCount {
            let leftMel = lowMel + Double(melIndex) * melDelta
            let centerMel = lowMel + Double(melIndex + 1) * melDelta
            let rightMel = lowMel + Double(melIndex + 2) * melDelta

            for fftIndex in 0 ..< fftBinCount {
                let mel = melScale(fftBinWidth * Double(fftIndex))
                let upSlope = (mel - leftMel) / (centerMel - leftMel)
                let downSlope = (rightMel - mel) / (rightMel - centerMel)
                banks[melIndex * (fftBinCount + 1) + fftIndex] = Float(max(0, min(upSlope, downSlope)))
            }
        }

        return banks
    }

    private static func melScale(_ frequency: Double) -> Double {
        1127 * Foundation.log(1 + frequency / 700)
    }

    private static func nextPowerOfTwo(_ value: Int) -> Int {
        guard value > 0 else { return 1 }
        var power = 1
        while power < value {
            power <<= 1
        }
        return power
    }
}

private enum SenseVoiceCMVN {
    static func load(from url: URL) throws -> (means: [Float], inverseStd: [Float]) {
        let text = try String(contentsOf: url, encoding: .utf8)
        let means = try values(after: "<AddShift>", in: text)
        let inverseStd = try values(after: "<Rescale>", in: text)
        return (means, inverseStd)
    }

    private static func values(after marker: String, in text: String) throws -> [Float] {
        guard let markerRange = text.range(of: marker),
              let openRange = text[markerRange.upperBound...].range(of: "["),
              let closeRange = text[openRange.upperBound...].range(of: "]") else {
            throw SenseVoiceNativeError.invalidConfiguration("missing CMVN values for \(marker)")
        }

        return text[openRange.upperBound ..< closeRange.lowerBound]
            .split(whereSeparator: \.isWhitespace)
            .compactMap { Float($0) }
    }
}

private struct SenseVoicePieceDecoder {
    private let pieces: [String]

    init(modelURL: URL) throws {
        pieces = try SenseVoiceSentencePieceModelParser.parsePieces(from: modelURL)
        guard !pieces.isEmpty else {
            throw SenseVoiceNativeError.invalidTokenizer
        }
    }

    func decode(_ tokenIDs: [Int32]) -> String {
        let joined = tokenIDs.compactMap { tokenID -> String? in
            let index = Int(tokenID)
            guard pieces.indices.contains(index) else {
                return nil
            }
            let piece = pieces[index]
            guard !piece.hasPrefix("<") || !piece.hasSuffix(">") else {
                return nil
            }
            return piece
        }.joined()

        return joined
            .replacingOccurrences(of: "▁", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

private enum SenseVoiceSentencePieceModelParser {
    static func parsePieces(from url: URL) throws -> [String] {
        let data = try Data(contentsOf: url)
        var reader = ProtobufReader(data: data)
        var pieces: [String] = []

        while !reader.isAtEnd {
            let tag = try reader.readVarint()
            let fieldNumber = Int(tag >> 3)
            let wireType = Int(tag & 0x7)

            if fieldNumber == 1, wireType == 2 {
                let message = try reader.readLengthDelimited()
                if let piece = try parsePieceMessage(message) {
                    pieces.append(piece)
                }
            } else {
                try reader.skip(wireType: wireType)
            }
        }

        return pieces
    }

    private static func parsePieceMessage(_ data: Data) throws -> String? {
        var reader = ProtobufReader(data: data)
        var piece: String?

        while !reader.isAtEnd {
            let tag = try reader.readVarint()
            let fieldNumber = Int(tag >> 3)
            let wireType = Int(tag & 0x7)

            if fieldNumber == 1, wireType == 2 {
                let bytes = try reader.readLengthDelimited()
                piece = String(data: bytes, encoding: .utf8)
            } else {
                try reader.skip(wireType: wireType)
            }
        }

        return piece
    }

    private struct ProtobufReader {
        let bytes: [UInt8]
        var offset: Int = 0

        init(data: Data) {
            bytes = Array(data)
        }

        var isAtEnd: Bool {
            offset >= bytes.count
        }

        mutating func readVarint() throws -> UInt64 {
            var result: UInt64 = 0
            var shift: UInt64 = 0

            while offset < bytes.count {
                let byte = UInt64(bytes[offset])
                offset += 1
                result |= (byte & 0x7f) << shift
                if byte & 0x80 == 0 {
                    return result
                }
                shift += 7
                if shift >= 64 {
                    throw SenseVoiceNativeError.invalidTokenizer
                }
            }

            throw SenseVoiceNativeError.invalidTokenizer
        }

        mutating func readLengthDelimited() throws -> Data {
            let length = Int(try readVarint())
            guard length >= 0, offset + length <= bytes.count else {
                throw SenseVoiceNativeError.invalidTokenizer
            }
            let start = offset
            offset += length
            return Data(bytes[start ..< offset])
        }

        mutating func skip(wireType: Int) throws {
            switch wireType {
            case 0:
                _ = try readVarint()
            case 1:
                offset += 8
            case 2:
                let length = Int(try readVarint())
                offset += length
            case 5:
                offset += 4
            default:
                throw SenseVoiceNativeError.invalidTokenizer
            }

            guard offset <= bytes.count else {
                throw SenseVoiceNativeError.invalidTokenizer
            }
        }
    }
}

private enum SenseVoicePCM {
    static func decodePCM16Mono(_ data: Data) -> [Float] {
        guard data.count >= 2 else { return [] }
        var samples: [Float] = []
        samples.reserveCapacity(data.count / 2)

        data.withUnsafeBytes { rawBuffer in
            let bytes = rawBuffer.bindMemory(to: UInt8.self)
            var index = 0
            while index + 1 < bytes.count {
                let raw = UInt16(bytes[index]) | (UInt16(bytes[index + 1]) << 8)
                let sample = Int16(bitPattern: raw)
                samples.append(max(-1, min(1, Float(sample) / 32768.0)))
                index += 2
            }
        }

        return samples
    }
}
