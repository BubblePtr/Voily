import CoreAudio
import XCTest
@testable import Voily

final class SystemMediaPlaybackServiceTests: XCTestCase {
    func testMuteIfNeededReturnsNilWhenOutputIsAlreadyMuted() async {
        let output = FakeSystemAudioOutputController(
            defaultDeviceID: 11,
            state: SystemAudioOutputState(deviceID: 11, isMuted: true, volume: 0.6)
        )
        let service = SystemAudioOutputMuteService(outputController: output)

        let token = await service.muteIfNeeded()

        XCTAssertNil(token)
        XCTAssertEqual(output.setMutedCalls, [])
        XCTAssertEqual(output.setVolumeCalls, [])
    }

    func testMuteIfNeededReturnsNilWhenOutputVolumeIsAlreadyZero() async {
        let output = FakeSystemAudioOutputController(
            defaultDeviceID: 11,
            state: SystemAudioOutputState(deviceID: 11, isMuted: nil, volume: 0)
        )
        let service = SystemAudioOutputMuteService(outputController: output)

        let token = await service.muteIfNeeded()

        XCTAssertNil(token)
        XCTAssertEqual(output.setMutedCalls, [])
        XCTAssertEqual(output.setVolumeCalls, [])
    }

    func testMuteIfNeededUsesMutePropertyWhenAvailable() async {
        let output = FakeSystemAudioOutputController(
            defaultDeviceID: 23,
            state: SystemAudioOutputState(deviceID: 23, isMuted: false, volume: 0.8)
        )
        let service = SystemAudioOutputMuteService(outputController: output)

        let token = await service.muteIfNeeded()

        XCTAssertEqual(token?.deviceID, 23)
        XCTAssertEqual(token?.restoreStrategy, .unmute)
        XCTAssertEqual(output.setMutedCalls, [.init(deviceID: 23, isMuted: true)])
        XCTAssertEqual(output.setVolumeCalls, [])
    }

    func testMuteIfNeededFallsBackToZeroVolumeWhenMuteUnsupported() async {
        let output = FakeSystemAudioOutputController(
            defaultDeviceID: 23,
            state: SystemAudioOutputState(deviceID: 23, isMuted: nil, volume: 0.42)
        )
        let service = SystemAudioOutputMuteService(outputController: output)

        let token = await service.muteIfNeeded()

        XCTAssertEqual(token?.deviceID, 23)
        XCTAssertEqual(token?.restoreStrategy, .restoreVolume(0.42))
        XCTAssertEqual(output.setMutedCalls, [])
        XCTAssertEqual(output.setVolumeCalls, [.init(deviceID: 23, volume: 0)])
    }

    func testMuteIfNeededReturnsNilWhenMuteAndVolumeControlsAreUnavailable() async {
        let output = FakeSystemAudioOutputController(
            defaultDeviceID: 23,
            state: SystemAudioOutputState(deviceID: 23, isMuted: nil, volume: nil)
        )
        let service = SystemAudioOutputMuteService(outputController: output)

        let token = await service.muteIfNeeded()

        XCTAssertNil(token)
        XCTAssertEqual(output.setMutedCalls, [])
        XCTAssertEqual(output.setVolumeCalls, [])
    }

    func testRestoreIfNeededUnmutesSameDevice() async {
        let output = FakeSystemAudioOutputController(
            defaultDeviceID: 31,
            state: SystemAudioOutputState(deviceID: 31, isMuted: false, volume: 0.7)
        )
        let service = SystemAudioOutputMuteService(outputController: output)
        let token = await service.muteIfNeeded()

        XCTAssertNotNil(token)
        if let token {
            await service.restoreIfNeeded(token)
        }

        XCTAssertEqual(output.setMutedCalls, [.init(deviceID: 31, isMuted: true), .init(deviceID: 31, isMuted: false)])
        XCTAssertEqual(output.setVolumeCalls, [])
    }

    func testRestoreIfNeededRestoresPreviousVolumeOnSameDevice() async {
        let output = FakeSystemAudioOutputController(
            defaultDeviceID: 31,
            state: SystemAudioOutputState(deviceID: 31, isMuted: nil, volume: 0.35)
        )
        let service = SystemAudioOutputMuteService(outputController: output)
        let token = await service.muteIfNeeded()

        XCTAssertNotNil(token)
        if let token {
            await service.restoreIfNeeded(token)
        }

        XCTAssertEqual(output.setMutedCalls, [])
        XCTAssertEqual(output.setVolumeCalls, [.init(deviceID: 31, volume: 0), .init(deviceID: 31, volume: 0.35)])
    }

