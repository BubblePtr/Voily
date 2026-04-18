import XCTest
@testable import Voily

private actor ProbeRecorder {
    private(set) var invokedProvider: ASRProvider?

    func record(_ provider: ASRProvider) {
        invokedProvider = provider
    }
}

final class ASRConnectionTesterTests: XCTestCase {
    func testRoutesQwenProviderToQwenProbe() async throws {
        let config = ASRProviderConfig(
            executablePath: "",
            modelPath: "",
            additionalArguments: "",
            baseURL: "wss://dashscope.aliyuncs.com/api-ws/v1/realtime",
            apiKey: "dashscope-key",
            model: "qwen3-asr-flash-realtime",
            appID: ""
        )

        let recorder = ProbeRecorder()
        let tester = ASRConnectionTester(
            qwenProbe: { receivedConfig, _ in
                XCTAssertEqual(receivedConfig, config)
                await recorder.record(.qwenASR)
            },
            stepProbe: { _, _ in
                XCTFail("unexpected step probe")
            },
            doubaoProbe: { _, _ in
                XCTFail("unexpected doubao probe")
            }
        )

        try await tester.testConnection(
            provider: .qwenASR,
            config: config,
            languageCode: "zh-CN"
        )

        let invokedProvider = await recorder.invokedProvider
        XCTAssertEqual(invokedProvider, .qwenASR)
    }

    func testRoutesDoubaoProviderToDoubaoProbe() async throws {
        let config = ASRProviderConfig(
            executablePath: "",
            modelPath: "",
            additionalArguments: "",
            baseURL: "wss://openspeech.bytedance.com/api/v3/sauc/bigmodel_async",
            apiKey: "volc-token",
            model: "volc.seedasr.sauc.duration",
            appID: "appid"
        )

        let recorder = ProbeRecorder()
        let tester = ASRConnectionTester(
            qwenProbe: { _, _ in
                XCTFail("unexpected qwen probe")
            },
            stepProbe: { _, _ in
                XCTFail("unexpected step probe")
            },
            doubaoProbe: { receivedConfig, _ in
                XCTAssertEqual(receivedConfig, config)
                await recorder.record(.doubaoStreaming)
            }
        )

        try await tester.testConnection(
            provider: .doubaoStreaming,
            config: config,
            languageCode: "zh-CN"
        )

        let invokedProvider = await recorder.invokedProvider
        XCTAssertEqual(invokedProvider, .doubaoStreaming)
    }

    func testRoutesStepProviderToStepProbe() async throws {
        let config = ASRProviderConfig(
            executablePath: "",
            modelPath: "",
            additionalArguments: "",
            baseURL: "wss://api.stepfun.com/v1/realtime/asr/stream",
            apiKey: "step-key",
            model: "step-asr-1.1-stream",
            appID: ""
        )

        let recorder = ProbeRecorder()
        let tester = ASRConnectionTester(
            qwenProbe: { _, _ in
                XCTFail("unexpected qwen probe")
            },
            stepProbe: { receivedConfig, _ in
                XCTAssertEqual(receivedConfig, config)
                await recorder.record(.stepfunASR)
            },
            doubaoProbe: { _, _ in
                XCTFail("unexpected doubao probe")
            }
        )

        try await tester.testConnection(
            provider: .stepfunASR,
            config: config,
            languageCode: "zh-CN"
        )

        let invokedProvider = await recorder.invokedProvider
        XCTAssertEqual(invokedProvider, .stepfunASR)
    }

    func testRejectsUnsupportedProvider() async {
        let tester = ASRConnectionTester(
            qwenProbe: { _, _ in },
            stepProbe: { _, _ in },
            doubaoProbe: { _, _ in }
        )

        do {
            try await tester.testConnection(
                provider: .senseVoice,
                config: .empty,
                languageCode: "zh-CN"
            )
            XCTFail("expected unsupported provider error")
        } catch {
            XCTAssertEqual(error as? ASRConnectionTesterError, .unsupportedProvider)
        }
    }
}
