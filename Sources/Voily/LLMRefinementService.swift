import Foundation

enum TranslationOutputStyle: Equatable {
    case natural
}

enum TextProcessingMode: Equatable {
    case proofread
    case translateZhToEn(style: TranslationOutputStyle)
}

struct TextProcessingRequest: Equatable {
    let text: String
    let languageCode: String
    let mode: TextProcessingMode
}

final class LLMRefinementService {
    enum LLMError: Error {
        case invalidBaseURL
        case invalidResponse
    }

    @MainActor
    func process(_ request: TextProcessingRequest, settings: AppSettings) async throws -> String {
        let config = settings.selectedTextProviderConfig
        let trimmedBaseURL = config.baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let baseURL = URL(string: trimmedBaseURL) else {
            throw LLMError.invalidBaseURL
        }

        var endpoint = baseURL
        if endpoint.path.isEmpty || endpoint.path == "/" {
            endpoint.append(path: "chat/completions")
        }

        var urlRequest = URLRequest(url: endpoint)
        urlRequest.httpMethod = "POST"
        urlRequest.timeoutInterval = 15
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        urlRequest.setValue("Bearer \(config.apiKey)", forHTTPHeaderField: "Authorization")

        let payload = ChatCompletionsRequest(
            model: config.model,
            messages: [
                .init(
                    role: "system",
                    content: Self.systemPrompt(for: request, glossarySections: settings.effectiveGlossarySections)
                ),
                .init(role: "user", content: request.text),
            ],
            temperature: 0
        )

        urlRequest.httpBody = try JSONEncoder().encode(payload)
        let (data, response) = try await URLSession.shared.data(for: urlRequest)

        guard let httpResponse = response as? HTTPURLResponse, (200 ..< 300).contains(httpResponse.statusCode) else {
            throw LLMError.invalidResponse
        }

        let decoded = try JSONDecoder().decode(ChatCompletionsResponse.self, from: data)
        guard let content = decoded.choices.first?.message.content else {
            throw LLMError.invalidResponse
        }

        return content.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    @MainActor
    func testConnection(settings: AppSettings) async throws {
        _ = try await process(
            TextProcessingRequest(
                text: "测试 JSON 和 Python",
                languageCode: settings.selectedLanguageCode,
                mode: .proofread
            ),
            settings: settings
        )
    }

    static func systemPrompt(for request: TextProcessingRequest, glossarySections: [GlossarySection]) -> String {
        switch request.mode {
        case .proofread:
            return proofreadPrompt(languageCode: request.languageCode, glossarySections: glossarySections)
        case let .translateZhToEn(style):
            return translationPrompt(languageCode: request.languageCode, style: style)
        }
    }

    private static func proofreadPrompt(languageCode: String, glossarySections: [GlossarySection]) -> String {
        let basePrompt = """
        你是一个极其保守的语音识别纠错器。当前语言环境是 \(languageCode)。
        你的唯一任务是修复明显的语音识别错误，例如：
        1. 中文谐音识别错误。
        2. 英文技术术语被错误识别成中文音译，例如“配森”改为“Python”，“杰森”改为“JSON”。
        3. 明显的标点断句错误，但仅限于会影响原意理解时。

        严格规则：
        - 不要润色，不要改写，不要总结，不要扩写。
        - 不要删除任何看起来已经正确的内容。
        - 如果输入看起来正确，必须原样返回，保持字符顺序不变。
        - 只输出修正后的最终文本，不要附加解释或引号。
        """

        guard !glossarySections.isEmpty else {
            return basePrompt
        }

        let glossaryText = glossarySections
            .map { section in
                "\(section.title)：\(section.items.joined(separator: "、"))"
            }
            .joined(separator: "\n")

        return """
        \(basePrompt)

        词库参考：
        - 若输入中出现疑似专有术语、行业术语、近音错词，应优先参考以下标准写法。
        - 词库仅用于纠错参考，不代表可以改写原句或补充新内容。
        \(glossaryText)
        """
    }

    private static func translationPrompt(languageCode: String, style: TranslationOutputStyle) -> String {
        let styleInstruction: String
        switch style {
        case .natural:
            styleInstruction = "输出自然、简洁、可直接发送的英文，允许做轻微调整让表达自然，但不要扩写。"
        }

        return """
        你是一个语音输入翻译器。输入内容来自中文口述识别，当前输入语言环境是 \(languageCode)。
        你的唯一任务是把用户输入翻译成英文。

        严格规则：
        - 只输出英文最终结果。
        - 不要输出中文。
        - 不要输出双语内容。
        - 不要附加解释、注释、前缀、标题或引号。
        - 保留原意，不要总结，不要遗漏关键信息。
        - 如果口述内容不完整，尽量按原意输出最直接的英文，不要自行补充背景。
        - \(styleInstruction)
        """
    }
}

private struct ChatCompletionsRequest: Codable {
    struct Message: Codable {
        let role: String
        let content: String
    }

    let model: String
    let messages: [Message]
    let temperature: Double
}

private struct ChatCompletionsResponse: Codable {
    struct Choice: Codable {
        struct Message: Codable {
            let role: String
            let content: String
        }

        let message: Message
    }

    let choices: [Choice]
}
