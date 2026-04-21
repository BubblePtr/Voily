import CryptoKit
import Foundation

struct FunASRVocabularyEntry: Codable, Equatable {
    let text: String
    let weight: Int
}

struct FunASRVocabularySyncPlan: Equatable {
    enum Action: Equatable {
        case none
        case create
        case recreate(vocabularyID: String)
        case update(vocabularyID: String)
        case delete(vocabularyID: String)
    }

    let action: Action
    let targetModel: String
    let entries: [FunASRVocabularyEntry]
    let revision: String
}

enum FunASRVocabularyServiceError: LocalizedError {
    case missingBaseURL
    case missingAPIKey
    case missingModel
    case invalidBaseURL(String)
    case invalidResponse
    case missingVocabularyID

    var errorDescription: String? {
        switch self {
        case .missingBaseURL:
            return "未配置 Fun-ASR 热词接口地址。"
        case .missingAPIKey:
            return "未配置 Fun-ASR 热词 API Key。"
        case .missingModel:
            return "未配置 Fun-ASR 热词目标模型。"
        case let .invalidBaseURL(value):
            return "Fun-ASR 热词接口地址无效：\(value)"
        case .invalidResponse:
            return "Fun-ASR 热词接口返回了无效响应。"
        case .missingVocabularyID:
            return "Fun-ASR 热词接口未返回 vocabulary_id。"
        }
    }
}

