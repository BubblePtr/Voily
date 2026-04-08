import Foundation

struct QwenRealtimeASRResult: Equatable {
    let text: String
    let duration: TimeInterval
    let commandSummary: String
}

enum QwenRealtimeASRServiceError: LocalizedError {
    case missingBaseURL
    case missingAPIKey
    case missingModel
    case invalidBaseURL(String)
    case sessionNotStarted
    case connectionFailed(String)
    case serverError(String)
    case unexpectedClose(code: URLSessionWebSocketTask.CloseCode, reason: String)
    case emptyTranscript

    var errorDescription: String? {
        switch self {
        case .missingBaseURL:
            return "未配置阿里云实时 ASR 地址。"
        case .missingAPIKey:
            return "未配置阿里云 API Key。"
        case .missingModel:
            return "未配置阿里云实时 ASR 模型。"
        case let .invalidBaseURL(value):
            return "阿里云实时 ASR 地址无效：\(value)"
        case .sessionNotStarted:
            return "阿里云实时 ASR 会话尚未建立。"
        case let .connectionFailed(message):
            return "阿里云实时 ASR 连接失败：\(message)"
        case let .serverError(message):
            return "阿里云实时 ASR 返回错误：\(message)"
        case let .unexpectedClose(code, reason):
            return "阿里云实时 ASR 连接已关闭：\(code.rawValue) \(reason)"
        case .emptyTranscript:
            return "阿里云实时 ASR 未返回可用文本。"
        }
    }
}

