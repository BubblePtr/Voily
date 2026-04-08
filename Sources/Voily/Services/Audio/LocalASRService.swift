import AVFoundation
import Foundation

struct LocalASRCommand: Equatable {
    let executablePath: String
    let arguments: [String]
    let summary: String
}

struct LocalASRTranscriptionResult: Equatable {
    let text: String
    let duration: TimeInterval
    let commandSummary: String
}

enum LocalASRError: LocalizedError, Equatable {
    case unsupportedProvider
    case missingExecutablePath
    case missingModelPath
    case executableNotFound(String)
    case noAudioCaptured
    case failedToPrepareAudioFile(String)
    case processLaunchFailed(String)
    case processFailed(exitCode: Int32, stderr: String)
    case emptyTranscript

    var errorDescription: String? {
        switch self {
        case .unsupportedProvider:
            return "当前 provider 不支持本地 CLI 转写。"
        case .missingExecutablePath:
            return "未配置本地可执行文件路径。"
        case .missingModelPath:
            return "未配置本地模型文件路径。"
        case let .executableNotFound(path):
            return "本地可执行文件不可用：\(path)"
        case .noAudioCaptured:
            return "没有采集到可用于本地识别的音频。"
        case let .failedToPrepareAudioFile(message):
            return "写入临时音频文件失败：\(message)"
        case let .processLaunchFailed(message):
            return "启动本地转写进程失败：\(message)"
        case let .processFailed(exitCode, stderr):
            if stderr.isEmpty {
                return "本地转写进程退出码异常：\(exitCode)"
            }
            return "本地转写进程退出码异常：\(exitCode)，\(stderr)"
        case .emptyTranscript:
            return "本地模型未返回可用文本。"
        }
    }
}

