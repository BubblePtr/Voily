import Foundation

enum ASRConnectionTesterError: LocalizedError, Equatable {
    case unsupportedProvider

    var errorDescription: String? {
        switch self {
        case .unsupportedProvider:
            return "当前 provider 不支持测试连接。"
        }
    }
}

struct ASRConnectionTester {
    let qwenProbe: @Sendable (ASRProviderConfig, String) async throws -> Void
    let doubaoProbe: @Sendable (ASRProviderConfig, String) async throws -> Void

    init(
        qwenProbe: @escaping @Sendable (ASRProviderConfig, String) async throws -> Void,
        doubaoProbe: @escaping @Sendable (ASRProviderConfig, String) async throws -> Void
    ) {
        self.qwenProbe = qwenProbe
        self.doubaoProbe = doubaoProbe
    }

    func testConnection(provider: ASRProvider, config: ASRProviderConfig, languageCode: String) async throws {
        switch provider {
        case .qwenASR:
            try await qwenProbe(config, languageCode)
        case .doubaoStreaming:
            try await doubaoProbe(config, languageCode)
        case .senseVoice:
            throw ASRConnectionTesterError.unsupportedProvider
        }
    }

    static func live(
        qwenService: QwenRealtimeASRService = QwenRealtimeASRService(),
        doubaoService: DoubaoStreamingASRService = DoubaoStreamingASRService()
    ) -> ASRConnectionTester {
        ASRConnectionTester(
            qwenProbe: { config, languageCode in
                try await qwenService.testConnection(config: config, languageCode: languageCode)
            },
            doubaoProbe: { config, languageCode in
                try await doubaoService.testConnection(config: config, languageCode: languageCode)
            }
        )
    }
}
