import XCTest
@testable import VoilyLogic

@MainActor
final class LLMRefinementServiceTests: XCTestCase {
    override func tearDown() {
        CapturingURLProtocol.reset()
        URLProtocol.unregisterClass(CapturingURLProtocol.self)
        super.tearDown()
    }

    func testDeepSeekRequestDisablesThinkingMode() async throws {
        URLProtocol.registerClass(CapturingURLProtocol.self)
        CapturingURLProtocol.responseBody = """
        {
          "choices": [
            {
              "message": {
                "role": "assistant",
                "content": "把 JSON 字段补齐。"
              }
            }
          ]
        }
        """.data(using: .utf8)!

        let settings = AppSettings(defaults: makeDefaults())
        settings.selectedTextProvider = .deepSeek
        settings.setTextRefinementConfig(
            TextRefinementProviderConfig(
                baseURL: "https://api.deepseek.com",
                apiKey: "sk-test",
                model: "deepseek-v4-flash"
            ),
            for: .deepSeek
        )

        let output = try await LLMRefinementService().process(
            TextProcessingRequest(
                text: "把杰森字段补齐",
                languageCode: "zh-Hans",
                mode: .dictation(skills: [])
            ),
            settings: settings
        )

        let body = try XCTUnwrap(CapturingURLProtocol.lastRequestBody)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: body) as? [String: Any])
        let thinking = try XCTUnwrap(json["thinking"] as? [String: Any])

        XCTAssertEqual(output, "把 JSON 字段补齐。")
        XCTAssertEqual(CapturingURLProtocol.lastRequest?.url?.absoluteString, "https://api.deepseek.com/chat/completions")
        XCTAssertEqual(json["model"] as? String, "deepseek-v4-flash")
        XCTAssertEqual(thinking["type"] as? String, "disabled")
    }

    func testNormalizedResponseTextStripsLeadingThinkBlockForProvider() {
        let output = LLMRefinementService.normalizedResponseText("""
        <think>
        先判断用户意图，再执行纠错。
        </think>

        把 JSON 字段补齐。
        """, provider: .deepSeek)

        XCTAssertEqual(output, "把 JSON 字段补齐。")
    }

    func testNormalizedResponseTextPreservesPlainContent() {
        let output = LLMRefinementService.normalizedResponseText("把 Python 版本升到 3.12。")

        XCTAssertEqual(output, "把 Python 版本升到 3.12。")
    }

    func testNormalizedResponseTextPreservesInlineThinkMarkup() {
        let output = LLMRefinementService.normalizedResponseText(
            "示例 XML：<think>literal</think><answer>done</answer>",
            provider: .deepSeek
        )

        XCTAssertEqual(output, "示例 XML：<think>literal</think><answer>done</answer>")
    }

    func testNormalizedResponseTextPreservesLeadingThinkBlockWithoutProviderContext() {
        let output = LLMRefinementService.normalizedResponseText("""
        <think>literal</think>
        <answer>done</answer>
        """)

        XCTAssertEqual(output, "<think>literal</think>\n<answer>done</answer>")
    }

    func testSystemPromptIncludesGlossarySectionsWhenAvailable() {
        let settings = AppSettings(defaults: makeDefaults())
        settings.setGlossaryState(
            enabledPresetIDs: [.internetDevelopment],
            customTerms: ["Voily", "DeepSeek"]
        )

        let prompt = LLMRefinementService.systemPrompt(
            for: TextProcessingRequest(
                text: "测试 JSON 和 Python",
                languageCode: "zh-Hans",
                mode: .dictation(skills: [])
            ),
            glossarySections: settings.effectiveGlossarySections
        )

        XCTAssertTrue(prompt.contains("词库参考"))
        XCTAssertTrue(prompt.contains("自定义词条"))
        XCTAssertTrue(prompt.contains("互联网-开发"))
        XCTAssertTrue(prompt.contains("Voily"))
        XCTAssertTrue(prompt.contains("OpenAI"))
    }

    func testSystemPromptOmitsGlossarySectionWhenNoGlossaryItemsExist() {
        let prompt = LLMRefinementService.systemPrompt(
            for: TextProcessingRequest(
                text: "测试 JSON 和 Python",
                languageCode: "zh-Hans",
                mode: .dictation(skills: [])
            ),
            glossarySections: []
        )

        XCTAssertFalse(prompt.contains("词库参考"))
        XCTAssertFalse(prompt.contains("自定义词条"))
        XCTAssertFalse(prompt.contains("互联网-开发"))
        XCTAssertFalse(prompt.contains("仅在启用下列技能时"))
    }

    func testDictationPromptIncludesSkillsInStableExecutionOrder() throws {
        let prompt = LLMRefinementService.systemPrompt(
            for: TextProcessingRequest(
                text: "嗯这个就是我们先做登录，然后那个支付后面再补",
                languageCode: "zh-Hans",
                mode: .dictation(skills: [.orderedList, .removeFillers, .formalize, .removeFillers])
            ),
            glossarySections: []
        )

        let removeRange = try XCTUnwrap(prompt.range(of: "第 2 步：去掉明显语气词"))
        let formalizeRange = try XCTUnwrap(prompt.range(of: "第 3 步：把口述表达整理为中性、简洁、正式的书面语"))
        let orderedListRange = try XCTUnwrap(prompt.range(of: "第 4 步：如果内容中存在 2 个及以上清晰的事项、观点或步骤"))

        XCTAssertLessThan(removeRange.lowerBound, formalizeRange.lowerBound)
        XCTAssertLessThan(formalizeRange.lowerBound, orderedListRange.lowerBound)
        XCTAssertTrue(prompt.contains("如果只有一个清晰事项或不适合拆项，则保持段落文本"))
        XCTAssertFalse(prompt.contains("第 5 步"))
    }

    func testTranslationPromptForcesEnglishOnlyOutput() {
        let prompt = LLMRefinementService.systemPrompt(
            for: TextProcessingRequest(
                text: "把这个版本今天发给客户",
                languageCode: "zh-CN",
                mode: .translateZhToEn(style: .natural)
            ),
            glossarySections: [GlossarySection(title: "自定义词条", items: ["Voily"])]
        )

        XCTAssertTrue(prompt.contains("只输出英文最终结果"))
        XCTAssertTrue(prompt.contains("不要输出中文"))
        XCTAssertFalse(prompt.contains("词库参考"))
        XCTAssertFalse(prompt.contains("Voily"))
        XCTAssertFalse(prompt.contains("第 1 步：基础纠错"))
    }

    private func makeDefaults() -> UserDefaults {
        let suiteName = "Voily.LLMRefinementServiceTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        return defaults
    }
}

private final class CapturingURLProtocol: URLProtocol {
    nonisolated(unsafe) static var lastRequest: URLRequest?
    nonisolated(unsafe) static var lastRequestBody: Data?
    nonisolated(unsafe) static var responseBody = Data()

    override class func canInit(with request: URLRequest) -> Bool {
        true
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        Self.lastRequest = request
        Self.lastRequestBody = request.httpBody ?? request.httpBodyStream.flatMap(Self.readBodyStream)

        let response = HTTPURLResponse(
            url: request.url!,
            statusCode: 200,
            httpVersion: "HTTP/1.1",
            headerFields: ["Content-Type": "application/json"]
        )!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Self.responseBody)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}

    static func reset() {
        lastRequest = nil
        lastRequestBody = nil
        responseBody = Data()
    }

    private static func readBodyStream(_ stream: InputStream) -> Data {
        stream.open()
        defer { stream.close() }

        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 4096)
        while stream.hasBytesAvailable {
            let count = stream.read(&buffer, maxLength: buffer.count)
            if count <= 0 {
                break
            }
            data.append(buffer, count: count)
        }
        return data
    }
}
