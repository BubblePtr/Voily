import AppKit
import SwiftUI

private enum OverlayPreviewScript {
    static let recordingSamples: [String] = [
        "现在来测试一下我自己的这个语音输入法",
        "现在来测试一下我自己的这个语音输入法，感觉其实还不错",
        "现在来测试一下我自己的这个语音输入法，感觉其实还不错，然后我再来看一下它滑动窗口有效果吧",
        "现在来测试一下我自己的这个语音输入法，感觉其实还不错，然后我再来看一下它滑动窗口有效果吧，感觉还是有点钝的",
        "现在来测试一下我自己的这个语音输入法，感觉其实还不错，然后我再来看一下它滑动窗口有效果吧，感觉还是有点钝的，就是不太平滑这个滑动窗口的效果"
    ]

    static let finalText = "现在来测试一下我自己的这个语音输入法，感觉其实还不错，然后我再来看一下它滑动窗口有效果吧，感觉还是有点钝的，就是不太平滑这个滑动窗口的效果。"

    static func state(at time: TimeInterval) -> OverlayState {
        let cycle = time.truncatingRemainder(dividingBy: 9.6)
        let rms = Float((sin(time * 3.6) + 1) * 0.5 * 0.75 + 0.15)

        switch cycle {
        case 0..<4.8:
            let progress = max(0, min(0.999, cycle / 4.8))
            let index = min(recordingSamples.count - 1, Int(progress * Double(recordingSamples.count)))
            return OverlayState(text: recordingSamples[index], rmsLevel: rms, phase: .recording)
        case 4.8..<6.4:
            return OverlayState(text: finalText, rmsLevel: rms * 0.22, phase: .transcribing)
        case 6.4..<7.5:
            return OverlayState(text: finalText, rmsLevel: 0, phase: .refining)
        default:
            return OverlayState(text: finalText, rmsLevel: 0, phase: .injecting)
        }
    }
}

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
                width: overlayWidth(for: state),
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
            let state = OverlayPreviewScript.state(at: time)

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

            Text("Mock transcript grows over time so the preview can show the sliding window behavior.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(16)
        .frame(width: 500)
    }
}

@available(macOS 26.0, *)
#Preview("Overlay Live Mock") {
    OverlayAnimatedPreview()
}
