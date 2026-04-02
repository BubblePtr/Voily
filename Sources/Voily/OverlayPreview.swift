import AppKit
import SwiftUI

private enum OverlayPreviewBackground: String, CaseIterable, Identifiable {
    case sea
    case pink
    case space

    var id: String { rawValue }

    var title: String {
        switch self {
        case .pink:
            return "Pink"
        case .space:
            return "Space"
        case .sea:
            return "Sea"
        }
    }

    var imagePath: String {
        switch self {
        case .sea:
            return "/Users/void/code/opensource/voily/Resources/PreviewAssets/preview-bg-sea.jpg"
        case .pink:
            return "/Users/void/code/opensource/voily/Resources/PreviewAssets/preview-bg-pink.jpg"
        case .space:
            return "/Users/void/code/opensource/voily/Resources/PreviewAssets/preview-bg-space.jpg"
        }
    }
}

private enum OverlayPreviewAssets {
    static let images: [OverlayPreviewBackground: NSImage] = {
        Dictionary(
            uniqueKeysWithValues: OverlayPreviewBackground.allCases.compactMap { background in
                guard let image = NSImage(contentsOfFile: background.imagePath) else {
                    return nil
                }

                return (background, image)
            }
        )
    }()
}

@available(macOS 26.0, *)
private struct OverlayPreviewFrame: View {
    let state: OverlayState
    let previewTime: TimeInterval?
    let animateInPreview: Bool
    let background: OverlayPreviewBackground

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
        GeometryReader { geometry in
            Group {
                if let backgroundImage {
                    Image(nsImage: backgroundImage)
                        .resizable()
                        .scaledToFill()
                } else {
                    Color.black
                }
            }
            .frame(width: geometry.size.width, height: geometry.size.height)
            .clipped()
        }
    }

    private var backgroundImage: NSImage? {
        OverlayPreviewAssets.images[background]
    }
}

@available(macOS 26.0, *)
private struct OverlayAnimatedPreviewCanvas: View {
    let background: OverlayPreviewBackground

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1.0 / 24.0)) { timeline in
            let time = timeline.date.timeIntervalSinceReferenceDate
            let rms = Float((sin(time * 3.6) + 1) * 0.5 * 0.75 + 0.15)
            let state = OverlayState(text: "Listening…", rmsLevel: rms, phase: .recording)

            OverlayPreviewFrame(
                state: state,
                previewTime: nil,
                animateInPreview: true,
                background: background
            )
            .frame(width: 460, height: 280)
            .clipShape(RoundedRectangle(cornerRadius: 16))
            .compositingGroup()
        }
    }
}

@available(macOS 26.0, *)
private struct OverlayAnimatedPreview: View {
    @State private var selectedBackground: OverlayPreviewBackground = .sea

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Picker("Background", selection: $selectedBackground) {
                ForEach(OverlayPreviewBackground.allCases) { background in
                    Text(background.title)
                        .tag(background)
                }
            }
            .pickerStyle(.segmented)

            OverlayAnimatedPreviewCanvas(background: selectedBackground)
                .id(selectedBackground)
        }
        .padding(16)
        .frame(width: 500)
    }
}

@available(macOS 26.0, *)
#Preview("Overlay Live Mock") {
    OverlayAnimatedPreview()
}
