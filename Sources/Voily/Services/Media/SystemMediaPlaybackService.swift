import AudioToolbox
import CoreAudio
import Foundation

struct AudioOutputMuteInterruptionToken: Equatable, Sendable {
    let deviceID: AudioDeviceID
    let restoreStrategy: AudioOutputRestoreStrategy
}

enum AudioOutputRestoreStrategy: Equatable, Sendable {
    case unmute
    case restoreVolume(Float32)
}

struct SystemAudioOutputState: Equatable, Sendable {
    let deviceID: AudioDeviceID
    let isMuted: Bool?
    let volume: Float32?
}

protocol SystemAudioOutputControlling: Sendable {
    func currentOutputState() -> SystemAudioOutputState?
    func currentDefaultOutputDeviceID() -> AudioDeviceID?
    func setMuted(_ isMuted: Bool, deviceID: AudioDeviceID) -> Bool
    func setVolume(_ value: Float32, deviceID: AudioDeviceID) -> Bool
}

final class SystemAudioOutputMuteService: @unchecked Sendable {
    private let silentVolumeThreshold: Float32 = 0.001
    private let outputController: any SystemAudioOutputControlling

    init(outputController: any SystemAudioOutputControlling = CoreAudioSystemAudioOutputController()) {
        self.outputController = outputController
    }

    func muteIfNeeded() async -> AudioOutputMuteInterruptionToken? {
        guard let state = outputController.currentOutputState() else {
            debugLog("System output mute skipped stateUnavailable=true")
            return nil
        }

        debugLog(
            "System output state before voice task deviceID=\(state.deviceID) muted=\(describeMute(state.isMuted)) volume=\(describeVolume(state.volume))"
        )

        if state.isMuted == true {
            debugLog("System output mute skipped alreadyMuted=true deviceID=\(state.deviceID)")
            return nil
        }

        if let volume = state.volume, volume <= silentVolumeThreshold {
            debugLog("System output mute skipped alreadySilent=true deviceID=\(state.deviceID)")
            return nil
        }

        if state.isMuted != nil {
            let didMute = outputController.setMuted(true, deviceID: state.deviceID)
            debugLog("System output mute action=muteProperty deviceID=\(state.deviceID) success=\(didMute)")
            guard didMute else {
                return nil
            }
            return AudioOutputMuteInterruptionToken(deviceID: state.deviceID, restoreStrategy: .unmute)
        }

        if let volume = state.volume {
            let didMute = outputController.setVolume(0, deviceID: state.deviceID)
            debugLog(
                "System output mute action=volumeZero deviceID=\(state.deviceID) previousVolume=\(describeVolume(volume)) success=\(didMute)"
            )
            guard didMute else {
                return nil
            }
            return AudioOutputMuteInterruptionToken(deviceID: state.deviceID, restoreStrategy: .restoreVolume(volume))
        }

        debugLog("System output mute skipped noWritableControl=true deviceID=\(state.deviceID)")
        return nil
    }

    func restoreIfNeeded(_ token: AudioOutputMuteInterruptionToken) async {
        guard let currentDeviceID = outputController.currentDefaultOutputDeviceID() else {
            debugLog("System output restore skipped defaultDeviceUnavailable=true expectedDeviceID=\(token.deviceID)")
            return
        }

        guard currentDeviceID == token.deviceID else {
            debugLog(
                "System output restore skipped deviceChanged expectedDeviceID=\(token.deviceID) observedDeviceID=\(currentDeviceID)"
            )
            return
        }

        switch token.restoreStrategy {
        case .unmute:
            let restored = outputController.setMuted(false, deviceID: token.deviceID)
            debugLog("System output restore action=unmute deviceID=\(token.deviceID) success=\(restored)")
        case let .restoreVolume(volume):
            let restored = outputController.setVolume(volume, deviceID: token.deviceID)
            debugLog(
                "System output restore action=restoreVolume deviceID=\(token.deviceID) volume=\(describeVolume(volume)) success=\(restored)"
            )
        }
    }

    private func describeMute(_ isMuted: Bool?) -> String {
        guard let isMuted else {
            return "unsupported"
        }
        return isMuted ? "true" : "false"
    }

    private func describeVolume(_ volume: Float32?) -> String {
        guard let volume else {
            return "unsupported"
        }
        return String(format: "%.3f", Double(volume))
    }
}

private final class CoreAudioSystemAudioOutputController: SystemAudioOutputControlling, @unchecked Sendable {
    func currentOutputState() -> SystemAudioOutputState? {
        guard let deviceID = currentDefaultOutputDeviceID() else {
            return nil
        }

        return SystemAudioOutputState(
            deviceID: deviceID,
            isMuted: readMutedState(deviceID: deviceID),
            volume: readVolume(deviceID: deviceID)
        )
    }

