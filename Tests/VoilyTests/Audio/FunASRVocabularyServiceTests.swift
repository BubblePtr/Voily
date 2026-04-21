import XCTest
@testable import Voily

final class FunASRVocabularyServiceTests: XCTestCase {
    func testMakeSyncPlanCreatesVocabularyWhenTermsExistAndNoVocabularyID() {
        let config = ASRProviderConfig(
            executablePath: "",
            modelPath: "",
            additionalArguments: "",
            baseURL: "wss://dashscope.aliyuncs.com/api-ws/v1/inference",
            apiKey: "dashscope-key",
            model: "fun-asr-realtime",
            appID: ""
        )

        let plan = FunASRVocabularyService.makeSyncPlan(
            config: config,
            glossaryTerms: [" Voily ", "OpenAI", "Voily"]
        )

        XCTAssertEqual(plan.action, .create)
        XCTAssertEqual(plan.targetModel, "fun-asr-realtime")
        XCTAssertEqual(plan.entries.map(\.text), ["OpenAI", "Voily"])
        XCTAssertFalse(plan.revision.isEmpty)
    }

    func testMakeSyncPlanUpdatesVocabularyWhenRevisionChanges() {
        let revision = FunASRVocabularyService.vocabularyRevision(
            targetModel: "fun-asr-realtime",
            glossaryTerms: ["OpenAI"]
        )
        let config = ASRProviderConfig(
            executablePath: "",
            modelPath: "",
            additionalArguments: "",
            baseURL: "wss://dashscope.aliyuncs.com/api-ws/v1/inference",
            apiKey: "dashscope-key",
            model: "fun-asr-realtime",
            appID: "",
            vocabularyID: "vocab-voily-123",
            vocabularyTargetModel: "fun-asr-realtime",
            vocabularyRevision: revision
        )

        let plan = FunASRVocabularyService.makeSyncPlan(
            config: config,
            glossaryTerms: ["OpenAI", "Voily"]
        )

        XCTAssertEqual(plan.action, .update(vocabularyID: "vocab-voily-123"))
        XCTAssertEqual(plan.entries.map(\.text), ["OpenAI", "Voily"])
    }

    func testMakeSyncPlanRecreatesVocabularyWhenTargetModelChanges() {
        let revision = FunASRVocabularyService.vocabularyRevision(
            targetModel: "fun-asr-realtime",
            glossaryTerms: ["OpenAI"]
        )
        let config = ASRProviderConfig(
            executablePath: "",
            modelPath: "",
            additionalArguments: "",
            baseURL: "wss://dashscope.aliyuncs.com/api-ws/v1/inference",
            apiKey: "dashscope-key",
            model: "fun-asr-realtime-v2",
            appID: "",
            vocabularyID: "vocab-voily-123",
            vocabularyTargetModel: "fun-asr-realtime",
            vocabularyRevision: revision
        )

        let plan = FunASRVocabularyService.makeSyncPlan(
            config: config,
            glossaryTerms: ["OpenAI"]
        )

        XCTAssertEqual(plan.action, .recreate(vocabularyID: "vocab-voily-123"))
        XCTAssertEqual(plan.targetModel, "fun-asr-realtime-v2")
        XCTAssertEqual(plan.entries.map(\.text), ["OpenAI"])
    }

    func testMakeSyncPlanDeletesVocabularyWhenGlossaryBecomesEmpty() {
        let config = ASRProviderConfig(
            executablePath: "",
            modelPath: "",
            additionalArguments: "",
            baseURL: "wss://dashscope.aliyuncs.com/api-ws/v1/inference",
            apiKey: "dashscope-key",
            model: "fun-asr-realtime",
            appID: "",
            vocabularyID: "vocab-voily-123",
            vocabularyTargetModel: "fun-asr-realtime",
            vocabularyRevision: "rev-123"
        )

        let plan = FunASRVocabularyService.makeSyncPlan(
            config: config,
            glossaryTerms: []
        )

        XCTAssertEqual(plan.action, .delete(vocabularyID: "vocab-voily-123"))
        XCTAssertEqual(plan.entries, [])
    }

    func testMakeCustomizationURLConvertsRealtimeWebSocketToHTTPCustomizationEndpoint() throws {
        let url = try FunASRVocabularyService.makeCustomizationURL(
            fromRealtimeBaseURL: "wss://dashscope.aliyuncs.com/api-ws/v1/inference"
        )

        XCTAssertEqual(url.absoluteString, "https://dashscope.aliyuncs.com/api/v1/services/audio/asr/customization")
    }

    func testCreateVocabularyRequestBodyIncludesTargetModelAndEntries() throws {
        let data = try FunASRVocabularyService.makeCreateVocabularyRequestBody(
            targetModel: "fun-asr-realtime",
            entries: [
                .init(text: "OpenAI", weight: 4),
                .init(text: "Voily", weight: 4),
            ]
        )
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let input = try XCTUnwrap(json["input"] as? [String: Any])
        let vocabulary = try XCTUnwrap(input["vocabulary"] as? [[String: Any]])

        XCTAssertEqual(json["model"] as? String, "speech-biasing")
        XCTAssertEqual(input["action"] as? String, "create_vocabulary")
        XCTAssertEqual(input["target_model"] as? String, "fun-asr-realtime")
        XCTAssertEqual(input["prefix"] as? String, "voily")
        XCTAssertEqual(vocabulary.count, 2)
        XCTAssertEqual(vocabulary.first?["text"] as? String, "OpenAI")
        XCTAssertEqual(vocabulary.first?["weight"] as? Int, 4)
    }
}
