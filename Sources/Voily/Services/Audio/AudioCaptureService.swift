import AVFoundation
import CoreAudio

struct AudioInputDevice: Identifiable, Equatable {
    enum Transport: Equatable {
        case usb
        case builtIn
        case bluetooth
        case other

        var automaticSelectionPriority: Int {
            switch self {
            case .usb:
                return 0
            case .builtIn:
                return 1
            case .bluetooth:
                return 2
            case .other:
                return 3
            }
        }
    }

    let uid: String
    let name: String
    let isDefault: Bool
    let transport: Transport

    var id: String { uid }
}

struct AudioInputDeviceCatalog {
    func availableInputDevices() -> [AudioInputDevice] {
        let defaultDeviceID = defaultInputDeviceID()

        return allInputDeviceIDs().compactMap { deviceID in
            guard let uid = stringProperty(
                for: deviceID,
                selector: kAudioDevicePropertyDeviceUID,
                scope: kAudioObjectPropertyScopeGlobal
            ) else {
                return nil
            }

            let rawName = stringProperty(
                for: deviceID,
                selector: kAudioObjectPropertyName,
                scope: kAudioObjectPropertyScopeGlobal
            )
            let manufacturer = stringProperty(
                for: deviceID,
                selector: kAudioObjectPropertyManufacturer,
                scope: kAudioObjectPropertyScopeGlobal
            )
            let modelName = stringProperty(
                for: deviceID,
                selector: kAudioObjectPropertyModelName,
                scope: kAudioObjectPropertyScopeGlobal
            )
            let modelUID = stringProperty(
                for: deviceID,
                selector: kAudioDevicePropertyModelUID,
                scope: kAudioObjectPropertyScopeGlobal
            )
            let transportType = transportType(for: deviceID)

            return AudioInputDevice(
                uid: uid,
                name: Self.makeDisplayName(
                    rawName: rawName,
                    manufacturer: manufacturer,
                    modelName: modelName,
                    modelUID: modelUID,
                    fallbackUID: uid
                ),
                isDefault: deviceID == defaultDeviceID,
                transport: Self.transport(from: transportType)
            )
        }
        .sorted(by: sortDevices)
    }

    func deviceID(forUID uid: String) -> AudioDeviceID? {
        allInputDeviceIDs().first {
            stringProperty(
                for: $0,
                selector: kAudioDevicePropertyDeviceUID,
                scope: kAudioObjectPropertyScopeGlobal
            ) == uid
        }
    }

    func defaultInputDeviceID() -> AudioDeviceID? {
        property(
            objectID: AudioObjectID(kAudioObjectSystemObject),
            selector: kAudioHardwarePropertyDefaultInputDevice,
            scope: kAudioObjectPropertyScopeGlobal
        )
    }

    func automaticallySelectedInputDevice(from devices: [AudioInputDevice]? = nil) -> AudioInputDevice? {
        let candidates = devices ?? availableInputDevices()
        return candidates.min(by: automaticSelectionSort)
    }

    private func allInputDeviceIDs() -> [AudioDeviceID] {
        let systemObjectID = AudioObjectID(kAudioObjectSystemObject)
        guard
            var devices = deviceIDsProperty(
                objectID: systemObjectID,
                selector: kAudioHardwarePropertyDevices,
                scope: kAudioObjectPropertyScopeGlobal
            )
        else {
            return []
        }

        devices.removeAll { inputChannelCount(for: $0) == 0 }
        return devices
    }

    private func inputChannelCount(for deviceID: AudioDeviceID) -> Int {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyStreamConfiguration,
            mScope: kAudioDevicePropertyScopeInput,
            mElement: kAudioObjectPropertyElementMain
        )
        var dataSize: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(deviceID, &address, 0, nil, &dataSize) == noErr else {
            return 0
        }

        let bufferListPointer = UnsafeMutableRawPointer.allocate(
            byteCount: Int(dataSize),
            alignment: MemoryLayout<AudioBufferList>.alignment
        )
        defer { bufferListPointer.deallocate() }

        guard AudioObjectGetPropertyData(deviceID, &address, 0, nil, &dataSize, bufferListPointer) == noErr else {
            return 0
        }