    func testRestoreIfNeededSkipsWhenDefaultOutputDeviceChanges() async {
        let output = FakeSystemAudioOutputController(
            defaultDeviceID: 31,
            state: SystemAudioOutputState(deviceID: 31, isMuted: false, volume: 0.7)
        )
        let service = SystemAudioOutputMuteService(outputController: output)
        let token = await service.muteIfNeeded()
        output.defaultDeviceID = 32

        XCTAssertNotNil(token)
        if let token {
            await service.restoreIfNeeded(token)
        }

        XCTAssertEqual(output.setMutedCalls, [.init(deviceID: 31, isMuted: true)])
        XCTAssertEqual(output.setVolumeCalls, [])
    }

    func testMuteIfNeededReturnsNilWhenMuteWriteFails() async {
        let output = FakeSystemAudioOutputController(
            defaultDeviceID: 31,
            state: SystemAudioOutputState(deviceID: 31, isMuted: false, volume: 0.7)
        )
        output.shouldFailSetMuted = true
        let service = SystemAudioOutputMuteService(outputController: output)

        let token = await service.muteIfNeeded()

        XCTAssertNil(token)
        XCTAssertEqual(output.setMutedCalls, [.init(deviceID: 31, isMuted: true)])
    }

    func testRestoreIfNeededSwallowsVolumeRestoreFailure() async {
        let output = FakeSystemAudioOutputController(
            defaultDeviceID: 31,
            state: SystemAudioOutputState(deviceID: 31, isMuted: nil, volume: 0.7)
        )
        output.failVolumeWriteValues.insert(0.7)
        let service = SystemAudioOutputMuteService(outputController: output)

        let token = await service.muteIfNeeded()

        XCTAssertNotNil(token)
        if let token {
            await service.restoreIfNeeded(token)
        }

        XCTAssertEqual(output.setVolumeCalls, [.init(deviceID: 31, volume: 0), .init(deviceID: 31, volume: 0.7)])
    }
}

private final class FakeSystemAudioOutputController: SystemAudioOutputControlling, @unchecked Sendable {
    var defaultDeviceID: AudioDeviceID?
    var stateByDeviceID: [AudioDeviceID: SystemAudioOutputState]
    var shouldFailSetMuted = false
    var failVolumeWriteValues = Set<Float32>()
    private(set) var setMutedCalls: [MuteCall] = []
    private(set) var setVolumeCalls: [VolumeCall] = []

    init(defaultDeviceID: AudioDeviceID?, state: SystemAudioOutputState) {
        self.defaultDeviceID = defaultDeviceID
        stateByDeviceID = [state.deviceID: state]
    }

    func currentOutputState() -> SystemAudioOutputState? {
        guard let defaultDeviceID else { return nil }
        return stateByDeviceID[defaultDeviceID]
    }

    func currentDefaultOutputDeviceID() -> AudioDeviceID? {
        defaultDeviceID
    }

    func setMuted(_ isMuted: Bool, deviceID: AudioDeviceID) -> Bool {
        setMutedCalls.append(.init(deviceID: deviceID, isMuted: isMuted))
        guard !shouldFailSetMuted else { return false }
        guard var state = stateByDeviceID[deviceID], state.isMuted != nil else { return false }
        state = SystemAudioOutputState(deviceID: deviceID, isMuted: isMuted, volume: state.volume)
        stateByDeviceID[deviceID] = state
        return true
    }

    func setVolume(_ value: Float32, deviceID: AudioDeviceID) -> Bool {
        setVolumeCalls.append(.init(deviceID: deviceID, volume: value))
        guard !failVolumeWriteValues.contains(value) else { return false }
        guard var state = stateByDeviceID[deviceID], state.volume != nil else { return false }
        state = SystemAudioOutputState(deviceID: deviceID, isMuted: state.isMuted, volume: value)
        stateByDeviceID[deviceID] = state
        return true
    }
}

private struct MuteCall: Equatable {
    let deviceID: AudioDeviceID
    let isMuted: Bool
}

private struct VolumeCall: Equatable {
    let deviceID: AudioDeviceID
    let volume: Float32
}
