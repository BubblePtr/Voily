import XCTest
@testable import Voily

@MainActor
final class SenseVoiceNativeServiceSmokeTests: XCTestCase {
    private let smokeFlagPath = "/tmp/voily-run-native-sensevoice-smoke"

    func testNativeSenseVoiceCanLoadLocalModelAndRunForwardPassWhenEnabled() async throws {
        guard isSmokeTestEnabled else {
            throw XCTSkip("Set VOILY_RUN_NATIVE_SENSEVOICE_SMOKE=1 or create /tmp/voily-run-native-sensevoice-smoke to run the local 900 MB model smoke test.")
        }

        let service = SenseVoiceNativeService()
        let pcm = makeSinePCM16(durationSeconds: 0.24, sampleRate: 16_000)

        do {
            _ = try await service.transcribe(
                pcm16MonoData: pcm,
                sampleRate: 16_000,
                languageCode: "zh-Hans"
            )
        } catch SenseVoiceNativeError.emptyTranscript {
            // The generated tone is not speech; the assertion here is that model loading and forward pass succeed.
        }
    }

    private var isSmokeTestEnabled: Bool {
        ProcessInfo.processInfo.environment["VOILY_RUN_NATIVE_SENSEVOICE_SMOKE"] == "1" ||
            FileManager.default.fileExists(atPath: smokeFlagPath)
    }

    private func makeSinePCM16(durationSeconds: Double, sampleRate: Int) -> Data {
        let count = Int(durationSeconds * Double(sampleRate))
        var data = Data()
        data.reserveCapacity(count * 2)

        for index in 0 ..< count {
            let phase = 2 * Double.pi * 440 * Double(index) / Double(sampleRate)
            let sample = Int16(max(-0.25, min(0.25, sin(phase))) * Double(Int16.max))
            var littleEndian = sample.littleEndian
            withUnsafeBytes(of: &littleEndian) { bytes in
                data.append(contentsOf: bytes)
            }
        }

        return data
    }
}
