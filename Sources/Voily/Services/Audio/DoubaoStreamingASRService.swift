import Foundation

struct DoubaoStreamingASRResult: Equatable {
    let text: String
    let duration: TimeInterval
    let commandSummary: String
}

enum DoubaoStreamingASRServiceError: LocalizedError {
    case missingBaseURL
    case missingAPIKey
    case missingResourceID
    case invalidResourceIDFormat(String)
    case unsupportedLanguage(String)
    case missingAppID
    case invalidBaseURL(String)
    case sessionNotStarted
    case invalidPacket
    case invalidResponse
    case serverError(Int, String)
    case connectionFailed(String)
    case unexpectedClose(code: URLSessionWebSocketTask.CloseCode, reason: String)
    case emptyTranscript

    var errorDescription: String? {
        switch self {
        case .missingBaseURL:
            return "未配置豆包实时 ASR 地址。"
        case .missingAPIKey:
            return "未配置豆包 Token。"
        case .missingResourceID:
            return "未配置豆包 Resource ID。"
        case let .invalidResourceIDFormat(value):
            return "豆包 Resource ID 格式不正确：\(value)。示例：volc.seedasr.sauc.duration"
        case let .unsupportedLanguage(value):
            return "豆包双向流式识别暂仅支持中文或英文输入：\(value)"
        case .missingAppID:
            return "未配置豆包 App ID。"
        case let .invalidBaseURL(value):
            return "豆包实时 ASR 地址无效：\(value)"
        case .sessionNotStarted:
            return "豆包实时 ASR 会话尚未建立。"
        case .invalidPacket:
            return "豆包实时 ASR 返回了无法解析的协议包。"
        case .invalidResponse:
            return "豆包实时 ASR 返回了无效响应。"
        case let .serverError(code, message):
            return "豆包实时 ASR 返回错误：[\(code)] \(message)"
        case let .connectionFailed(message):
            return "豆包实时 ASR 连接失败：\(message)"
        case let .unexpectedClose(code, reason):
            return "豆包实时 ASR 连接已关闭：\(code.rawValue) \(reason)"
        case .emptyTranscript:
            return "豆包实时 ASR 未返回可用文本。"
        }
    }
}

enum DoubaoWireCompression {
    case none

    fileprivate var nibble: UInt8 {
        switch self {
        case .none:
            return 0x0
        }
    }
}

struct DoubaoDecodedMessage: Equatable {
    let text: String?
    let resultText: String?
    let lastUtteranceText: String?
    let utteranceCount: Int
    let sequence: Int?
    let isDefinite: Bool
    let isFinal: Bool
    let code: Int?
    let message: String?

    var debugSummary: String {
        "sequence=\(sequence.map(String.init) ?? "nil") final=\(isFinal) definite=\(isDefinite) utteranceCount=\(utteranceCount) selectedTextLength=\(text?.count ?? 0) resultTextLength=\(resultText?.count ?? 0) lastUtteranceLength=\(lastUtteranceText?.count ?? 0) selectedTextPreview=\"\(Self.preview(text))\" resultTextPreview=\"\(Self.preview(resultText))\" lastUtterancePreview=\"\(Self.preview(lastUtteranceText))\""
    }

    private static func preview(_ text: String?) -> String {
        guard let text else { return "" }
        let normalized = text
            .replacingOccurrences(of: "\n", with: "\\n")
            .replacingOccurrences(of: "\r", with: "\\r")
        if normalized.count <= 24 {
            return normalized
        }
        let endIndex = normalized.index(normalized.startIndex, offsetBy: 24)
        return "\(normalized[..<endIndex])..."
    }
}

struct DoubaoPacketDiagnostics: Equatable {
    let byteCount: Int
    let protocolVersion: UInt8?
    let headerSizeUnits: UInt8?
    let headerSizeBytes: Int?
    let messageType: UInt8?
    let flags: UInt8?
    let serialization: UInt8?
    let compression: UInt8?
    let payloadSize: Int?
    let availablePayloadBytes: Int?
    let prefixHex: String
    let utf8Preview: String?

