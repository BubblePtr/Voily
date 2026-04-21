import XCTest
@testable import Voily

final class FunASRRealtimeServiceTests: XCTestCase {
    func testRunTaskMessageIncludesModelAndRealtimeParameters() throws {
        let message = try FunASRRealtimeService.makeRunTaskMessage(
            taskID: "task-123",
            model: "fun-asr-realtime",
            vocabularyID: nil,
            languageCode: SupportedLanguage.simplifiedChinese.rawValue
        )
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: message) as? [String: Any])
        let header = try XCTUnwrap(json["header"] as? [String: Any])
        let payload = try XCTUnwrap(json["payload"] as? [String: Any])
        let parameters = try XCTUnwrap(payload["parameters"] as? [String: Any])
        let input = try XCTUnwrap(payload["input"] as? [String: Any])

        XCTAssertEqual(header["action"] as? String, "run-task")
        XCTAssertEqual(header["task_id"] as? String, "task-123")
        XCTAssertEqual(header["streaming"] as? String, "duplex")
        XCTAssertEqual(payload["task_group"] as? String, "audio")
        XCTAssertEqual(payload["task"] as? String, "asr")
        XCTAssertEqual(payload["function"] as? String, "recognition")
        XCTAssertEqual(payload["model"] as? String, "fun-asr-realtime")
        XCTAssertEqual(parameters["format"] as? String, "pcm")
        XCTAssertEqual(parameters["sample_rate"] as? Int, 16_000)
        XCTAssertEqual(parameters["semantic_punctuation_enabled"] as? Bool, false)
        XCTAssertEqual(parameters["max_sentence_silence"] as? Int, 1_300)
        XCTAssertEqual(parameters["language_hints"] as? [String], ["zh"])
        XCTAssertNil(parameters["vocabulary_id"])
        XCTAssertEqual(input.count, 0)
    }

    func testRunTaskMessageIncludesVocabularyIDWhenProvided() throws {
        let message = try FunASRRealtimeService.makeRunTaskMessage(
            taskID: "task-123",
            model: "fun-asr-realtime",
            vocabularyID: "vocab-voily-123",
            languageCode: SupportedLanguage.english.rawValue
        )
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: message) as? [String: Any])
        let payload = try XCTUnwrap(json["payload"] as? [String: Any])
        let parameters = try XCTUnwrap(payload["parameters"] as? [String: Any])

        XCTAssertEqual(parameters["vocabulary_id"] as? String, "vocab-voily-123")
        XCTAssertEqual(parameters["language_hints"] as? [String], ["en"])
    }

    func testRunTaskMessageOmitsLanguageHintsWhenLanguageIsUnsupported() throws {
        let message = try FunASRRealtimeService.makeRunTaskMessage(
            taskID: "task-123",
            model: "fun-asr-realtime",
            vocabularyID: nil,
            languageCode: SupportedLanguage.korean.rawValue
        )
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: message) as? [String: Any])
        let payload = try XCTUnwrap(json["payload"] as? [String: Any])
        let parameters = try XCTUnwrap(payload["parameters"] as? [String: Any])

        XCTAssertNil(parameters["language_hints"])
    }

    func testFinishTaskMessageReferencesTaskID() throws {
        let message = try FunASRRealtimeService.makeFinishTaskMessage(taskID: "task-456")
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: message) as? [String: Any])
        let header = try XCTUnwrap(json["header"] as? [String: Any])
        let payload = try XCTUnwrap(json["payload"] as? [String: Any])
        let input = try XCTUnwrap(payload["input"] as? [String: Any])

        XCTAssertEqual(header["action"] as? String, "finish-task")
        XCTAssertEqual(header["task_id"] as? String, "task-456")
        XCTAssertEqual(header["streaming"] as? String, "duplex")
        XCTAssertEqual(input.count, 0)
    }

    func testSentenceUpdateExtractorReadsOfficialEventShape() {
        let payload: [String: Any] = [
            "header": [
                "event": "result-generated",
            ],
            "payload": [
                "output": [
                    "sentence": [
                        "text": "好，我知道了",
                        "sentence_end": true,
                        "heartbeat": false,
                    ],
                ],
            ],
        ]

        let update = FunASRRealtimeService.sentenceUpdate(from: payload)

        XCTAssertEqual(update?.text, "好，我知道了")
        XCTAssertEqual(update?.sentenceEnd, true)
        XCTAssertEqual(update?.heartbeat, false)
    }

    func testTaskFailedMessageExtractorReadsErrorCodeAndMessage() {
        let payload: [String: Any] = [
            "header": [
                "event": "task-failed",
                "error_code": "CLIENT_ERROR",
                "error_message": "request timeout after 23 seconds.",
            ],
        ]

        let error = FunASRRealtimeService.taskFailure(from: payload)

        XCTAssertEqual(error?.code, "CLIENT_ERROR")
        XCTAssertEqual(error?.message, "request timeout after 23 seconds.")
    }
}
