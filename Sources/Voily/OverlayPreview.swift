import SwiftUI

private let overlayPreviewBackgroundImagePath = "/Users/void/code/opensource/voily/Resources/PreviewAssets/overlay-preview-background.jpg"

@available(macOS 26.0, *)
private struct OverlayPreviewFrame: View {
    let state: OverlayState
    let previewTime: TimeInterval?
    let animateInPreview: Bool

    var body: some View {
        let model = OverlayViewModel()
        model.state = state

        return ZStack {
            previewBackground

            OverlayRootView(
                model: model,
                animateInPreview: animateInPreview,
                previewTime: previewTime
            )
            .frame(
                width: overlayWidth(for: OverlayRootView.displayText(for: state)),
                height: overlayHeight
            )
        }
    }

    private var previewBackground: some View {
        Group {
            if let backgroundImage {
                Image(nsImage: backgroundImage)
                    .resizable()
                    .scaledToFill()
            } else {
                Color.black
            }
        }
        .clipped()
    }

    private var backgroundImage: NSImage? {
        NSImage(contentsOfFile: overlayPreviewBackgroundImagePath)
    }
}

@available(macOS 26.0, *)
private struct OverlayAnimatedPreview: View {
    var body: some View {
        TimelineView(.animation) { timeline in
            let time = timeline.date.timeIntervalSinceReferenceDate
            let rms = Float((sin(time * 3.6) + 1) * 0.5 * 0.75 + 0.15)
            let state = OverlayState(text: "Listening…", rmsLevel: rms, phase: .recording)

            OverlayPreviewFrame(
                state: state,
                previewTime: nil,
                animateInPreview: true
            )
            .frame(width: 460, height: 220)
        }
    }
}

@available(macOS 26.0, *)
#Preview("Overlay Live Mock") {
    OverlayAnimatedPreview()
}