    var debugDescription: String {
        let version = protocolVersion.map(String.init) ?? "nil"
        let headerUnits = headerSizeUnits.map(String.init) ?? "nil"
        let headerBytes = headerSizeBytes.map(String.init) ?? "nil"
        let type = messageType.map { String(format: "0x%X", $0) } ?? "nil"
        let packetFlags = flags.map { String(format: "0x%X", $0) } ?? "nil"
        let packetSerialization = serialization.map { String(format: "0x%X", $0) } ?? "nil"
        let packetCompression = compression.map { String(format: "0x%X", $0) } ?? "nil"
        let size = payloadSize.map(String.init) ?? "nil"
        let available = availablePayloadBytes.map(String.init) ?? "nil"
        let preview = utf8Preview.map { "\"\($0)\"" } ?? "nil"
        return "bytes=\(byteCount) version=\(version) headerUnits=\(headerUnits) headerBytes=\(headerBytes) type=\(type) flags=\(packetFlags) serialization=\(packetSerialization) compression=\(packetCompression) payloadSize=\(size) availablePayloadBytes=\(available) prefixHex=\(prefixHex) utf8Preview=\(preview)"
    }
}

enum DoubaoWireCodec {
    private static let protocolVersion: UInt8 = 0x1
    private static let headerSizeUnits: UInt8 = 0x1

    static func makeFullRequestPacket(payload: Data, compression: DoubaoWireCompression) throws -> Data {
        try makePacket(
            messageType: 0x1,
            flags: 0x0,
            serialization: 0x1,
            compression: compression,
            payload: payload
        )
    }

    static func makeAudioPacket(audioData: Data, isFinal: Bool, compression: DoubaoWireCompression) throws -> Data {
        try makePacket(
            messageType: 0x2,
            flags: isFinal ? 0x2 : 0x0,
            serialization: 0x0,
            compression: compression,
            payload: audioData
        )
    }

    static func decodeServerMessage(_ data: Data) throws -> DoubaoDecodedMessage {
        guard data.count >= 8 else {
            throw DoubaoStreamingASRServiceError.invalidPacket
        }

        let header = [UInt8](data.prefix(4))
        let messageType = header[1] >> 4
        let flags = header[1] & 0x0F
        let serialization = header[2] >> 4

        switch messageType {
        case 0x9:
            let responseEnvelope = try decodeResponseEnvelope(data, flags: flags)
            guard serialization == 0x1 else {
                throw DoubaoStreamingASRServiceError.invalidPacket
            }
            return try decodeJSONResponse(
                responseEnvelope.payload,
                flags: flags,
                packetSequence: responseEnvelope.sequence
            )
        case 0xF:
            return try decodeErrorResponse(data, serialization: serialization)
        default:
            throw DoubaoStreamingASRServiceError.invalidPacket
        }
    }

    static func inspectServerMessage(_ data: Data) -> DoubaoPacketDiagnostics {
        let bytes = [UInt8](data)
        let prefixHex = bytes.prefix(24).map { String(format: "%02X", $0) }.joined(separator: " ")

        guard data.count >= 4 else {
            return DoubaoPacketDiagnostics(
                byteCount: data.count,
                protocolVersion: nil,
                headerSizeUnits: nil,
                headerSizeBytes: nil,
                messageType: nil,
                flags: nil,
                serialization: nil,
                compression: nil,
                payloadSize: nil,
                availablePayloadBytes: nil,
                prefixHex: prefixHex,
                utf8Preview: nil
            )
        }

        let header = [UInt8](data.prefix(4))
        let headerUnits = header[0] & 0x0F
        let headerBytes = Int(headerUnits) * 4
        let messageType = header[1] >> 4
        let payloadRange = payloadRangeForDiagnostics(data: data, messageType: messageType)
        let payloadPreview = payloadRange.flatMap { range in
            String(data: data.subdata(in: range), encoding: .utf8)?
                .replacingOccurrences(of: "\n", with: "\\n")
                .replacingOccurrences(of: "\r", with: "\\r")
        }
        return DoubaoPacketDiagnostics(
            byteCount: data.count,
            protocolVersion: header[0] >> 4,
            headerSizeUnits: headerUnits,
            headerSizeBytes: headerBytes,
            messageType: messageType,
            flags: header[1] & 0x0F,
            serialization: header[2] >> 4,
            compression: header[2] & 0x0F,
            payloadSize: payloadRange.map(\.count),
            availablePayloadBytes: payloadRange.map(\.count),
            prefixHex: prefixHex,
            utf8Preview: payloadPreview
        )
    }

