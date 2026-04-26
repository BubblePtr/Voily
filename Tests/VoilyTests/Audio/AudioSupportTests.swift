import XCTest
import AVFoundation
@testable import Voily

final class AudioSupportTests: XCTestCase {
    func testAudioPCMConverterProducesPCM16MonoData() throws {
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

        let data = try AudioPCMConverter.pcm16MonoData(from: buffer, targetSampleRate: 16_000)

        XCTAssertEqual(data.count, 8)
        XCTAssertEqual(Array(data), [255, 31, 0, 224, 255, 63, 0, 192])
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

}