actor FunASRVocabularyService {
    private static let prefix = "voily"

    private let session: URLSession

    init(session: URLSession = .shared) {
        self.session = session
    }

    func syncVocabularyIfNeeded(config: ASRProviderConfig, glossaryTerms: [String]) async throws -> ASRProviderConfig {
        let plan = Self.makeSyncPlan(config: config, glossaryTerms: glossaryTerms)

        switch plan.action {
        case .none:
            if plan.entries.isEmpty {
                return config.clearingFunASRVocabulary()
            }
            return config.updatingFunASRVocabulary(
                vocabularyID: config.vocabularyID,
                vocabularyTargetModel: plan.targetModel,
                vocabularyRevision: plan.revision
            )
        case .create:
            let vocabularyID = try await createVocabulary(
                config: config,
                targetModel: plan.targetModel,
                entries: plan.entries
            )
            return config.updatingFunASRVocabulary(
                vocabularyID: vocabularyID,
                vocabularyTargetModel: plan.targetModel,
                vocabularyRevision: plan.revision
            )
        case let .recreate(vocabularyID):
            try await deleteVocabulary(config: config, vocabularyID: vocabularyID)
            let newVocabularyID = try await createVocabulary(
                config: config,
                targetModel: plan.targetModel,
                entries: plan.entries
            )
            return config.updatingFunASRVocabulary(
                vocabularyID: newVocabularyID,
                vocabularyTargetModel: plan.targetModel,
                vocabularyRevision: plan.revision
            )
        case let .update(vocabularyID):
            try await updateVocabulary(
                config: config,
                vocabularyID: vocabularyID,
                entries: plan.entries
            )
            return config.updatingFunASRVocabulary(
                vocabularyID: vocabularyID,
                vocabularyTargetModel: plan.targetModel,
                vocabularyRevision: plan.revision
            )
        case let .delete(vocabularyID):
            try await deleteVocabulary(config: config, vocabularyID: vocabularyID)
            return config.clearingFunASRVocabulary()
        }
    }

    static func makeSyncPlan(config: ASRProviderConfig, glossaryTerms: [String]) -> FunASRVocabularySyncPlan {
        let entries = normalizedEntries(from: glossaryTerms)
        let targetModel = FunASRRealtimeService.normalizedSingleLineValue(config.model)
        let revision = vocabularyRevision(targetModel: targetModel, glossaryTerms: glossaryTerms)
        let vocabularyID = FunASRRealtimeService.normalizedSingleLineValue(config.vocabularyID)
        let cachedTargetModel = FunASRRealtimeService.normalizedSingleLineValue(config.vocabularyTargetModel)
        let cachedRevision = FunASRRealtimeService.normalizedSingleLineValue(config.vocabularyRevision)

        if entries.isEmpty {
            if vocabularyID.isEmpty {
                return FunASRVocabularySyncPlan(action: .none, targetModel: targetModel, entries: [], revision: "")
            }
            return FunASRVocabularySyncPlan(
                action: .delete(vocabularyID: vocabularyID),
                targetModel: targetModel,
                entries: [],
                revision: ""
            )
        }

        if vocabularyID.isEmpty {
            return FunASRVocabularySyncPlan(
                action: .create,
                targetModel: targetModel,
                entries: entries,
                revision: revision
            )
        }

        if cachedTargetModel != targetModel {
            return FunASRVocabularySyncPlan(
                action: .recreate(vocabularyID: vocabularyID),
                targetModel: targetModel,
                entries: entries,
                revision: revision
            )
        }

        if cachedRevision != revision {
            return FunASRVocabularySyncPlan(
                action: .update(vocabularyID: vocabularyID),
                targetModel: targetModel,
                entries: entries,
                revision: revision
            )
        }

        return FunASRVocabularySyncPlan(
            action: .none,
            targetModel: targetModel,
            entries: entries,
            revision: revision
        )
    }

    static func vocabularyRevision(targetModel: String, glossaryTerms: [String]) -> String {
        let seed = ([targetModel] + normalizedEntries(from: glossaryTerms).map(\.text)).joined(separator: "\u{1F}")
        let digest = SHA256.hash(data: Data(seed.utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    static func makeCustomizationURL(fromRealtimeBaseURL realtimeBaseURL: String) throws -> URL {
        let normalized = FunASRRealtimeService.normalizedSingleLineValue(realtimeBaseURL)
        guard let baseURL = URL(string: normalized), let host = baseURL.host else {
            throw FunASRVocabularyServiceError.invalidBaseURL(normalized)
        }

        var components = URLComponents()
        switch baseURL.scheme?.lowercased() {
        case "wss", "https":
            components.scheme = "https"
        case "ws", "http":
            components.scheme = "http"
        default:
            throw FunASRVocabularyServiceError.invalidBaseURL(normalized)
        }
        components.host = host
        components.port = baseURL.port
        components.path = "/api/v1/services/audio/asr/customization"

        guard let url = components.url else {
            throw FunASRVocabularyServiceError.invalidBaseURL(normalized)
        }
        return url
    }

    static func makeCreateVocabularyRequestBody(targetModel: String, entries: [FunASRVocabularyEntry]) throws -> Data {
        let payload: [String: Any] = [
            "model": "speech-biasing",
            "input": [
                "action": "create_vocabulary",
                "target_model": targetModel,
                "prefix": prefix,
                "vocabulary": try vocabularyJSONObject(from: entries),
            ],
        ]
        return try JSONSerialization.data(withJSONObject: payload)
    }

    static func makeUpdateVocabularyRequestBody(vocabularyID: String, entries: [FunASRVocabularyEntry]) throws -> Data {
        let payload: [String: Any] = [
            "model": "speech-biasing",
            "input": [
                "action": "update_vocabulary",
                "vocabulary_id": vocabularyID,
                "vocabulary": try vocabularyJSONObject(from: entries),
            ],
        ]
        return try JSONSerialization.data(withJSONObject: payload)
    }

    static func makeDeleteVocabularyRequestBody(vocabularyID: String) throws -> Data {
        let payload: [String: Any] = [
            "model": "speech-biasing",
            "input": [
                "action": "delete_vocabulary",
                "vocabulary_id": vocabularyID,
            ],
        ]
        return try JSONSerialization.data(withJSONObject: payload)
    }

    private func createVocabulary(
        config: ASRProviderConfig,
        targetModel: String,
        entries: [FunASRVocabularyEntry]
    ) async throws -> String {
        let model = FunASRRealtimeService.normalizedSingleLineValue(targetModel)
        guard !model.isEmpty else { throw FunASRVocabularyServiceError.missingModel }

        let body = try Self.makeCreateVocabularyRequestBody(targetModel: model, entries: entries)
        let data = try await sendCustomizationRequest(config: config, body: body)
        let response = try JSONDecoder().decode(FunASRVocabularyCreateResponse.self, from: data)
        guard let vocabularyID = response.output?.vocabularyID?.trimmingCharacters(in: .whitespacesAndNewlines),
              !vocabularyID.isEmpty
        else {
            throw FunASRVocabularyServiceError.missingVocabularyID
        }
        return vocabularyID
    }

    private func updateVocabulary(
        config: ASRProviderConfig,
        vocabularyID: String,
        entries: [FunASRVocabularyEntry]
    ) async throws {
        let body = try Self.makeUpdateVocabularyRequestBody(vocabularyID: vocabularyID, entries: entries)
        _ = try await sendCustomizationRequest(config: config, body: body)
    }

    private func deleteVocabulary(config: ASRProviderConfig, vocabularyID: String) async throws {
        let body = try Self.makeDeleteVocabularyRequestBody(vocabularyID: vocabularyID)
        _ = try await sendCustomizationRequest(config: config, body: body)
    }

    private func sendCustomizationRequest(config: ASRProviderConfig, body: Data) async throws -> Data {
        let baseURL = FunASRRealtimeService.normalizedSingleLineValue(config.baseURL)
        guard !baseURL.isEmpty else { throw FunASRVocabularyServiceError.missingBaseURL }
        let apiKey = FunASRRealtimeService.normalizedSingleLineValue(config.apiKey)
        guard !apiKey.isEmpty else { throw FunASRVocabularyServiceError.missingAPIKey }

        let customizationURL = try Self.makeCustomizationURL(fromRealtimeBaseURL: baseURL)
        var request = URLRequest(url: customizationURL)
        request.httpMethod = "POST"
        request.timeoutInterval = 15
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.httpBody = body

        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse, (200 ..< 300).contains(httpResponse.statusCode) else {
            throw FunASRVocabularyServiceError.invalidResponse
        }
        return data
    }

    private static func normalizedEntries(from glossaryTerms: [String]) -> [FunASRVocabularyEntry] {
        var seen = Set<String>()
        let entries = glossaryTerms
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .filter { seen.insert($0).inserted }
            .map { FunASRVocabularyEntry(text: $0, weight: 4) }

        return entries.sorted {
            let lhs = $0.text.lowercased()
            let rhs = $1.text.lowercased()
            if lhs == rhs {
                return $0.text < $1.text
            }
            return lhs < rhs
        }
    }

    private static func vocabularyJSONObject(from entries: [FunASRVocabularyEntry]) throws -> [[String: Any]] {
        let data = try JSONEncoder().encode(entries)
        guard let object = try JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
            throw FunASRVocabularyServiceError.invalidResponse
        }
        return object
    }
}

private struct FunASRVocabularyCreateResponse: Decodable {
    struct Output: Decodable {
        let vocabularyID: String?

        private enum CodingKeys: String, CodingKey {
            case vocabularyID = "vocabulary_id"
        }
    }

    let output: Output?
}