    private static func makePacket(
        messageType: UInt8,
        flags: UInt8,
        serialization: UInt8,
        compression: DoubaoWireCompression,
        payload: Data
    ) throws -> Data {
        var packet = Data()
        packet.append((protocolVersion << 4) | headerSizeUnits)
        packet.append((messageType << 4) | flags)
        packet.append((serialization << 4) | compression.nibble)
        packet.append(0x00)

        var payloadSize = UInt32(payload.count).bigEndian
        withUnsafeBytes(of: &payloadSize) { packet.append(contentsOf: $0) }
        packet.append(payload)
        return packet
    }

    private static func decodeJSONResponse(
        _ payload: Data,
        flags: UInt8,
        packetSequence: Int32?
    ) throws -> DoubaoDecodedMessage {
        let response = try JSONDecoder().decode(DoubaoServerResponse.self, from: payload)
        let bestResult = response.result?.values.first
        let bestUtterance = bestResult?.utterances?.last
        let resultText = bestResult?.text
        let lastUtteranceText = bestUtterance?.text
        let text = resultText ?? lastUtteranceText
        let sequence = packetSequence.map(Int.init) ?? response.sequence ?? 0
        let isFinal = sequence < 0 || flags == 0x3 || flags == 0x2
        return DoubaoDecodedMessage(
            text: text?.trimmingCharacters(in: .whitespacesAndNewlines),
            resultText: resultText?.trimmingCharacters(in: .whitespacesAndNewlines),
            lastUtteranceText: lastUtteranceText?.trimmingCharacters(in: .whitespacesAndNewlines),
            utteranceCount: bestResult?.utterances?.count ?? 0,
            sequence: packetSequence.map(Int.init) ?? response.sequence,
            isDefinite: bestUtterance?.definite ?? isFinal,
            isFinal: isFinal,
            code: response.code,
            message: response.message
        )
    }

    private static func decodeResponseEnvelope(_ data: Data, flags: UInt8) throws -> (sequence: Int32?, payload: Data) {
        if flags == 0x0 {
            guard data.count >= 8 else {
                throw DoubaoStreamingASRServiceError.invalidPacket
            }
            let payloadSize = Int(readUInt32(from: data.subdata(in: 4 ..< 8)))
            guard data.count >= 8 + payloadSize else {
                throw DoubaoStreamingASRServiceError.invalidPacket
            }
            return (nil, data.subdata(in: 8 ..< 8 + payloadSize))
        }

        guard data.count >= 12 else {
            throw DoubaoStreamingASRServiceError.invalidPacket
        }
        let sequence = Int32(bitPattern: readUInt32(from: data.subdata(in: 4 ..< 8)))
        let payloadSize = Int(readUInt32(from: data.subdata(in: 8 ..< 12)))
        guard data.count >= 12 + payloadSize else {
            throw DoubaoStreamingASRServiceError.invalidPacket
        }
        return (sequence, data.subdata(in: 12 ..< 12 + payloadSize))
    }

    private static func decodeErrorResponse(_ data: Data, serialization: UInt8) throws -> DoubaoDecodedMessage {
        guard data.count >= 12 else {
            throw DoubaoStreamingASRServiceError.invalidPacket
        }

        let code = Int(readUInt32(from: data.subdata(in: 4 ..< 8)))
        let payloadSize = Int(readUInt32(from: data.subdata(in: 8 ..< 12)))
        guard data.count >= 12 + payloadSize else {
            throw DoubaoStreamingASRServiceError.invalidPacket
        }

        let payload = data.subdata(in: 12 ..< 12 + payloadSize)
        let message: String
        if serialization == 0x1 {
            message = String(data: payload, encoding: .utf8) ?? "unknown error"
        } else {
            message = payload.prefix(80).map { String(format: "%02X", $0) }.joined(separator: " ")
        }

        return DoubaoDecodedMessage(
            text: nil,
            resultText: nil,
            lastUtteranceText: nil,
            utteranceCount: 0,
            sequence: nil,
            isDefinite: false,
            isFinal: true,
            code: code,
            message: message
        )
    }