struct LocalASRService: Sendable {
    func transcribe(
        provider: ASRProvider,
        config: ASRProviderConfig,
        audioFileURL: URL,
        languageCode: String
    ) async throws -> LocalASRTranscriptionResult {
        let command = try Self.makeCommand(
            provider: provider,
            config: config,
            audioFileURL: audioFileURL,
            languageCode: languageCode
        )

        debugLog("Local ASR launching provider=\(provider.rawValue) command=\(command.summary)")
        let startedAt = Date()
        let processResult = try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                do {
                    continuation.resume(returning: try Self.run(command: command))
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
        let duration = Date().timeIntervalSince(startedAt)

        if processResult.exitCode != 0 {
            let stderrSummary = Self.summarize(processResult.stderr)
            debugLog("Local ASR exited provider=\(provider.rawValue) code=\(processResult.exitCode) stderr=\(stderrSummary)")
            throw LocalASRError.processFailed(exitCode: processResult.exitCode, stderr: stderrSummary)
        }

        guard let text = Self.extractTranscript(stdout: processResult.stdout, stderr: processResult.stderr, provider: provider) else {
            let stdoutSummary = Self.summarize(processResult.stdout)
            let stderrSummary = Self.summarize(processResult.stderr)
            debugLog(
                "Local ASR returned empty transcript provider=\(provider.rawValue) stdout=\(stdoutSummary) stderr=\(stderrSummary)"
            )
            throw LocalASRError.emptyTranscript
        }

        debugLog("Local ASR succeeded provider=\(provider.rawValue) durationMs=\(Int(duration * 1000))")
        return LocalASRTranscriptionResult(text: text, duration: duration, commandSummary: command.summary)
    }

    static func makeCommand(
        provider: ASRProvider,
        config: ASRProviderConfig,
        audioFileURL: URL,
        languageCode: String
    ) throws -> LocalASRCommand {
        guard provider.category == .local else {
            throw LocalASRError.unsupportedProvider
        }

        let executablePath = config.executablePath.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !executablePath.isEmpty else {
            throw LocalASRError.missingExecutablePath
        }
        guard FileManager.default.isExecutableFile(atPath: executablePath) else {
            throw LocalASRError.executableNotFound(executablePath)
        }

        let modelPath = config.modelPath.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !modelPath.isEmpty else {
            throw LocalASRError.missingModelPath
        }

        let userArguments = tokenize(arguments: config.additionalArguments)
        let arguments: [String]
        switch provider {
        case .senseVoice:
            let defaultArguments = defaultSenseVoiceArguments(appending: userArguments)
            arguments = [
                "-m", modelPath,
                "-f", audioFileURL.path,
                "-l", senseVoiceLanguageCode(for: languageCode),
            ] + defaultArguments
        case .doubaoStreaming, .qwenASR:
            throw LocalASRError.unsupportedProvider
        }

        let summary = ([executablePath] + arguments).map(quoted).joined(separator: " ")
        return LocalASRCommand(executablePath: executablePath, arguments: arguments, summary: summary)
    }

    static func tokenize(arguments: String) -> [String] {
        var tokens: [String] = []
        var current = ""
        var quote: Character?
        var isEscaping = false

        for character in arguments {
            if isEscaping {
                current.append(character)
                isEscaping = false
                continue
            }

            if character == "\\" {
                isEscaping = true
                continue
            }

            if let currentQuote = quote, character == currentQuote {
                quote = nil
                continue
            }

            if quote == nil, character == "\"" || character == "'" {
                quote = character
                continue
            }

            if quote == nil, character.isWhitespace {
                if !current.isEmpty {
                    tokens.append(current)
                    current.removeAll(keepingCapacity: true)
                }
                continue
            }

            current.append(character)
        }

        if !current.isEmpty {
            tokens.append(current)
        }

        return tokens
    }

    private static func senseVoiceLanguageCode(for languageCode: String) -> String {
        if languageCode.hasPrefix("zh") {
            return "zh"
        }
        if languageCode.hasPrefix("ja") {
            return "ja"
        }
        if languageCode.hasPrefix("ko") {
            return "ko"
        }
        return "en"
    }

    private static func quoted(_ argument: String) -> String {
        if argument.isEmpty {
            return "\"\""
        }

        let needsQuotes = argument.contains(where: \.isWhitespace)
        if !needsQuotes {
            return argument
        }

        return "\"\(argument.replacingOccurrences(of: "\"", with: "\\\""))\""
    }

    private static func sanitizeTranscriptLine(_ line: String) -> String {
        let stripped = line
            .replacingOccurrences(of: #"^\[[^\]]+\]\s*"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: #"^(<\|[^>]+\|>\s*)+"#, with: "", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return stripped
    }

    private static func extractTranscript(stdout: String, stderr: String, provider: ASRProvider) -> String? {
        switch provider {
        case .senseVoice:
            let lines = senseVoiceTranscriptLines(stdout: stdout, stderr: stderr)
            guard !lines.isEmpty else { return nil }
            return lines.joined(separator: "\n")
        case .doubaoStreaming, .qwenASR:
            return nil
        }
    }

    private static func senseVoiceTranscriptLines(stdout: String, stderr: String) -> [String] {
        let primaryLines = senseVoiceCandidateLines(from: stdout)
        if !primaryLines.isEmpty {
            return primaryLines
        }
        return senseVoiceCandidateLines(from: stderr)
    }

    private static func senseVoiceCandidateLines(from output: String) -> [String] {
        output
            .split(whereSeparator: \.isNewline)
            .map { sanitizeTranscriptLine(String($0)) }
            .filter { !$0.isEmpty }
            .filter { !isSenseVoiceLogLine($0) }
    }

    private static func isSenseVoiceLogLine(_ line: String) -> Bool {
        let prefixes = [
            "sense_voice_",
            "ggml_",
            "system_info:",
            "main:",
            "error:",
            "usage:",
            "options:",
        ]
        if prefixes.contains(where: { line.hasPrefix($0) }) {
            return true
        }
        if line.hasPrefix("-") || line.hasPrefix("--") {
            return true
        }
        return false
    }

    private static func defaultSenseVoiceArguments(appending userArguments: [String]) -> [String] {
        var arguments: [String] = []
        if !userArguments.contains("-np") && !userArguments.contains("--no-prints") {
            arguments.append("-np")
        }
        if !userArguments.contains("-nt") && !userArguments.contains("--no-timestamps") {
            arguments.append("-nt")
        }
        return arguments + userArguments
    }

    private static func summarize(_ value: String) -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "" }
        let maxLength = 240
        if trimmed.count <= maxLength {
            return trimmed
        }
        return String(trimmed.prefix(maxLength)) + "..."
    }

    private static func run(command: LocalASRCommand) throws -> (stdout: String, stderr: String, exitCode: Int32) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: command.executablePath)
        process.arguments = command.arguments

        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        do {
            try process.run()
        } catch {
            throw LocalASRError.processLaunchFailed(error.localizedDescription)
        }

        process.waitUntilExit()

        let stdout = String(data: stdoutPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        let stderr = String(data: stderrPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        return (stdout, stderr, process.terminationStatus)
    }
}

