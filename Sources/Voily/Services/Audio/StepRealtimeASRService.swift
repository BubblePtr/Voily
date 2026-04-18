import Foundation

struct StepRealtimeASRResult: Equatable {
    let text: String
    let duration: TimeInterval
    let commandSummary: String
}

enum StepRealtimeASRServiceError: LocalizedError {
    case missingBaseURL
    case missingAPIKey
    case missingModel
    case unsupportedLanguage(String)
    case finishTimedOut(Duration)
    case invalidBaseURL(String)
    case sessionNotStarted
    case connectionFailed(String)
    case serverError(String)
    case unexpectedClose(code: URLSessionWebSocketTask.CloseCode, reason: String)
    case emptyTranscript

    var errorDescription: String? {
        switch self {
        case .missingBaseURL:
            return "未配置跃阶星辰实时 ASR 地址。"
        case .missingAPIKey:
            return "未配置跃阶星辰 API Key。"
        case .missingModel:
            return "未配置跃阶星辰实时 ASR 模型。"
        case let .unsupportedLanguage(value):
            return "跃阶星辰流式识别当前仅支持中文或英文输入：\(value)"
        case let .finishTimedOut(timeout):
            let seconds = Double(timeout.components.seconds) + (Double(timeout.components.attoseconds) / 1_000_000_000_000_000_000)
            return String(format: "跃阶星辰实时 ASR 在 %.2f 秒内未返回最终结果。", seconds)
        case let .invalidBaseURL(value):
            return "跃阶星辰实时 ASR 地址无效：\(value)"
        case .sessionNotStarted:
            return "跃阶星辰实时 ASR 会话尚未建立。"
        case let .connectionFailed(message):
            return "跃阶星辰实时 ASR 连接失败：\(message)"
        case let .serverError(message):
            return "跃阶星辰实时 ASR 返回错误：\(message)"
        case let .unexpectedClose(code, reason):
            return "跃阶星辰实时 ASR 连接已关闭：\(code.rawValue) \(reason)"
        case .emptyTranscript:
            return "跃阶星辰实时 ASR 未返回可用文本。"
        }
    }
}

