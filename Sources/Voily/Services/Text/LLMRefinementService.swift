import Foundation

enum TranslationOutputStyle: Equatable {
    case natural
}

enum TextProcessingMode: Equatable {
    case dictation(skills: [DictationProcessingSkill])
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
        let provider = settings.selectedTextProvider
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
            temperature: 0,
            thinking: Self.thinkingMode(for: provider)
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

        return Self.normalizedResponseText(content, provider: provider)
    }

    @MainActor
    func testConnection(settings: AppSettings) async throws {
        _ = try await process(
            TextProcessingRequest(
                text: "测试 JSON 和 Python",
                languageCode: settings.selectedLanguageCode,
                mode: .dictation(skills: settings.enabledDictationSkills)
            ),
            settings: settings
        )
    }

    static func systemPrompt(for request: TextProcessingRequest, glossarySections: [GlossarySection]) -> String {
        switch request.mode {
        case let .dictation(skills):
            return dictationPrompt(languageCode: request.languageCode, skills: skills, glossarySections: glossarySections)
        case let .translateZhToEn(style):
            return translationPrompt(languageCode: request.languageCode, style: style)
        }
    }

    static func normalizedResponseText(_ text: String, provider: TextRefinementProvider? = nil) -> String {
        let output = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard shouldStripLeadingThinkBlock(for: provider),
              let range = leadingThinkBlockRange(in: output)
        else {
            return output
        }

        let suffix = output[range.upperBound...].trimmingCharacters(in: .whitespacesAndNewlines)
        return suffix.isEmpty ? output : suffix
    }

    private static func shouldStripLeadingThinkBlock(for provider: TextRefinementProvider?) -> Bool {
        provider != nil
    }

    private static func thinkingMode(for provider: TextRefinementProvider) -> ChatCompletionsRequest.Thinking? {
        switch provider {
        case .deepSeek:
            return .init(type: "disabled")
        case .dashScope, .volcengine, .minimax, .kimi, .zhipu:
            return nil
        }
    }

    private static func leadingThinkBlockRange(in text: String) -> Range<String.Index>? {
        text.range(
            of: #"(?is)^\s*<think>.*?</think>"#,
            options: .regularExpression
        )
    }

    private static func dictationPrompt(
        languageCode: String,
        skills: [DictationProcessingSkill],
        glossarySections: [GlossarySection]
    ) -> String {
        let normalizedSkills = normalized(skills)
        let basePrompt = """
        你是一个语音识别后处理器。输入内容来自普通听写识别，当前语言环境是 \(languageCode)。
        你必须严格按顺序执行以下任务。

        第 1 步：基础纠错。
        只修复明显的语音识别错误，例如：
        1. 中文谐音识别错误。
        2. 英文技术术语被错误识别成中文音译，例如“配森”改为“Python”，“杰森”改为“JSON”。
        3. 明显的标点断句错误，但仅限于会影响原意理解时。

        严格规则：
        - 第 1 步只做保守纠错，不要顺便润色、总结或扩写。
        - 不要删除任何看起来已经正确的内容。
        - 如果输入看起来正确，且后续没有启用相关技能，必须尽量保持原意和信息量不变。
        - 只输出修正后的最终文本，不要附加解释或引号。
        """

        let skillPrompt = skillInstructions(for: normalizedSkills)
        let promptWithSkills = skillPrompt.isEmpty ? basePrompt : "\(basePrompt)\n\n\(skillPrompt)"

        guard !glossarySections.isEmpty else {
            return promptWithSkills
        }

        let glossaryText = glossarySections
            .map { section in
                "\(section.title)：\(section.items.joined(separator: "、"))"
            }
            .joined(separator: "\n")

        return """
        \(promptWithSkills)

        词库参考：
        - 若输入中出现疑似专有术语、行业术语、近音错词，应优先参考以下标准写法。
        - 词库仅用于纠错参考，不代表可以改写原句或补充新内容。
        \(glossaryText)
        """
    }

    private static func skillInstructions(for skills: [DictationProcessingSkill]) -> String {
        guard !skills.isEmpty else {
            return ""
        }

        let steps = skills.enumerated().map { index, skill in
            "第 \(index + 2) 步：\(skillInstruction(for: skill))"
        }

        return """
        仅在启用下列技能时，才执行对应步骤：
        \(steps.joined(separator: "\n"))

        额外规则：
        - 不要补充原文没有出现的新信息。
        - 不要把内容总结成更短版本。
        - 除“整理成有序列表”外，不要主动改变整体结构。
        """
    }

    private static func skillInstruction(for skill: DictationProcessingSkill) -> String {
        switch skill {
        case .removeFillers:
            return "去掉明显语气词和停顿赘词，例如“嗯”“啊”“那个”“就是”“然后”。仅删除赘词，尽量不改句子结构。"
        case .formalize:
            return "把口述表达整理为中性、简洁、正式的书面语。不要写成邮件，不要加入标题，不要扩写。"
        case .orderedList:
            return "如果内容中存在 2 个及以上清晰的事项、观点或步骤，整理成纯文本有序列表，使用“1.”、“2.”、“3.”。如果只有一个清晰事项或不适合拆项，则保持段落文本，不要强行列成单项列表。"
        }
    }

    private static func normalized(_ skills: [DictationProcessingSkill]) -> [DictationProcessingSkill] {
        let uniqueSkills = Set(skills)
        return DictationProcessingSkill.allCases.filter { uniqueSkills.contains($0) }
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

    struct Thinking: Codable {
        let type: String
    }

    let model: String
    let messages: [Message]
    let temperature: Double
    let thinking: Thinking?
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
