import XCTest
@testable import Voily

final class DoubaoStreamingASRServiceTests: XCTestCase {
    func testStartRequestPayloadIncludesEnglishLanguage() throws {
        let payload = try DoubaoStreamingASRService.makeStartRequestPayload(languageCode: "en-US")
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: payload) as? [String: Any])
        let audio = try XCTUnwrap(json["audio"] as? [String: Any])

        XCTAssertEqual(audio["language"] as? String, "en-US")
        XCTAssertEqual(audio["format"] as? String, "pcm")
    }

    func testStartRequestPayloadNormalizesTraditionalChineseToZhCN() throws {
        let payload = try DoubaoStreamingASRService.makeStartRequestPayload(languageCode: "zh-TW")
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: payload) as? [String: Any])
        let audio = try XCTUnwrap(json["audio"] as? [String: Any])

        XCTAssertEqual(audio["language"] as? String, "zh-CN")
    }

    func testStartRequestPayloadRejectsUnsupportedLanguage() {
        XCTAssertThrowsError(try DoubaoStreamingASRService.makeStartRequestPayload(languageCode: "ja-JP")) { error in
            guard case let DoubaoStreamingASRServiceError.unsupportedLanguage(value) = error else {
                return XCTFail("unexpected error: \(error)")
            }
            XCTAssertEqual(value, "ja-JP")
        }
    }

    func testInvalidResourceIDFormatIsRejectedBeforeNetwork() async {
        let service = DoubaoStreamingASRService()
        let config = ASRProviderConfig(
            executablePath: "",
            modelPath: "",
            additionalArguments: "",
            baseURL: "wss://openspeech.bytedance.com/api/v3/sauc/bigmodel_async",
            apiKey: "token",
            model: "volc.seedast.sauc.duration",
            appID: "appid"
        )

        do {
            try await service.testConnection(config: config, languageCode: "zh-CN")
            XCTFail("expected invalid resource id error")
        } catch {
            guard case let DoubaoStreamingASRServiceError.invalidResourceIDFormat(value) = error else {
                return XCTFail("unexpected error: \(error)")
            }
            XCTAssertEqual(value, "volc.seedast.sauc.duration")
        }
    }

    func testFullRequestPacketUsesJSONPayloadWithoutCompression() throws {
        let packet = try DoubaoWireCodec.makeFullRequestPacket(
            payload: Data(#"{"hello":"world"}"#.utf8),
            compression: .none
        )

        XCTAssertEqual(packet.prefix(4), Data([0x11, 0x10, 0x10, 0x00]))
        XCTAssertEqual(packet.count, 4 + 4 + #"{"hello":"world"}"#.utf8.count)
    }

    func testFinalAudioPacketUsesFinalFlag() throws {
        let packet = try DoubaoWireCodec.makeAudioPacket(
            audioData: Data([0x01, 0x02, 0x03]),
            isFinal: true,
            compression: .none
        )

        XCTAssertEqual(packet.prefix(4), Data([0x11, 0x22, 0x00, 0x00]))
        XCTAssertEqual(packet.suffix(3), Data([0x01, 0x02, 0x03]))
    }

    func testDecodeServerResponseExtractsUtteranceTextAndFinalFlag() throws {
        let payload = """
        {
          "code": 20000000,
          "message": "success",
          "sequence": -1,
          "result": {
            "text": "今天下午三点开会",
            "utterances": [
              {
                "text": "今天下午三点开会",
                "definite": true
              }
            ]
          }
        }
        """

        let packet = DoubaoStreamingASRServiceTests.makeServerResponsePacket(payload: Data(payload.utf8))
        let response = try DoubaoWireCodec.decodeServerMessage(packet)

        XCTAssertEqual(response.text, "今天下午三点开会")
        XCTAssertTrue(response.isFinal)
        XCTAssertEqual(response.code, 20000000)
    }

    func testDecodeSequencedServerResponseExtractsPartialText() throws {
        let payload = """
        {
          "code": 20000000,
          "message": "success",
          "result": [
            {
              "text": "今天下午三点",
              "utterances": [
                {
                  "text": "今天下午三点",
                  "definite": false
                }
              ]
            }
          ]
        }
        """

        let packet = Self.makeSequencedServerResponsePacket(
            flags: 0x1,
            sequence: 2,
            payload: Data(payload.utf8)
        )
        let response = try DoubaoWireCodec.decodeServerMessage(packet)

        XCTAssertEqual(response.text, "今天下午三点")
        XCTAssertFalse(response.isFinal)
        XCTAssertFalse(response.isDefinite)
        XCTAssertEqual(response.code, 20000000)
    }

    func testDecodeErrorResponseReadsCodeAndJSONStringPayload() throws {
        let payload = #"{"message":"invalid token"}"#
        let packet = Self.makeServerErrorPacket(code: 401, payload: Data(payload.utf8))

        let response = try DoubaoWireCodec.decodeServerMessage(packet)

        XCTAssertNil(response.text)
        XCTAssertTrue(response.isFinal)
        XCTAssertEqual(response.code, 401)
        XCTAssertEqual(response.message, payload)
    }

    func testInspectServerMessageCapturesHeaderMetadata() {
        let payload = #"{"code":1000}"#
        let packet = Self.makeServerResponsePacket(payload: Data(payload.utf8))

        let diagnostics = DoubaoWireCodec.inspectServerMessage(packet)

        XCTAssertEqual(diagnostics.byteCount, packet.count)
        XCTAssertEqual(diagnostics.protocolVersion, 1)
        XCTAssertEqual(diagnostics.headerSizeUnits, 1)
        XCTAssertEqual(diagnostics.headerSizeBytes, 4)
        XCTAssertEqual(diagnostics.messageType, 0x9)
        XCTAssertEqual(diagnostics.serialization, 0x1)
        XCTAssertEqual(diagnostics.payloadSize, payload.utf8.count)
        XCTAssertEqual(diagnostics.availablePayloadBytes, payload.utf8.count)
        XCTAssertEqual(diagnostics.utf8Preview, payload)
    }

    func testInspectSequencedServerMessageCapturesPayloadPreview() {
        let payload = #"{"code":20000000,"result":[{"text":"今天"}]}"#
        let packet = Self.makeSequencedServerResponsePacket(flags: 0x1, sequence: 2, payload: Data(payload.utf8))

        let diagnostics = DoubaoWireCodec.inspectServerMessage(packet)

        XCTAssertEqual(diagnostics.messageType, 0x9)
        XCTAssertEqual(diagnostics.flags, 0x1)
        XCTAssertEqual(diagnostics.payloadSize, payload.utf8.count)
        XCTAssertEqual(diagnostics.availablePayloadBytes, payload.utf8.count)
        XCTAssertEqual(diagnostics.utf8Preview, payload)
    }

    func testInspectServerMessageUsesErrorPayloadForPreview() {
        let payload = #"{"message":"invalid token"}"#
        let packet = Self.makeServerErrorPacket(code: 401, payload: Data(payload.utf8))

        let diagnostics = DoubaoWireCodec.inspectServerMessage(packet)

        XCTAssertEqual(diagnostics.messageType, 0xF)
        XCTAssertEqual(diagnostics.payloadSize, payload.utf8.count)
        XCTAssertEqual(diagnostics.availablePayloadBytes, payload.utf8.count)
        XCTAssertEqual(diagnostics.utf8Preview, payload)
    }

    func testNormalizedSingleLineValueUsesFirstNonEmptyLine() {
        let normalized = DoubaoStreamingASRService.normalizedSingleLineValue(
            "wss://openspeech.bytedance.com/api/v3/sauc/bigmodel_async\n\nwss://openspeech.bytedance.com/api/v3/sauc/bigmodel_async"
        )

        XCTAssertEqual(normalized, "wss://openspeech.bytedance.com/api/v3/sauc/bigmodel_async")
    }

    func testStepSessionUpdatePayloadIncludesModelAndLanguage() throws {
        let payload = try StepRealtimeASRService.makeSessionUpdatePayload(
            model: "step-asr-1.1-stream",
            languageCode: "zh-CN"
        )
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: payload) as? [String: Any])
        let session = try XCTUnwrap(json["session"] as? [String: Any])
        let audio = try XCTUnwrap(session["audio"] as? [String: Any])
        let input = try XCTUnwrap(audio["input"] as? [String: Any])
        let format = try XCTUnwrap(input["format"] as? [String: Any])
        let transcription = try XCTUnwrap(input["transcription"] as? [String: Any])

        XCTAssertEqual(json["type"] as? String, "session.update")
        XCTAssertEqual(format["type"] as? String, "pcm")
        XCTAssertEqual(format["codec"] as? String, "pcm_s16le")
        XCTAssertEqual(format["rate"] as? Int, 16_000)
        XCTAssertEqual(transcription["model"] as? String, "step-asr-1.1-stream")
        XCTAssertEqual(transcription["language"] as? String, "zh")
        XCTAssertEqual(transcription["full_rerun_on_commit"] as? Bool, true)
        XCTAssertEqual(transcription["enable_itn"] as? Bool, true)
        XCTAssertNil(input["turn_detection"])
    }

    func testStepSessionUpdatePayloadRejectsUnsupportedLanguage() {
        XCTAssertThrowsError(
            try StepRealtimeASRService.makeSessionUpdatePayload(
                model: "step-asr-1.1-stream",
                languageCode: "ja-JP"
            )
        ) { error in
            guard case let StepRealtimeASRServiceError.unsupportedLanguage(value) = error else {
                return XCTFail("unexpected error: \(error)")
            }
            XCTAssertEqual(value, "ja-JP")
        }
    }

    func testStepPartialAndFinalTextExtractorsReadOfficialEventShapes() {
        let partialPayload: [String: Any] = [
            "type": "conversation.item.input_audio_transcription.delta",
            "text": "你好，世界"
        ]
        let finalPayload: [String: Any] = [
            "type": "conversation.item.input_audio_transcription.completed",
            "transcript": "你好，世界"
        ]

        XCTAssertEqual(StepRealtimeASRService.partialText(from: partialPayload), "你好，世界")
        XCTAssertEqual(StepRealtimeASRService.finalTranscript(from: finalPayload), "你好，世界")
    }

    func testStepWithTimeoutThrowsWhenOperationDoesNotFinish() async {
        do {
            _ = try await StepRealtimeASRService.withTimeout(.milliseconds(20)) {
                try await Task.sleep(for: .milliseconds(100))
                return "late"
            }
            XCTFail("expected timeout")
        } catch {
            guard case let StepRealtimeASRServiceError.finishTimedOut(timeout) = error else {
                return XCTFail("unexpected error: \(error)")
            }
            XCTAssertEqual(timeout, .milliseconds(20))
        }
    }

    private static func makeServerResponsePacket(payload: Data) -> Data {
        var packet = Data([0x11, 0x90, 0x10, 0x00])
        var size = UInt32(payload.count).bigEndian
        withUnsafeBytes(of: &size) { packet.append(contentsOf: $0) }
        packet.append(payload)
        return packet
    }

    private static func makeSequencedServerResponsePacket(flags: UInt8, sequence: Int32, payload: Data) -> Data {
        var packet = Data([0x11, (0x9 << 4) | flags, 0x10, 0x00])
        var sequenceValue = UInt32(bitPattern: sequence).bigEndian
        withUnsafeBytes(of: &sequenceValue) { packet.append(contentsOf: $0) }
        var size = UInt32(payload.count).bigEndian
        withUnsafeBytes(of: &size) { packet.append(contentsOf: $0) }
        packet.append(payload)
        return packet
    }

    private static func makeServerErrorPacket(code: UInt32, payload: Data) -> Data {
        var packet = Data([0x11, 0xF0, 0x10, 0x00])
        var errorCode = code.bigEndian
        withUnsafeBytes(of: &errorCode) { packet.append(contentsOf: $0) }
        var size = UInt32(payload.count).bigEndian
        withUnsafeBytes(of: &size) { packet.append(contentsOf: $0) }
        packet.append(payload)
        return packet
    }
}