        let audioBufferList = bufferListPointer.assumingMemoryBound(to: AudioBufferList.self)
        let buffers = UnsafeMutableAudioBufferListPointer(audioBufferList)
        return buffers.reduce(0) { partialResult, buffer in
            partialResult + Int(buffer.mNumberChannels)
        }
    }

    private func transportType(for deviceID: AudioDeviceID) -> UInt32? {
        property(
            objectID: deviceID,
            selector: kAudioDevicePropertyTransportType,
            scope: kAudioObjectPropertyScopeGlobal
        )
    }

    private func stringProperty(
        for objectID: AudioObjectID,
        selector: AudioObjectPropertySelector,
        scope: AudioObjectPropertyScope
    ) -> String? {
        var address = AudioObjectPropertyAddress(
            mSelector: selector,
            mScope: scope,
            mElement: kAudioObjectPropertyElementMain
        )
        var value: Unmanaged<CFString>?
        var dataSize = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)

        guard AudioObjectGetPropertyData(objectID, &address, 0, nil, &dataSize, &value) == noErr else {
            return nil
        }

        return value?.takeUnretainedValue() as String?
    }

    private func property<Value>(
        objectID: AudioObjectID,
        selector: AudioObjectPropertySelector,
        scope: AudioObjectPropertyScope
    ) -> Value? {
        var address = AudioObjectPropertyAddress(
            mSelector: selector,
            mScope: scope,
            mElement: kAudioObjectPropertyElementMain
        )
        var dataSize = UInt32(MemoryLayout<Value>.size)
        let valuePointer = UnsafeMutableRawPointer.allocate(
            byteCount: MemoryLayout<Value>.size,
            alignment: MemoryLayout<Value>.alignment
        )
        defer { valuePointer.deallocate() }

        guard AudioObjectGetPropertyData(objectID, &address, 0, nil, &dataSize, valuePointer) == noErr else {
            return nil
        }

        return valuePointer.load(as: Value.self)
    }

    private func deviceIDsProperty(
        objectID: AudioObjectID,
        selector: AudioObjectPropertySelector,
        scope: AudioObjectPropertyScope
    ) -> [AudioDeviceID]? {
        var address = AudioObjectPropertyAddress(
            mSelector: selector,
            mScope: scope,
            mElement: kAudioObjectPropertyElementMain
        )
        var dataSize: UInt32 = 0

        guard AudioObjectGetPropertyDataSize(objectID, &address, 0, nil, &dataSize) == noErr else {
            return nil
        }

        let count = Int(dataSize) / MemoryLayout<AudioDeviceID>.stride
        var values = Array(repeating: AudioDeviceID(0), count: count)

        guard AudioObjectGetPropertyData(objectID, &address, 0, nil, &dataSize, &values) == noErr else {
            return nil
        }

        return values
    }

    private func sortDevices(_ lhs: AudioInputDevice, _ rhs: AudioInputDevice) -> Bool {
        if lhs.transport.automaticSelectionPriority != rhs.transport.automaticSelectionPriority {
            return lhs.transport.automaticSelectionPriority < rhs.transport.automaticSelectionPriority
        }
        if lhs.isDefault != rhs.isDefault {
            return lhs.isDefault
        }
        return lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
    }

    private func automaticSelectionSort(_ lhs: AudioInputDevice, _ rhs: AudioInputDevice) -> Bool {
        if lhs.transport.automaticSelectionPriority != rhs.transport.automaticSelectionPriority {
            return lhs.transport.automaticSelectionPriority < rhs.transport.automaticSelectionPriority
        }
        if lhs.isDefault != rhs.isDefault {
            return lhs.isDefault
        }
        return lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
    }

    private static func transport(from rawValue: UInt32?) -> AudioInputDevice.Transport {
        switch rawValue {
        case kAudioDeviceTransportTypeUSB:
            return .usb
        case kAudioDeviceTransportTypeBuiltIn:
            return .builtIn
        case kAudioDeviceTransportTypeBluetooth, kAudioDeviceTransportTypeBluetoothLE:
            return .bluetooth
        default:
            return .other
        }
    }

    static func makeDisplayName(
        rawName: String?,
        manufacturer: String?,
        modelName: String?,
        modelUID: String?,
        fallbackUID: String
    ) -> String {
        let manufacturer = normalizeManufacturer(manufacturer)
        let rawName = normalizeComponent(rawName)
        let modelName = normalizeComponent(modelName)
        let modelUID = normalizeComponent(modelUID)

        if let rawName, !isGenericDeviceName(rawName) {
            return rawName
        }

        let base = modelName ?? modelUID ?? rawName ?? fallbackUID

        guard let manufacturer, !manufacturer.isEmpty else {
            return base
        }

        if base.localizedCaseInsensitiveContains(manufacturer) {
            return base
        }

        if manufacturer == "Apple" {
            return base
        }

        return "\(manufacturer) \(base)"
    }

    private static func normalizeManufacturer(_ value: String?) -> String? {
        guard let normalized = normalizeComponent(value) else {
            return nil
        }

        let suffixes = [" Inc.", " Inc", ", Inc.", ", Inc", " Corporation", " Corp."]
        for suffix in suffixes where normalized.hasSuffix(suffix) {
            return String(normalized.dropLast(suffix.count))
        }
        return normalized
    }

    private static func normalizeComponent(_ value: String?) -> String? {
        guard let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines), !trimmed.isEmpty else {
            return nil
        }
        if trimmed == "-" || trimmed == "?" {
            return nil
        }
        return trimmed
    }

    private static func isGenericDeviceName(_ value: String) -> Bool {
        let normalized = value.lowercased()
        let genericNames = [
            "usb audio device",
            "usb microphone",
            "microphone",
            "external microphone",
            "wireless microphone",
            "bluetooth microphone",
        ]
        return genericNames.contains(normalized)
    }
}

