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

    func testTranscriptAccumulatorAppendsIncrementalDeltasIntoLiveText() {
        var accumulator = TranscriptAccumulator()

        XCTAssertEqual(accumulator.appendDelta("你"), "你")
        XCTAssertEqual(accumulator.appendDelta("好"), "你好")
        XCTAssertEqual(accumulator.appendDelta("，世界"), "你好，世界")
        XCTAssertEqual(accumulator.finalText, "你好，世界")
    }

    func testPartialTranscriptDisplayThrottleEmitsFirstPartialImmediatelyAndBuffersRapidUpdates() {
        var throttle = PartialTranscriptDisplayThrottle(minimumInterval: 0.25)

        XCTAssertEqual(throttle.push("你", at: 0.00), "你")
        XCTAssertNil(throttle.push("你好", at: 0.05))
        XCTAssertNil(throttle.push("你好世", at: 0.10))
        XCTAssertEqual(throttle.pendingText, "你好世")
    }

    func testPartialTranscriptDisplayThrottleFlushesLatestBufferedTextAfterInterval() {
        var throttle = PartialTranscriptDisplayThrottle(minimumInterval: 0.25)

        XCTAssertEqual(throttle.push("你", at: 0.00), "你")
        XCTAssertNil(throttle.push("你好", at: 0.05))
        XCTAssertEqual(throttle.flush(at: 0.25), "你好")
        XCTAssertNil(throttle.pendingText)
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
                provider: .senseVoice,
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

    func testAutomaticMicrophoneSelectionPrefersUSBThenBuiltInThenBluetooth() {
        let catalog = AudioInputDeviceCatalog()
        let devices = [
            AudioInputDevice(uid: "bluetooth", name: "AirPods Pro", isDefault: true, transport: .bluetooth),
            AudioInputDevice(uid: "builtin", name: "MacBook Pro Microphone", isDefault: false, transport: .builtIn),
            AudioInputDevice(uid: "usb", name: "Shure MV7", isDefault: false, transport: .usb),
        ]

        XCTAssertEqual(catalog.automaticallySelectedInputDevice(from: devices)?.uid, "usb")
        XCTAssertEqual(catalog.automaticallySelectedInputDevice(from: Array(devices.dropLast()))?.uid, "builtin")
        XCTAssertEqual(catalog.automaticallySelectedInputDevice(from: [devices[0]])?.uid, "bluetooth")
    }

    func testDisplayNamePrefersExistingReadableShortName() {
        XCTAssertEqual(
            AudioInputDeviceCatalog.makeDisplayName(
                rawName: "DJI Mic Mini",
                manufacturer: "SZ DJI Technology Co., Ltd.",
                modelName: "Wireless Microphone Transmitter",
                modelUID: "DJI Mic Mini Transmitter",
                fallbackUID: "dji-mic"
            ),
            "DJI Mic Mini"
        )
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