    private static func payloadRangeForDiagnostics(data: Data, messageType: UInt8) -> Range<Int>? {
        switch messageType {
        case 0x9:
            let flags = data.count >= 2 ? data[1] & 0x0F : 0x0
            if flags == 0x0 {
                guard data.count >= 8 else { return nil }
                let payloadSize = Int(readUInt32(from: data.subdata(in: 4 ..< 8)))
                guard data.count >= 8 + payloadSize else { return nil }
                return 8 ..< 8 + payloadSize
            }
            guard data.count >= 12 else { return nil }
            let payloadSize = Int(readUInt32(from: data.subdata(in: 8 ..< 12)))
            guard data.count >= 12 + payloadSize else { return nil }
            return 12 ..< 12 + payloadSize
        case 0xF:
            guard data.count >= 12 else { return nil }
            let payloadSize = Int(readUInt32(from: data.subdata(in: 8 ..< 12)))
            guard data.count >= 12 + payloadSize else { return nil }
            return 12 ..< 12 + payloadSize
        default:
            return nil
        }
    }

    private static func readUInt32(from data: Data) -> UInt32 {
        data.reduce(0) { partialResult, byte in
            (partialResult << 8) | UInt32(byte)
        }
    }
}

private struct DoubaoServerResponse: Decodable {
    struct ResultList: Decodable {
        let values: [Result]

        init(from decoder: Decoder) throws {
            let container = try decoder.singleValueContainer()
            if let single = try? container.decode(Result.self) {
                values = [single]
            } else {
                values = try container.decode([Result].self)
            }
        }
    }

    struct Result: Decodable {
        struct Utterance: Decodable {
            let text: String?
            let definite: Bool?
        }

        let text: String?
        let utterances: [Utterance]?
    }

    let code: Int?
    let message: String?
    let sequence: Int?
    let result: ResultList?
}

