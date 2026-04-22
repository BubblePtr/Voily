import Foundation

struct FunASRRealtimeASRResult: Equatable {
    let text: String
    let duration: TimeInterval
    let commandSummary: String
}

enum FunASRRealtimeServiceError: LocalizedError {
    case missingBaseURL
    case missingAPIKey
    case missingModel
    case invalidBaseURL(String)
    case sessionNotStarted
    case connectionFailed(String)
    case serverError(code: String?, message: String)
    case unexpectedClose(code: URLSessionWebSocketTask.CloseCode, reason: String)
    case emptyTranscript

    var errorDescription: String? {
        switch self {
        case .missingBaseURL:
            return "未配置 Fun-ASR 实时识别地址。"
        case .missingAPIKey:
            return "未配置 Fun-ASR API Key。"
        case .missingModel:
            return "未配置 Fun-ASR 实时识别模型。"
        case let .invalidBaseURL(value):
            return "Fun-ASR 实时识别地址无效：\(value)"
        case .sessionNotStarted:
            return "Fun-ASR 实时识别会话尚未建立。"
        case let .connectionFailed(message):
            return "Fun-ASR 实时识别连接失败：\(message)"
        case let .serverError(code, message):
            if let code, !code.isEmpty {
                return "Fun-ASR 实时识别返回错误：\(code) \(message)"
            }
            return "Fun-ASR 实时识别返回错误：\(message)"
        case let .unexpectedClose(code, reason):
            return "Fun-ASR 实时识别连接已关闭：\(code.rawValue) \(reason)"
        case .emptyTranscript:
            return "Fun-ASR 实时识别未返回可用文本。"
        }
    }
}

