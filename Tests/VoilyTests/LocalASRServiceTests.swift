import XCTest
import AVFoundation
@testable import Voily

final class LocalASRServiceTests: XCTestCase {
    func testTranscriptAccumulatorKeepsCommittedSegmentsAcrossPauses() {
        var accumulator = TranscriptAccumulator()

        XCTAssertEqual(accumulator.updatePartial("现在我来测试一下流式输出"), "现在我来测试一下流式输出")
        XCTAssertEqual(accumulator.commit("现在我来测试一下流式输出"), "现在我来测试一下流式输出")
        XCTAssertEqual(accumulator.updatePartial("如果我有停顿的话"), "现在我来测试一下流式输出如果我有停顿的话")
        XCTAssertEqual(accumulator.commit("如果我有停顿的话"), "现在我来测试一下流式输出如果我有停顿的话")
        XCTAssertEqual(accumulator.finalText, "现在我来测试一下流式输出如果我有停顿的话")
    }

    func testTranscriptAccumulatorAddsSpaceBetweenASCIIWordSegments() {
        var accumulator = TranscriptAccumulator()

        XCTAssertEqual(accumulator.commit("hello"), "hello")
        XCTAssertEqual(accumulator.updatePartial("world"), "hello world")
        XCTAssertEqual(accumulator.commit("world"), "hello world")
        XCTAssertEqual(accumulator.finalText, "hello world")
    }

    func testWhisperCommandUsesWhisperArguments() throws {
        let executablePath = try makeExecutable()
        let audioURL = URL(fileURLWithPath: "/tmp/sample.wav")
        let config = ASRProviderConfig(
            executablePath: executablePath,
            modelPath: "/models/ggml-base.bin",
            additionalArguments: "--threads 4 --prompt \"hello world\"",
            baseURL: "",
            apiKey: "",
            model: ""
        )

        let command = try LocalASRService.makeCommand(
            provider: .whisperCpp,
            config: config,
            audioFileURL: audioURL,
            languageCode: "zh-Hans"
        )

        XCTAssertEqual(command.executablePath, executablePath)
        XCTAssertEqual(
            command.arguments,
            ["-m", "/models/ggml-base.bin", "-f", "/tmp/sample.wav", "-l", "zh", "--threads", "4", "--prompt", "hello world"]
        )
    }

    func testSenseVoiceCommandUsesSenseVoiceArguments() throws {
        let executablePath = try makeExecutable()
        let audioURL = URL(fileURLWithPath: "/tmp/sample.wav")
        let config = ASRProviderConfig(
            executablePath: executablePath,
            modelPath: "/opt/models/sensevoice-small",
            additionalArguments: "--vad true",
            baseURL: "",
            apiKey: "",
            model: ""
        )

        let command = try LocalASRService.makeCommand(
            provider: .senseVoice,
            config: config,
            audioFileURL: audioURL,
            languageCode: "en-US"
        )

        XCTAssertEqual(
            command.arguments,
            ["-m", "/opt/models/sensevoice-small", "-f", "/tmp/sample.wav", "-l", "en", "-np", "-nt", "--vad", "true"]
        )
    }

    func testMakeCommandRejectsMissingModelPath() throws {
        let executablePath = try makeExecutable()
        let config = ASRProviderConfig(
            executablePath: executablePath,
            modelPath: "   ",
            additionalArguments: "",
            baseURL: "",
            apiKey: "",
            model: ""
        )

        XCTAssertThrowsError(
            try LocalASRService.makeCommand(
                provider: .whisperCpp,
                config: config,
                audioFileURL: URL(fileURLWithPath: "/tmp/sample.wav"),
                languageCode: "zh-Hans"
            )
        ) { error in
            XCTAssertEqual(error as? LocalASRError, .missingModelPath)
        }
    }

    func testMakeCommandRejectsCloudProvider() throws {
        let executablePath = try makeExecutable()
        let config = ASRProviderConfig(
            executablePath: executablePath,
            modelPath: "/models/unused",
            additionalArguments: "",
            baseURL: "",
            apiKey: "",
            model: ""
        )

        XCTAssertThrowsError(
            try LocalASRService.makeCommand(
                provider: .qwenASR,
                config: config,
                audioFileURL: URL(fileURLWithPath: "/tmp/sample.wav"),
                languageCode: "zh-Hans"
            )
        ) { error in
            XCTAssertEqual(error as? LocalASRError, .unsupportedProvider)
        }
    }

    func testTemporaryAudioCaptureWriterProducesCanonicalWAV() throws {
        let format = try XCTUnwrap(
            AVAudioFormat(
                commonFormat: .pcmFormatFloat32,
                sampleRate: 16_000,
                channels: 1,
                interleaved: false
            )
        )
        let buffer = try XCTUnwrap(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 4))
        buffer.frameLength = 4
        let samples: [Float] = [0.25, -0.25, 0.5, -0.5]
        for (index, sample) in samples.enumerated() {
            buffer.floatChannelData?[0][index] = sample
        }

        let writer = TemporaryAudioCaptureWriter()
        writer.append(buffer)
        let url = try writer.finalize()
        defer { try? FileManager.default.removeItem(at: url) }

        let data = try Data(contentsOf: url)
        XCTAssertEqual(String(data: data.prefix(4), encoding: .ascii), "RIFF")
        XCTAssertEqual(String(data: data.subdata(in: 8..<12), encoding: .ascii), "WAVE")
        XCTAssertEqual(String(data: data.subdata(in: 12..<16), encoding: .ascii), "fmt ")
        XCTAssertEqual(String(data: data.subdata(in: 36..<40), encoding: .ascii), "data")
    }

    private func makeExecutable() throws -> String {
        let url = FileManager.default.temporaryDirectory
            .appending(path: "voily-test-\(UUID().uuidString)")
            .appendingPathExtension("sh")
        try "#!/bin/sh\nexit 0\n".write(to: url, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: url.path)
        addTeardownBlock {
            try? FileManager.default.removeItem(at: url)
        }
        return url.path
    }
}
