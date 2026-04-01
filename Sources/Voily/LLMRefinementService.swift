import Foundation

struct RefinementRequest {
    let text: String
    let languageCode: String
}

final class LLMRefinementService {
    enum LLMError: Error {
        case invalidBaseURL
        case invalidResponse
    }

    @MainActor
    func refine(_ request: RefinementRequest, settings: AppSettings) async throws -> String {
        let trimmedBaseURL = settings.llmBaseURL.trimmingCharacters(in: .whitespacesAndNewlines)
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
        urlRequest.setValue("Bearer \(settings.llmAPIKey)", forHTTPHeaderField: "Authorization")

        let payload = ChatCompletionsRequest(
            model: settings.llmModel,
            messages: [
                .init(role: "system", content: Self.systemPrompt(languageCode: request.languageCode)),
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
        _ = try await refine(RefinementRequest(text: "测试 JSON 和 Python", languageCode: settings.selectedLanguageCode), settings: settings)
    }

    private static func systemPrompt(languageCode: String) -> String {
        """
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