actor QwenRealtimeASRService {
    private let session: URLSession
    private var webSocketTask: URLSessionWebSocketTask?
    private var onPartialText: (@Sendable (String) -> Void)?
    private var createdContinuation: CheckedContinuation<Void, Error>?
    private var finishContinuation: CheckedContinuation<QwenRealtimeASRResult, Error>?
    private var commandSummary = ""
    private var transcriptAccumulator = TranscriptAccumulator()
    private var finalStartedAt: Date?
    private var isFinishing = false

    init(session: URLSession = .shared) {
        self.session = session
    }

    func startSession(
        config: ASRProviderConfig,
        languageCode: String,
        onPartialText: @escaping @Sendable (String) -> Void
    ) async throws {
        try await cancelSession()

        let baseURL = config.baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !baseURL.isEmpty else { throw QwenRealtimeASRServiceError.missingBaseURL }
        guard let websocketBaseURL = URL(string: baseURL) else {
            throw QwenRealtimeASRServiceError.invalidBaseURL(baseURL)
        }

        let apiKey = config.apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !apiKey.isEmpty else { throw QwenRealtimeASRServiceError.missingAPIKey }

        let model = config.model.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !model.isEmpty else { throw QwenRealtimeASRServiceError.missingModel }

        guard var components = URLComponents(url: websocketBaseURL, resolvingAgainstBaseURL: false) else {
            throw QwenRealtimeASRServiceError.invalidBaseURL(baseURL)
        }
        components.queryItems = (components.queryItems ?? []) + [URLQueryItem(name: "model", value: model)]
        guard let websocketURL = components.url else {
            throw QwenRealtimeASRServiceError.invalidBaseURL(baseURL)
        }

        var request = URLRequest(url: websocketURL)
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("realtime=v1", forHTTPHeaderField: "OpenAI-Beta")

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
                    try await sendSessionUpdate(languageCode: languageCode)
                } catch {
                    await self.failAll(with: error)
                }
            }
        }
    }

    func appendAudioChunk(_ pcm16MonoData: Data) async throws {
        guard let webSocketTask else {
            throw QwenRealtimeASRServiceError.sessionNotStarted
        }
        guard !pcm16MonoData.isEmpty else { return }

        let payload: [String: Any] = [
            "event_id": UUID().uuidString,
            "type": "input_audio_buffer.append",
            "audio": pcm16MonoData.base64EncodedString(),
        ]
        try await sendJSON(payload, over: webSocketTask)
    }

    func finishSession() async throws -> QwenRealtimeASRResult {
        guard let webSocketTask else {
            throw QwenRealtimeASRServiceError.sessionNotStarted
        }

        finalStartedAt = Date()
        isFinishing = true

        return try await withCheckedThrowingContinuation { continuation in
            finishContinuation = continuation
            Task {
                do {
                    try await sendJSON([
                        "event_id": UUID().uuidString,
                        "type": "session.finish",
                    ], over: webSocketTask)
                } catch {
                    await self.failAll(with: error)
                }
            }
        }
    }

    func cancelSession() async throws {
        createdContinuation?.resume(throwing: QwenRealtimeASRServiceError.connectionFailed("会话已取消"))
        createdContinuation = nil
        finishContinuation?.resume(throwing: QwenRealtimeASRServiceError.connectionFailed("会话已取消"))
        finishContinuation = nil

        webSocketTask?.cancel(with: .goingAway, reason: nil)
        webSocketTask = nil
        onPartialText = nil
        commandSummary = ""
        transcriptAccumulator.reset()
        finalStartedAt = nil
        isFinishing = false
    }

    private func sendSessionUpdate(languageCode: String) async throws {
        guard let webSocketTask else {
            throw QwenRealtimeASRServiceError.sessionNotStarted
        }

        let payload: [String: Any] = [
            "event_id": UUID().uuidString,
            "type": "session.update",
            "session": [
                "modalities": ["text"],
                "input_audio_format": "pcm",
                "sample_rate": 16000,
                "input_audio_transcription": [
                    "language": Self.qwenLanguageCode(for: languageCode),
                ],
                "turn_detection": [
                    "type": "server_vad",
                    "threshold": 0.0,
                    "silence_duration_ms": 400,
                ],
            ],
        ]
        try await sendJSON(payload, over: webSocketTask)
    }

    private func sendJSON(_ payload: [String: Any], over task: URLSessionWebSocketTask) async throws {
        let data = try JSONSerialization.data(withJSONObject: payload)
        guard let text = String(data: data, encoding: .utf8) else {
            throw QwenRealtimeASRServiceError.connectionFailed("请求序列化失败")
        }
        try await task.send(.string(text))
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
        case let .string(text):
            data = Data(text.utf8)
        case let .data(binary):
            data = binary
        @unknown default:
            return
        }

        guard
            let object = try? JSONSerialization.jsonObject(with: data),
            let payload = object as? [String: Any],
            let type = payload["type"] as? String
        else {
            return
        }

        switch type {
        case "session.created", "session.updated":
            debugLog("Qwen realtime event type=\(type)")
            createdContinuation?.resume()
            createdContinuation = nil
        case "conversation.item.input_audio_transcription.text":
            guard let partial = Self.partialText(from: payload), !partial.isEmpty else { return }
            let displayText = transcriptAccumulator.updatePartial(partial)
            debugLog("Qwen realtime partial length=\(displayText.count)")
            onPartialText?(displayText)
        case "conversation.item.input_audio_transcription.completed":
            if let transcript = Self.finalTranscript(from: payload), !transcript.isEmpty {
                let committedText = transcriptAccumulator.commit(transcript)
                debugLog("Qwen realtime final length=\(committedText.count)")
            }
        case "session.finished":
            debugLog("Qwen realtime event type=session.finished")
            if let finishContinuation {
                let finalText = transcriptAccumulator.finalText
                if finalText.isEmpty {
                    finishContinuation.resume(throwing: QwenRealtimeASRServiceError.emptyTranscript)
                } else {
                    let duration = finalStartedAt.map { Date().timeIntervalSince($0) } ?? 0
                    finishContinuation.resume(returning: QwenRealtimeASRResult(
                        text: finalText,
                        duration: duration,
                        commandSummary: commandSummary
                    ))
                }
                self.finishContinuation = nil
            }
            try? await cancelSession()
        case "error":
            let message = Self.errorMessage(from: payload)
            debugLog("Qwen realtime error=\(message)")
            await failAll(with: QwenRealtimeASRServiceError.serverError(message))
        default:
            break
        }
    }

    private func handleReceiveFailure(_ error: Error) async {
        let finalText = transcriptAccumulator.finalText
        if isFinishing, !finalText.isEmpty, let finishContinuation {
            let duration = finalStartedAt.map { Date().timeIntervalSince($0) } ?? 0
            finishContinuation.resume(returning: QwenRealtimeASRResult(
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
            await failAll(with: QwenRealtimeASRServiceError.unexpectedClose(code: closeCode, reason: reason))
            return
        }

        await failAll(with: QwenRealtimeASRServiceError.connectionFailed(error.localizedDescription))
    }

    private func failAll(with error: Error) async {
        createdContinuation?.resume(throwing: error)
        createdContinuation = nil
        finishContinuation?.resume(throwing: error)
        finishContinuation = nil
        try? await cancelSession()
    }

    private static func partialText(from payload: [String: Any]) -> String? {
        if let value = stitchedText(from: payload) {
            return value
        }
        if let item = payload["item"] as? [String: Any], let value = stitchedText(from: item) {
            return value
        }
        if let transcript = payload["transcript"] as? String {
            return transcript
        }
        return nil
    }

    private static func finalTranscript(from payload: [String: Any]) -> String? {
        if let transcript = payload["transcript"] as? String {
            return transcript
        }
        if let item = payload["item"] as? [String: Any], let transcript = item["transcript"] as? String {
            return transcript
        }
        if let text = payload["text"] as? String {
            return text
        }
        return nil
    }

    private static func stitchedText(from object: [String: Any]) -> String? {
        let text = (object["text"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let stash = (object["stash"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)

        if !text.isEmpty, !stash.isEmpty {
            return text + stash
        }
        if !text.isEmpty {
            return text
        }
        if !stash.isEmpty {
            return stash
        }
        return nil
    }

    private static func errorMessage(from payload: [String: Any]) -> String {
        if let error = payload["error"] as? [String: Any] {
            if let message = error["message"] as? String, !message.isEmpty {
                return message
            }
            if let code = error["code"] as? String, !code.isEmpty {
                return code
            }
        }
        if let message = payload["message"] as? String, !message.isEmpty {
            return message
        }
        return "unknown error"
    }

    private static func qwenLanguageCode(for languageCode: String) -> String {
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
}
