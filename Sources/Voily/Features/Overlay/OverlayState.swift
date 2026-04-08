import Foundation

enum OverlayPhase: Equatable {
    case idle
    case recording
    case recordingPartial
    case transcribing
    case refining
    case translating
    case injecting
}

enum OverlayControls: Equatable {
    case none
    case confirmCancel
}

struct OverlayState: Equatable {
    var text: String
    var rmsLevel: Float
    var phase: OverlayPhase
    var controls: OverlayControls = .none

    static let idle = OverlayState(text: "", rmsLevel: 0, phase: .idle, controls: .none)
}