actor FunASRRealtimeService {
    private static let defaultMaxSentenceSilence = 1_300

    struct SentenceUpdate: Equatable {
        let text: String
        let sentenceEnd: Bool
        let heartbeat: Bool
    }

    struct TaskFailure: Equatable {
        let code: String?
        let message: String
    }

    private let session: URLSession
    private var webSocketTask: URLSessionWebSocketTask?
    private var taskID = ""
    private var onPartialText: (@Sendable (String) -> Void)?
    private var createdContinuation: CheckedContinuation<Void, Error>?
    private var finishContinuation: CheckedContinuation<FunASRRealtimeASRResult, Error>?
    private var commandSummary = ""
    private var transcriptAccumulator = TranscriptAccumulator()
    private var finalStartedAt: Date?
    private var isFinishing = false
    private var startTimeoutTask: Task<Void, Never>?
    private var finishTimeoutTask: Task<Void, Never>?

    init(session: URLSession = .shared) {
        self.session = session
    }

    func testConnection(config: ASRProviderConfig, languageCode: String) async throws {
        try await startSession(config: config.clearingFunASRVocabulary(), languageCode: languageCode) { _ in }
        try await cancelSession()
    }

    func startSession(
        config: ASRProviderConfig,
        languageCode: String,
        onPartialText: @escaping @Sendable (String) -> Void
    ) async throws {
        try await cancelSession()

        let baseURL = Self.normalizedSingleLineValue(config.baseURL)
        guard !baseURL.isEmpty else { throw FunASRRealtimeServiceError.missingBaseURL }
        guard let websocketURL = URL(string: baseURL) else {
            throw FunASRRealtimeServiceError.invalidBaseURL(baseURL)
        }

        let apiKey = Self.normalizedSingleLineValue(config.apiKey)
        guard !apiKey.isEmpty else { throw FunASRRealtimeServiceError.missingAPIKey }

        let model = Self.normalizedSingleLineValue(config.model)
        guard !model.isEmpty else { throw FunASRRealtimeServiceError.missingModel }
        let vocabularyID = Self.normalizedSingleLineValue(config.vocabularyID)

        var request = URLRequest(url: websocketURL)
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")

        let task = session.webSocketTask(with: request)
        webSocketTask = task
        taskID = Self.makeTaskID()
        self.onPartialText = onPartialText
        let sanitizedURL = Self.sanitizedURLString(websocketURL)
        commandSummary = vocabularyID.isEmpty
            ? "\(sanitizedURL) model=\(model)"
            : "\(sanitizedURL) model=\(model) vocabulary_id=\(vocabularyID)"
        transcriptAccumulator.reset()
        finalStartedAt = nil
        isFinishing = false

        task.resume()
        debugLog("Fun-ASR realtime connect url=\(sanitizedURL) model=\(model)")
        let receiveTaskID = taskID
        Task {
            await self.receiveNextMessage(taskID: receiveTaskID)
        }

        try await withCheckedThrowingContinuation { continuation in
            createdContinuation = continuation
            // `withCheckedThrowingContinuation`, `startTimeoutTask`, and the `sendControlMessage`
            // Task race only through this actor: `failAll` clears `createdContinuation`, and we
            // cancel `startTimeoutTask` right after the continuation resumes so no dangling timeout survives.
            startTimeoutTask = Task {
                try? await Task.sleep(for: .seconds(10))
                guard !Task.isCancelled else { return }
                await self.failAll(with: FunASRRealtimeServiceError.connectionFailed("建立会话超时"))
            }
            Task {
                do {
                    let payload = try Self.makeRunTaskMessage(
                        taskID: self.taskID,
                        model: model,
                        vocabularyID: vocabularyID.isEmpty ? nil : vocabularyID,
                        languageCode: languageCode
                    )
                    try await self.sendControlMessage(payload, over: task)
                } catch {
                    await self.failAll(with: error)
                }
            }
        }
        startTimeoutTask?.cancel()
        startTimeoutTask = nil
    }

    func appendAudioChunk(_ pcm16MonoData: Data) async throws {
        guard let webSocketTask else {
            throw FunASRRealtimeServiceError.sessionNotStarted
        }
        guard !pcm16MonoData.isEmpty else { return }

        debugLog("Fun-ASR realtime append bytes=\(pcm16MonoData.count)")
        try await webSocketTask.send(.data(pcm16MonoData))
    }

    func finishSession() async throws -> FunASRRealtimeASRResult {
        guard let webSocketTask else {
            throw FunASRRealtimeServiceError.sessionNotStarted
        }

        finalStartedAt = Date()
        isFinishing = true
        debugLog("Fun-ASR realtime finish requested")

        return try await withCheckedThrowingContinuation { continuation in
            finishContinuation = continuation
            finishTimeoutTask = Task {
                try? await Task.sleep(for: .seconds(10))
                guard !Task.isCancelled else { return }
                await self.failAll(with: FunASRRealtimeServiceError.connectionFailed("等待识别结果超时"))
            }
            Task {
                do {
                    let payload = try Self.makeFinishTaskMessage(taskID: self.taskID)
                    try await self.sendControlMessage(payload, over: webSocketTask)
                } catch {
                    await self.failAll(with: error)
                }
            }
        }
    }

    func cancelSession() async throws {
        startTimeoutTask?.cancel()
        startTimeoutTask = nil
        finishTimeoutTask?.cancel()
        finishTimeoutTask = nil

        createdContinuation?.resume(throwing: FunASRRealtimeServiceError.connectionFailed("会话已取消"))
        createdContinuation = nil
        finishContinuation?.resume(throwing: FunASRRealtimeServiceError.connectionFailed("会话已取消"))
        finishContinuation = nil

        webSocketTask?.cancel(with: .goingAway, reason: nil)
        webSocketTask = nil
        taskID = ""
        onPartialText = nil
        commandSummary = ""
        transcriptAccumulator.reset()
        finalStartedAt = nil
        isFinishing = false
    }

    private func sendControlMessage(_ data: Data, over task: URLSessionWebSocketTask) async throws {
        guard let text = String(data: data, encoding: .utf8) else {
            throw FunASRRealtimeServiceError.connectionFailed("请求序列化失败")
        }
        try await task.send(.string(text))
    }

    private func receiveNextMessage(taskID: String) async {
        guard taskID == self.taskID, let webSocketTask else { return }

        do {
            let message = try await webSocketTask.receive()
            guard taskID == self.taskID else { return }
            await handle(message)
            await receiveNextMessage(taskID: taskID)
        } catch {
            guard taskID == self.taskID else { return }
            await handleReceiveFailure(error)
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
            let header = payload["header"] as? [String: Any],
            let event = header["event"] as? String
        else {
            return
        }

        switch event {
        case "task-started":
            startTimeoutTask?.cancel()
            startTimeoutTask = nil
            debugLog("Fun-ASR realtime event type=task-started")
            createdContinuation?.resume()
            createdContinuation = nil
        case "result-generated":
            guard let update = Self.sentenceUpdate(from: payload), !update.heartbeat else { return }
            let trimmed = update.text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { return }

            if update.sentenceEnd {
                let committedText = transcriptAccumulator.commit(trimmed)
                debugLog("Fun-ASR realtime final-sentence length=\(committedText.count)")
                onPartialText?(committedText)
            } else {
                let displayText = transcriptAccumulator.updatePartial(trimmed)
                debugLog("Fun-ASR realtime partial length=\(displayText.count)")
                onPartialText?(displayText)
            }
        case "task-finished":
            finishTimeoutTask?.cancel()
            finishTimeoutTask = nil
            debugLog("Fun-ASR realtime event type=task-finished")
            if let finishContinuation {
                let finalText = transcriptAccumulator.finalText
                if finalText.isEmpty {
                    finishContinuation.resume(throwing: FunASRRealtimeServiceError.emptyTranscript)
                } else {
                    let duration = finalStartedAt.map { Date().timeIntervalSince($0) } ?? 0
                    finishContinuation.resume(returning: FunASRRealtimeASRResult(
                        text: finalText,
                        duration: duration,
                        commandSummary: commandSummary
                    ))
                }
                self.finishContinuation = nil
            }
            try? await cancelSession()
        case "task-failed":
            let failure = Self.taskFailure(from: payload)
            await failAll(with: FunASRRealtimeServiceError.serverError(
                code: failure?.code,
                message: failure?.message ?? "任务失败"
            ))
        case "error":
            let failure = Self.taskFailure(from: payload)
            await failAll(with: FunASRRealtimeServiceError.serverError(
                code: failure?.code,
                message: failure?.message ?? "任务失败"
            ))
        default:
            break
        }
    }

    private func handleReceiveFailure(_ error: Error) async {
        let finalText = transcriptAccumulator.finalText
        if isFinishing, !finalText.isEmpty, let finishContinuation {
            let duration = finalStartedAt.map { Date().timeIntervalSince($0) } ?? 0
            finishContinuation.resume(returning: FunASRRealtimeASRResult(
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
            await failAll(with: FunASRRealtimeServiceError.unexpectedClose(code: closeCode, reason: reason))
            return
        }

        await failAll(with: FunASRRealtimeServiceError.connectionFailed(error.localizedDescription))
    }

    private func failAll(with error: Error) async {
        startTimeoutTask?.cancel()
        startTimeoutTask = nil
        finishTimeoutTask?.cancel()
        finishTimeoutTask = nil

        let createdContinuation = createdContinuation
        let finishContinuation = finishContinuation
        self.createdContinuation = nil
        self.finishContinuation = nil

        createdContinuation?.resume(throwing: error)
        finishContinuation?.resume(throwing: error)
        try? await cancelSession()
    }

    static func makeRunTaskMessage(
        taskID: String,
        model: String,
        vocabularyID: String?,
        languageCode: String
    ) throws -> Data {
        var parameters: [String: Any] = [
            "format": "pcm",
            "sample_rate": 16_000,
            "semantic_punctuation_enabled": false,
            "max_sentence_silence": defaultMaxSentenceSilence,
        ]
        if let vocabularyID, !vocabularyID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            parameters["vocabulary_id"] = vocabularyID
        }
        if let languageHint = funASRLanguageHint(for: languageCode) {
            parameters["language_hints"] = [languageHint]
        }

        let payload: [String: Any] = [
            "header": [
                "action": "run-task",
                "task_id": taskID,
                "streaming": "duplex",
            ],
            "payload": [
                "task_group": "audio",
                "task": "asr",
                "function": "recognition",
                "model": model,
                "parameters": parameters,
                "input": [:],
            ],
        ]
        return try JSONSerialization.data(withJSONObject: payload)
    }

    static func makeFinishTaskMessage(taskID: String) throws -> Data {
        let payload: [String: Any] = [
            "header": [
                "action": "finish-task",
                "task_id": taskID,
                "streaming": "duplex",
            ],
            "payload": [
                "input": [:],
            ],
        ]
        return try JSONSerialization.data(withJSONObject: payload)
    }

    static func sentenceUpdate(from payload: [String: Any]) -> SentenceUpdate? {
        guard
            let header = payload["header"] as? [String: Any],
            (header["event"] as? String) == "result-generated",
            let body = payload["payload"] as? [String: Any],
            let output = body["output"] as? [String: Any],
            let sentence = output["sentence"] as? [String: Any],
            let text = sentence["text"] as? String
        else {
            return nil
        }

        return SentenceUpdate(
            text: text,
            sentenceEnd: sentence["sentence_end"] as? Bool ?? false,
            heartbeat: sentence["heartbeat"] as? Bool ?? false
        )
    }

    static func taskFailure(from payload: [String: Any]) -> TaskFailure? {
        guard let header = payload["header"] as? [String: Any] else {
            return nil
        }

        let code = header["error_code"] as? String
        let message = (header["error_message"] as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines)

        if let message, !message.isEmpty {
            return TaskFailure(code: code, message: message)
        }

        if
            let body = payload["payload"] as? [String: Any],
            let message = body["message"] as? String,
            !message.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        {
            return TaskFailure(code: code, message: message)
        }

        return nil
    }

    static func normalizedSingleLineValue(_ value: String) -> String {
        value
            .split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .first(where: { !$0.isEmpty }) ?? ""
    }

    static func sanitizedURLString(_ url: URL) -> String {
        var components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        components?.query = nil
        return components?.string ?? url.absoluteString
    }

    static func funASRLanguageHint(for languageCode: String) -> String? {
        switch SupportedLanguage(rawValue: languageCode) {
        case .english:
            return "en"
        case .simplifiedChinese, .traditionalChinese:
            return "zh"
        case .japanese:
            return "ja"
        case .korean:
            return "ko"
        case .none:
            return nil
        }
    }

    private static func makeTaskID() -> String {
        UUID().uuidString.replacingOccurrences(of: "-", with: "")
    }
}