actor DoubaoStreamingASRService {
    private let session: URLSession
    private let compression: DoubaoWireCompression
    private var webSocketTask: URLSessionWebSocketTask?
    private var onPartialText: (@Sendable (String) -> Void)?
    private var createdContinuation: CheckedContinuation<Void, Error>?
    private var finishContinuation: CheckedContinuation<DoubaoStreamingASRResult, Error>?
    private var commandSummary = ""
    private var transcriptAccumulator = TranscriptAccumulator()
    private var finalStartedAt: Date?
    private var isFinishing = false

    init(session: URLSession = .shared, compression: DoubaoWireCompression = .none) {
        self.session = session
        self.compression = compression
    }

    func testConnection(config: ASRProviderConfig, languageCode: String) async throws {
        try await startSession(config: config, languageCode: languageCode) { _ in }
        try await cancelSession()
    }

    func startSession(
        config: ASRProviderConfig,
        languageCode: String,
        onPartialText: @escaping @Sendable (String) -> Void
    ) async throws {
        try await cancelSession()

        let baseURL = Self.normalizedSingleLineValue(config.baseURL)
        guard !baseURL.isEmpty else { throw DoubaoStreamingASRServiceError.missingBaseURL }
        guard let websocketURL = URL(string: baseURL) else {
            throw DoubaoStreamingASRServiceError.invalidBaseURL(baseURL)
        }

        let token = Self.normalizedSingleLineValue(config.apiKey)
        guard !token.isEmpty else { throw DoubaoStreamingASRServiceError.missingAPIKey }

        let resourceID = Self.normalizedSingleLineValue(config.model)
        guard !resourceID.isEmpty else { throw DoubaoStreamingASRServiceError.missingResourceID }
        guard resourceID.hasPrefix("volc.seedasr.sauc.") else {
            throw DoubaoStreamingASRServiceError.invalidResourceIDFormat(resourceID)
        }

        let appID = Self.normalizedSingleLineValue(config.appID)
        guard !appID.isEmpty else { throw DoubaoStreamingASRServiceError.missingAppID }

        var request = URLRequest(url: websocketURL)
        request.timeoutInterval = 15
        request.setValue(appID, forHTTPHeaderField: "X-Api-App-Key")
        request.setValue(token, forHTTPHeaderField: "X-Api-Access-Key")
        request.setValue(resourceID, forHTTPHeaderField: "X-Api-Resource-Id")
        request.setValue(UUID().uuidString, forHTTPHeaderField: "X-Api-Connect-Id")
        debugLog("Doubao realtime connect url=\(websocketURL.absoluteString) appID=\(appID) resourceID=\(resourceID) tokenLength=\(token.count)")

        let task = session.webSocketTask(with: request)
        webSocketTask = task
        self.onPartialText = onPartialText
        commandSummary = websocketURL.absoluteString
        transcriptAccumulator.reset()
        finalStartedAt = nil
        isFinishing = false

        task.resume()
        receiveNextMessage()

        try await withCheckedThrowingContinuation { continuation in
            createdContinuation = continuation
            Task {
                do {
                    let payload = try Self.makeStartRequestPayload(languageCode: languageCode)
                    let packet = try DoubaoWireCodec.makeFullRequestPacket(payload: payload, compression: compression)
                    try await task.send(.data(packet))
                } catch {
                    await self.failAll(with: error)
                }
            }
        }
    }

    func appendAudioChunk(_ pcm16MonoData: Data) async throws {
        guard let webSocketTask else {
            throw DoubaoStreamingASRServiceError.sessionNotStarted
        }
        guard !pcm16MonoData.isEmpty else { return }

        let packet = try DoubaoWireCodec.makeAudioPacket(
            audioData: pcm16MonoData,
            isFinal: false,
            compression: compression
        )
        try await webSocketTask.send(.data(packet))
    }

    func finishSession() async throws -> DoubaoStreamingASRResult {
        guard let webSocketTask else {
            throw DoubaoStreamingASRServiceError.sessionNotStarted
        }

        finalStartedAt = Date()
        isFinishing = true

        return try await withCheckedThrowingContinuation { continuation in
            finishContinuation = continuation
            Task {
                do {
                    let packet = try DoubaoWireCodec.makeAudioPacket(
                        audioData: Data(),
                        isFinal: true,
                        compression: compression
                    )
                    try await webSocketTask.send(.data(packet))
                } catch {
                    await self.failAll(with: error)
                }
            }
        }
    }

    func cancelSession() async throws {
        createdContinuation?.resume(throwing: DoubaoStreamingASRServiceError.connectionFailed("会话已取消"))
        createdContinuation = nil
        finishContinuation?.resume(throwing: DoubaoStreamingASRServiceError.connectionFailed("会话已取消"))
        finishContinuation = nil

        webSocketTask?.cancel(with: .goingAway, reason: nil)
        webSocketTask = nil
        onPartialText = nil
        commandSummary = ""
        transcriptAccumulator.reset()
        finalStartedAt = nil
        isFinishing = false
    }

    private func receiveNextMessage() {
        guard let webSocketTask else { return }
        Task {
            do {
                let message = try await webSocketTask.receive()
                await self.handle(message)
                self.receiveNextMessage()
            } catch {
                await self.handleReceiveFailure(error)
            }
        }
    }

    private func handle(_ message: URLSessionWebSocketTask.Message) async {
        let data: Data
        switch message {
        case let .data(binary):
            data = binary
            debugLog("Doubao realtime recv frame=data \(DoubaoWireCodec.inspectServerMessage(binary).debugDescription)")
        case let .string(text):
            data = Data(text.utf8)
            let preview = text.prefix(160)
                .replacingOccurrences(of: "\n", with: "\\n")
                .replacingOccurrences(of: "\r", with: "\\r")
            debugLog("Doubao realtime recv frame=string chars=\(text.count) preview=\"\(preview)\"")
        @unknown default:
            return
        }

        do {
            let decoded = try DoubaoWireCodec.decodeServerMessage(data)
            if let code = decoded.code, code != 1000, code != 20000000 {
                let message = decoded.message ?? "unknown error"
                await failAll(with: DoubaoStreamingASRServiceError.serverError(code, message))
                return
            }

            createdContinuation?.resume()
            createdContinuation = nil
            debugLog("Doubao realtime decoded \(decoded.debugSummary)")

            if let text = decoded.text, !text.isEmpty {
                let displayText = decoded.isDefinite
                    ? transcriptAccumulator.commit(text)
                    : transcriptAccumulator.updatePartial(text)
                debugLog("Doubao realtime partial length=\(displayText.count) final=\(decoded.isFinal)")
                onPartialText?(displayText)
            }

            if decoded.isFinal, let finishContinuation {
                let finalText = transcriptAccumulator.finalText
                if finalText.isEmpty {
                    finishContinuation.resume(throwing: DoubaoStreamingASRServiceError.emptyTranscript)
                } else {
                    let duration = finalStartedAt.map { Date().timeIntervalSince($0) } ?? 0
                    finishContinuation.resume(returning: DoubaoStreamingASRResult(
                        text: finalText,
                        duration: duration,
                        commandSummary: commandSummary
                    ))
                }
                self.finishContinuation = nil
                try? await cancelSession()
            }
        } catch {
            debugLog("Doubao realtime decode failed error=\(error.localizedDescription) \(DoubaoWireCodec.inspectServerMessage(data).debugDescription)")
            await failAll(with: error)
        }
    }

    private func handleReceiveFailure(_ error: Error) async {
        let finalText = transcriptAccumulator.finalText
        if isFinishing, !finalText.isEmpty, let finishContinuation {
            let duration = finalStartedAt.map { Date().timeIntervalSince($0) } ?? 0
            finishContinuation.resume(returning: DoubaoStreamingASRResult(
                text: finalText,
                duration: duration,
                commandSummary: commandSummary
            ))
            self.finishContinuation = nil
            try? await cancelSession()
            return
        }

        if let closeCode = webSocketTask?.closeCode, closeCode != .invalid {
            let reasonData = webSocketTask?.closeReason
            let reason = reasonData.flatMap { String(data: $0, encoding: .utf8) } ?? ""
            debugLog("Doubao realtime close code=\(closeCode.rawValue) reason=\(reason)")
            await failAll(with: DoubaoStreamingASRServiceError.unexpectedClose(code: closeCode, reason: reason))
            return
        }

        debugLog("Doubao realtime receive failed error=\(error.localizedDescription)")
        await failAll(with: DoubaoStreamingASRServiceError.connectionFailed(error.localizedDescription))
    }

    private func failAll(with error: Error) async {
        createdContinuation?.resume(throwing: error)
        createdContinuation = nil
        finishContinuation?.resume(throwing: error)
        finishContinuation = nil
        try? await cancelSession()
    }

    nonisolated static func normalizedSingleLineValue(_ rawValue: String) -> String {
        rawValue
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .first { !$0.isEmpty } ?? rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    nonisolated static func makeStartRequestPayload(languageCode: String) throws -> Data {
        try JSONSerialization.data(withJSONObject: [
            "user": [
                "uid": "voily-\(UUID().uuidString)",
            ],
            "audio": [
                "format": "pcm",
                "codec": "raw",
                "rate": 16_000,
                "bits": 16,
                "channel": 1,
                "language": try resolvedAudioLanguage(for: languageCode),
            ] as [String: Any],
            "request": [
                "model_name": "bigmodel",
                "enable_itn": true,
                "enable_punc": true,
                "enable_ddc": false,
            ],
        ])
    }

    nonisolated private static func resolvedAudioLanguage(for languageCode: String) throws -> String {
        let normalized = normalizedSingleLineValue(languageCode)
        if normalized.isEmpty || normalized.hasPrefix("zh") {
            return "zh-CN"
        }
        if normalized.hasPrefix("en") {
            return "en-US"
        }
        throw DoubaoStreamingASRServiceError.unsupportedLanguage(normalized)
    }
}