actor StepRealtimeASRService {
    private static let finishTimeout: Duration = .seconds(5)
    private let session: URLSession
    private var webSocketTask: URLSessionWebSocketTask?
    private var onPartialText: (@Sendable (String) -> Void)?
    private var createdContinuation: CheckedContinuation<Void, Error>?
    private var finishContinuation: CheckedContinuation<StepRealtimeASRResult, Error>?
    private var commandSummary = ""
    private var transcriptAccumulator = TranscriptAccumulator()
    private var finalStartedAt: Date?
    private var isFinishing = false

    init(session: URLSession = .shared) {
        self.session = session
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
        guard !baseURL.isEmpty else { throw StepRealtimeASRServiceError.missingBaseURL }
        guard let websocketURL = URL(string: baseURL) else {
            throw StepRealtimeASRServiceError.invalidBaseURL(baseURL)
        }

        let apiKey = Self.normalizedSingleLineValue(config.apiKey)
        guard !apiKey.isEmpty else { throw StepRealtimeASRServiceError.missingAPIKey }

        let model = Self.normalizedSingleLineValue(config.model)
        guard !model.isEmpty else { throw StepRealtimeASRServiceError.missingModel }

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
        debugLog("Step realtime connect url=\(websocketURL.absoluteString)")
        receiveNextMessage()

        try await withCheckedThrowingContinuation { continuation in
            createdContinuation = continuation
            Task {
                do {
                    let payload = try Self.makeSessionUpdatePayload(model: model, languageCode: languageCode)
                    debugLog("Step realtime session.update payload=\(Self.jsonPreview(payload))")
                    try await self.sendJSONData(payload, over: task)
                } catch {
                    await self.failAll(with: error)
                }
            }
        }
    }

    func appendAudioChunk(_ pcm16MonoData: Data) async throws {
        guard let webSocketTask else {
            throw StepRealtimeASRServiceError.sessionNotStarted
        }
        guard !pcm16MonoData.isEmpty else { return }

        let payload: [String: Any] = [
            "event_id": UUID().uuidString,
            "type": "input_audio_buffer.append",
            "audio": pcm16MonoData.base64EncodedString(),
        ]
        debugLog("Step realtime append bytes=\(pcm16MonoData.count)")
        try await sendJSON(payload, over: webSocketTask)
    }

    func finishSession() async throws -> StepRealtimeASRResult {
        guard let webSocketTask else {
            throw StepRealtimeASRServiceError.sessionNotStarted
        }

        finalStartedAt = Date()
        isFinishing = true

        debugLog("Step realtime finish requested")
        let resultTask = Task { [self] in
            try await self.awaitFinishResult()
        }

        do {
            try await self.sendJSON([
                "event_id": UUID().uuidString,
                "type": "input_audio_buffer.commit",
            ], over: webSocketTask)
            debugLog("Step realtime commit sent")
            return try await Self.withTimeout(Self.finishTimeout) {
                try await resultTask.value
            }
        } catch {
            resultTask.cancel()
            if case StepRealtimeASRServiceError.finishTimedOut = error {
                await failAll(with: error)
            }
            throw error
        }
    }

    func cancelSession() async throws {
        createdContinuation?.resume(throwing: StepRealtimeASRServiceError.connectionFailed("会话已取消"))
        createdContinuation = nil
        finishContinuation?.resume(throwing: StepRealtimeASRServiceError.connectionFailed("会话已取消"))
        finishContinuation = nil

        webSocketTask?.cancel(with: .goingAway, reason: nil)
        webSocketTask = nil
        onPartialText = nil
        commandSummary = ""
        transcriptAccumulator.reset()
        finalStartedAt = nil
        isFinishing = false
    }

    private func sendJSON(_ payload: [String: Any], over task: URLSessionWebSocketTask) async throws {
        let data = try JSONSerialization.data(withJSONObject: payload)
        try await sendJSONData(data, over: task)
    }

    private func sendJSONData(_ data: Data, over task: URLSessionWebSocketTask) async throws {
        guard let text = String(data: data, encoding: .utf8) else {
            throw StepRealtimeASRServiceError.connectionFailed("请求序列化失败")
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
            debugLog("Step realtime event type=\(type)")
            if type == "session.updated" {
                debugLog("Step realtime session.updated summary=\(Self.sessionSummary(from: payload))")
            }
            createdContinuation?.resume()
            createdContinuation = nil
        case "input_audio_buffer.committed", "input_audio_buffer.cleared":
            debugLog("Step realtime event type=\(type)")
        case "input_audio_buffer.speech_started", "input_audio_buffer.speech_stopped":
            debugLog("Step realtime event type=\(type)")
        case "conversation.item.created":
            debugLog("Step realtime event type=conversation.item.created")
        case "conversation.item.input_audio_transcription.delta":
            guard let partial = Self.partialText(from: payload), !partial.isEmpty else { return }
            let displayText = transcriptAccumulator.appendDelta(partial)
            debugLog("Step realtime partial length=\(displayText.count)")
            onPartialText?(displayText)
        case "conversation.item.input_audio_transcription.completed":
            if let transcript = Self.finalTranscript(from: payload), !transcript.isEmpty {
                let committedText = transcriptAccumulator.commit(transcript)
                debugLog("Step realtime final length=\(committedText.count)")
            }

            if isFinishing, let finishContinuation {
                let finalText = transcriptAccumulator.finalText
                if finalText.isEmpty {
                    finishContinuation.resume(throwing: StepRealtimeASRServiceError.emptyTranscript)
                } else {
                    let duration = finalStartedAt.map { Date().timeIntervalSince($0) } ?? 0
                    finishContinuation.resume(returning: StepRealtimeASRResult(
                        text: finalText,
                        duration: duration,
                        commandSummary: commandSummary
                    ))
                }
                self.finishContinuation = nil
                try? await cancelSession()
            }
        case "conversation.item.input_audio_transcription.failed":
            let message = Self.errorMessage(from: payload)
            debugLog("Step realtime transcription failed error=\(message)")
            await failAll(with: StepRealtimeASRServiceError.serverError(message))
        case "error":
            let message = Self.errorMessage(from: payload)
            debugLog("Step realtime error=\(message)")
            await failAll(with: StepRealtimeASRServiceError.serverError(message))
        default:
            debugLog("Step realtime unhandled event type=\(type)")
            break
        }
    }

    private func handleReceiveFailure(_ error: Error) async {
        let finalText = transcriptAccumulator.finalText
        if isFinishing, !finalText.isEmpty, let finishContinuation {
            let duration = finalStartedAt.map { Date().timeIntervalSince($0) } ?? 0
            finishContinuation.resume(returning: StepRealtimeASRResult(
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
            debugLog("Step realtime close code=\(closeCode.rawValue) reason=\(reason)")
            await failAll(with: StepRealtimeASRServiceError.unexpectedClose(code: closeCode, reason: reason))
            return
        }

        debugLog("Step realtime receive failure error=\(error.localizedDescription)")
        await failAll(with: StepRealtimeASRServiceError.connectionFailed(error.localizedDescription))
    }

    private func failAll(with error: Error) async {
        debugLog("Step realtime failAll error=\(error.localizedDescription)")
        createdContinuation?.resume(throwing: error)
        createdContinuation = nil
        finishContinuation?.resume(throwing: error)
        finishContinuation = nil
        try? await cancelSession()
    }

    static func makeSessionUpdatePayload(model: String, languageCode: String) throws -> Data {
        let normalizedLanguageCode = try stepLanguageCode(for: languageCode)
        let payload: [String: Any] = [
            "event_id": UUID().uuidString,
            "type": "session.update",
            "session": [
                "audio": [
                    "input": [
                        "format": [
                            "type": "pcm",
                            "codec": "pcm_s16le",
                            "rate": 16_000,
                            "bits": 16,
                            "channel": 1,
                        ],
                        "transcription": [
                            "model": model,
                            "language": normalizedLanguageCode,
                            "prompt": "请记录下你所听到的语音内容。",
                            "full_rerun_on_commit": true,
                            "enable_itn": true,
                        ],
                    ],
                ],
            ],
        ]
        return try JSONSerialization.data(withJSONObject: payload)
    }

    static func partialText(from payload: [String: Any]) -> String? {
        if let text = payload["text"] as? String {
            return text.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return (payload["delta"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func finalTranscript(from payload: [String: Any]) -> String? {
        if let transcript = payload["transcript"] as? String {
            return transcript.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        if let item = payload["item"] as? [String: Any],
           let transcript = item["transcript"] as? String {
            return transcript.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return nil
    }

    static func normalizedSingleLineValue(_ value: String) -> String {
        value
            .split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .first(where: { !$0.isEmpty }) ?? value.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func awaitFinishResult() async throws -> StepRealtimeASRResult {
        try await withCheckedThrowingContinuation { continuation in
            finishContinuation = continuation
        }
    }

    static func withTimeout<T: Sendable>(
        _ timeout: Duration,
        operation: @escaping @Sendable () async throws -> T
    ) async throws -> T {
        try await withThrowingTaskGroup(of: T.self) { group in
            group.addTask {
                try await operation()
            }
            group.addTask {
                try await Task.sleep(for: timeout)
                throw StepRealtimeASRServiceError.finishTimedOut(timeout)
            }

            let result = try await group.next()!
            group.cancelAll()
            return result
        }
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
        if let item = payload["item"] as? [String: Any],
           let error = item["error"] as? [String: Any],
           let message = error["message"] as? String,
           !message.isEmpty
        {
            return message
        }
        return "unknown error"
    }

    private static func stepLanguageCode(for languageCode: String) throws -> String {
        if languageCode.hasPrefix("zh") {
            return "zh"
        }
        if languageCode.hasPrefix("en") {
            return "en"
        }
        throw StepRealtimeASRServiceError.unsupportedLanguage(languageCode)
    }

    private static func jsonPreview(_ data: Data) -> String {
        guard let text = String(data: data, encoding: .utf8) else {
            return "<non-utf8>"
        }
        return text.count > 400 ? String(text.prefix(400)) + "..." : text
    }

    private static func sessionSummary(from payload: [String: Any]) -> String {
        guard
            let session = payload["session"] as? [String: Any],
            let audio = session["audio"] as? [String: Any],
            let input = audio["input"] as? [String: Any]
        else {
            return "missing-session"
        }

        let language = ((input["transcription"] as? [String: Any])?["language"] as? String) ?? "<nil>"
        let model = ((input["transcription"] as? [String: Any])?["model"] as? String) ?? "<nil>"
        let format = (input["format"] as? [String: Any]) ?? [:]
        let rate = (format["rate"] as? Int).map(String.init) ?? "<nil>"
        let codec = (format["codec"] as? String) ?? "<nil>"
        let hasTurnDetection = input["turn_detection"] != nil
        return "language=\(language) model=\(model) codec=\(codec) rate=\(rate) turnDetection=\(hasTurnDetection)"
    }
}