    func currentDefaultOutputDeviceID() -> AudioDeviceID? {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        guard let deviceID = readAudioDeviceID(
            objectID: AudioObjectID(kAudioObjectSystemObject),
            address: &address
        ) else {
            return nil
        }
        return deviceID == kAudioObjectUnknown ? nil : deviceID
    }

    func setMuted(_ isMuted: Bool, deviceID: AudioDeviceID) -> Bool {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyMute,
            mScope: kAudioDevicePropertyScopeOutput,
            mElement: kAudioObjectPropertyElementMain
        )
        var muteValue: UInt32 = isMuted ? 1 : 0
        return writeUInt32Property(objectID: deviceID, address: &address, value: &muteValue)
    }

    func setVolume(_ value: Float32, deviceID: AudioDeviceID) -> Bool {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwareServiceDeviceProperty_VirtualMainVolume,
            mScope: kAudioDevicePropertyScopeOutput,
            mElement: kAudioObjectPropertyElementMain
        )
        var volume = value
        return writeFloat32Property(objectID: deviceID, address: &address, value: &volume)
    }

    private func readMutedState(deviceID: AudioDeviceID) -> Bool? {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyMute,
            mScope: kAudioDevicePropertyScopeOutput,
            mElement: kAudioObjectPropertyElementMain
        )
        guard let muteValue = readUInt32Property(objectID: deviceID, address: &address) else {
            return nil
        }
        return muteValue != 0
    }

    private func readVolume(deviceID: AudioDeviceID) -> Float32? {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwareServiceDeviceProperty_VirtualMainVolume,
            mScope: kAudioDevicePropertyScopeOutput,
            mElement: kAudioObjectPropertyElementMain
        )
        return readFloat32Property(objectID: deviceID, address: &address)
    }

    private func readAudioDeviceID(
        objectID: AudioObjectID,
        address: inout AudioObjectPropertyAddress
    ) -> AudioDeviceID? {
        guard AudioObjectHasProperty(objectID, &address) else {
            return nil
        }

        var value = AudioDeviceID(0)
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        let status = AudioObjectGetPropertyData(objectID, &address, 0, nil, &size, &value)
        guard status == noErr else {
            return nil
        }
        return value
    }

    private func readUInt32Property(
        objectID: AudioObjectID,
        address: inout AudioObjectPropertyAddress
    ) -> UInt32? {
        guard AudioObjectHasProperty(objectID, &address) else {
            return nil
        }

        var value: UInt32 = 0
        var size = UInt32(MemoryLayout<UInt32>.size)
        let status = AudioObjectGetPropertyData(objectID, &address, 0, nil, &size, &value)
        guard status == noErr else {
            return nil
        }
        return value
    }

    private func readFloat32Property(
        objectID: AudioObjectID,
        address: inout AudioObjectPropertyAddress
    ) -> Float32? {
        guard AudioObjectHasProperty(objectID, &address) else {
            return nil
        }

        var value: Float32 = 0
        var size = UInt32(MemoryLayout<Float32>.size)
        let status = AudioObjectGetPropertyData(objectID, &address, 0, nil, &size, &value)
        guard status == noErr else {
            return nil
        }
        return value
    }

    private func writeUInt32Property(
        objectID: AudioObjectID,
        address: inout AudioObjectPropertyAddress,
        value: inout UInt32
    ) -> Bool {
        guard isWritableProperty(objectID: objectID, address: &address) else {
            return false
        }

        let size = UInt32(MemoryLayout<UInt32>.size)
        let status = AudioObjectSetPropertyData(objectID, &address, 0, nil, size, &value)
        return status == noErr
    }

    private func writeFloat32Property(
        objectID: AudioObjectID,
        address: inout AudioObjectPropertyAddress,
        value: inout Float32
    ) -> Bool {
        guard isWritableProperty(objectID: objectID, address: &address) else {
            return false
        }

        let size = UInt32(MemoryLayout<Float32>.size)
        let status = AudioObjectSetPropertyData(objectID, &address, 0, nil, size, &value)
        return status == noErr
    }

    private func isWritableProperty(
        objectID: AudioObjectID,
        address: inout AudioObjectPropertyAddress
    ) -> Bool {
        guard AudioObjectHasProperty(objectID, &address) else {
            return false
        }

        var isSettable: DarwinBoolean = false
        return AudioObjectIsPropertySettable(objectID, &address, &isSettable) == noErr && isSettable.boolValue
    }
}
