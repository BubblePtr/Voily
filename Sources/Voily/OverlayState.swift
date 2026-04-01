import Foundation

enum OverlayPhase: Equatable {
    case idle
    case recording
    case transcribing
    case refining
    case injecting
}

struct OverlayState: Equatable {
    var text: String
    var rmsLevel: Float
    var phase: OverlayPhase

    static let idle = OverlayState(text: "", rmsLevel: 0, phase: .idle)
}