final class AudioInputDeviceMonitor {
    private let systemObjectID = AudioObjectID(kAudioObjectSystemObject)
    private let queue = DispatchQueue(label: "Voily.AudioInputDeviceMonitor")
    private let selectors: [AudioObjectPropertySelector] = [
        kAudioHardwarePropertyDevices,
        kAudioHardwarePropertyDefaultInputDevice,
    ]

    private var listenerBlocks: [AudioObjectPropertySelector: AudioObjectPropertyListenerBlock] = [:]
    private var isMonitoring = false

    func start(onChange: @escaping @MainActor () -> Void) {
        stop()

        for selector in selectors {
            var address = AudioObjectPropertyAddress(
                mSelector: selector,
                mScope: kAudioObjectPropertyScopeGlobal,
                mElement: kAudioObjectPropertyElementMain
            )
            let block: AudioObjectPropertyListenerBlock = { _, _ in
                Task { @MainActor in
                    onChange()
                }
            }
            let status = AudioObjectAddPropertyListenerBlock(systemObjectID, &address, queue, block)
            guard status == noErr else {
                debugLog("Audio input monitor add listener failed selector=\(selector) status=\(status)")
                continue
            }
            listenerBlocks[selector] = block
        }

        isMonitoring = !listenerBlocks.isEmpty
    }

    func stop() {
        guard isMonitoring else { return }

        for selector in selectors {
            guard let block = listenerBlocks[selector] else { continue }
            var address = AudioObjectPropertyAddress(
                mSelector: selector,
                mScope: kAudioObjectPropertyScopeGlobal,
                mElement: kAudioObjectPropertyElementMain
            )
            let status = AudioObjectRemovePropertyListenerBlock(systemObjectID, &address, queue, block)
            if status != noErr {
                debugLog("Audio input monitor remove listener failed selector=\(selector) status=\(status)")
            }
        }

        listenerBlocks.removeAll()
        isMonitoring = false
    }

    deinit {
        stop()
    }
}

final class AudioCaptureService {
    enum AudioCaptureError: Error {
        case unavailableInput
    }

    private let engine = AVAudioEngine()
    private let deviceCatalog = AudioInputDeviceCatalog()
    private var isRunning = false

    func start(
        inputDeviceUID: String?,
        onBuffer: @escaping (AVAudioPCMBuffer) -> Void,
        onLevel: @escaping (Float) -> Void
    ) throws {
        guard !isRunning else { return }

        let inputNode = engine.inputNode
        configureInputDevice(for: inputNode, preferredUID: inputDeviceUID)
        let format = inputNode.inputFormat(forBus: 0)
        guard format.sampleRate > 0 else {
            throw AudioCaptureError.unavailableInput
        }

        inputNode.removeTap(onBus: 0)
        inputNode.installTap(onBus: 0, bufferSize: 2048, format: format) { buffer, _ in
            onBuffer(buffer)

            let rms = Self.calculateRMS(buffer: buffer)
            onLevel(rms)
        }

        engine.prepare()
        try engine.start()
        isRunning = true
    }

    func stop() {
        guard isRunning else { return }
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        isRunning = false
    }

    private func configureInputDevice(for inputNode: AVAudioInputNode, preferredUID: String?) {
        if let preferredUID, !preferredUID.isEmpty {
            if let preferredDeviceID = deviceCatalog.deviceID(forUID: preferredUID) {
                do {
                    try inputNode.auAudioUnit.setDeviceID(preferredDeviceID)
                    return
                } catch {
                    debugLog("Preferred microphone selection failed uid=\(preferredUID) error=\(error.localizedDescription)")
                }
            } else {
                debugLog("Preferred microphone unavailable uid=\(preferredUID) fallback=true")
            }
        }

        if let automaticDevice = deviceCatalog.automaticallySelectedInputDevice(),
           let automaticDeviceID = deviceCatalog.deviceID(forUID: automaticDevice.uid) {
            do {
                try inputNode.auAudioUnit.setDeviceID(automaticDeviceID)
                debugLog("Automatic microphone selected uid=\(automaticDevice.uid) name=\(automaticDevice.name)")
                return
            } catch {
                debugLog("Automatic microphone selection failed uid=\(automaticDevice.uid) error=\(error.localizedDescription)")
            }
        }

        guard let defaultDeviceID = deviceCatalog.defaultInputDeviceID() else {
            debugLog("Automatic microphone fallback unavailable")
            return
        }

        do {
            try inputNode.auAudioUnit.setDeviceID(defaultDeviceID)
            debugLog("Automatic microphone fallback chose system default")
        } catch {
            debugLog("Default microphone selection failed error=\(error.localizedDescription)")
        }
    }

    private static func calculateRMS(buffer: AVAudioPCMBuffer) -> Float {
        guard let channelData = buffer.floatChannelData else { return 0 }

        let channel = channelData[0]
        let frameCount = Int(buffer.frameLength)
        guard frameCount > 0 else { return 0 }

        var sum: Float = 0
        for index in 0 ..< frameCount {
            let value = channel[index]
            sum += value * value
        }

        let rms = sqrt(sum / Float(frameCount))
        return min(max(rms * 10, 0), 1)
    }
}