final class TemporaryAudioCaptureWriter {
    private let lock = NSLock()
    private var fileURL: URL?
    private var sampleRate: Double?
    private var pcmData = Data()
    private var writeError: LocalASRError?

    func append(_ buffer: AVAudioPCMBuffer) {
        lock.lock()
        defer { lock.unlock() }

        guard writeError == nil else { return }

        do {
            if fileURL == nil {
                let temporaryURL = FileManager.default.temporaryDirectory
                    .appending(path: "voily-local-asr-\(UUID().uuidString)")
                    .appendingPathExtension("wav")
                fileURL = temporaryURL
                sampleRate = buffer.format.sampleRate
            }

            pcmData.append(try Self.pcm16MonoData(from: buffer))
        } catch {
            writeError = .failedToPrepareAudioFile(error.localizedDescription)
        }
    }

    static func pcm16MonoData(from buffer: AVAudioPCMBuffer) throws -> Data {
        try pcm16MonoData(from: buffer, targetSampleRate: buffer.format.sampleRate)
    }

    static func pcm16MonoData(from buffer: AVAudioPCMBuffer, targetSampleRate: Double) throws -> Data {
        var data = Data()
        if abs(buffer.format.sampleRate - targetSampleRate) > 1 {
            try appendResampledPCM16Samples(from: buffer, targetSampleRate: targetSampleRate, to: &data)
        } else {
            try appendPCM16Samples(from: buffer, to: &data)
        }
        return data
    }

    func finalize() throws -> URL {
        lock.lock()
        defer { lock.unlock() }

        if let writeError {
            cleanupLocked()
            throw writeError
        }

        guard let fileURL, let sampleRate, !pcmData.isEmpty else {
            throw LocalASRError.noAudioCaptured
        }

        do {
            try Self.writeCanonicalWAV(to: fileURL, sampleRate: sampleRate, pcmData: pcmData)
        } catch {
            cleanupLocked()
            throw LocalASRError.failedToPrepareAudioFile(error.localizedDescription)
        }

        return fileURL
    }

    func cancel() {
        lock.lock()
        defer { lock.unlock() }
        cleanupLocked()
    }

    private func cleanupLocked() {
        if let fileURL {
            try? FileManager.default.removeItem(at: fileURL)
        }
        fileURL = nil
        sampleRate = nil
        pcmData.removeAll(keepingCapacity: false)
        writeError = nil
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

        throw NSError(domain: "TemporaryAudioCaptureWriter", code: -1, userInfo: [
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
                append(int16Sample: Self.int16Sample(from: sample), to: &data)
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

        throw NSError(domain: "TemporaryAudioCaptureWriter", code: -1, userInfo: [
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

    private static func writeCanonicalWAV(to url: URL, sampleRate: Double, pcmData: Data) throws {
        let dataSize = UInt32(pcmData.count)
        let formatChunkSize: UInt32 = 16
        let riffChunkSize = UInt32(4 + (8 + formatChunkSize) + (8 + dataSize))
        let channels: UInt16 = 1
        let bitsPerSample: UInt16 = 16
        let sampleRateValue = UInt32(sampleRate.rounded())
        let byteRate = sampleRateValue * UInt32(channels) * UInt32(bitsPerSample / 8)
        let blockAlign = channels * (bitsPerSample / 8)

        var data = Data()
        data.append("RIFF".data(using: .ascii)!)
        append(value: riffChunkSize, to: &data)
        data.append("WAVE".data(using: .ascii)!)
        data.append("fmt ".data(using: .ascii)!)
        append(value: formatChunkSize, to: &data)
        append(value: UInt16(1), to: &data)
        append(value: channels, to: &data)
        append(value: sampleRateValue, to: &data)
        append(value: byteRate, to: &data)
        append(value: blockAlign, to: &data)
        append(value: bitsPerSample, to: &data)
        data.append("data".data(using: .ascii)!)
        append(value: dataSize, to: &data)
        data.append(pcmData)

        try data.write(to: url, options: .atomic)
    }

    private static func append<T: FixedWidthInteger>(value: T, to data: inout Data) {
        var littleEndianValue = value.littleEndian
        withUnsafeBytes(of: &littleEndianValue) { bytes in
            data.append(contentsOf: bytes)
        }
    }
}
