import AppKit
import SwiftUI
import Observation

let overlayHeight: CGFloat = 52
private let overlayMinimumWidth: CGFloat = 160
private let overlayMaximumWidth: CGFloat = 560
private let overlayHorizontalPadding: CGFloat = 18
private let overlayWaveformWidth: CGFloat = 32
private let overlayWaveformSpacing: CGFloat = 12

func overlayWidth(for text: String) -> CGFloat {
    let attributes: [NSAttributedString.Key: Any] = [
        .font: NSFont.systemFont(ofSize: 16, weight: .medium),
    ]

    let textWidth = (text as NSString).size(withAttributes: attributes).width
    let chromeWidth = (overlayHorizontalPadding * 2) + overlayWaveformWidth + overlayWaveformSpacing + 26
    return min(max(textWidth + chromeWidth, overlayMinimumWidth), overlayMaximumWidth)
}

@available(macOS 26.0, *)
@MainActor
final class OverlayPanelController {
    private let model = OverlayViewModel()
    private let panel: NSPanel
    private let hostView: NSHostingView<OverlayRootView>
    private var hideTask: Task<Void, Never>?

    init() {
        let rootView = OverlayRootView(model: model)
        hostView = NSHostingView(rootView: rootView)

        panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 240, height: overlayHeight),
            styleMask: [.nonactivatingPanel, .borderless],
            backing: .buffered,
            defer: false
        )

        panel.level = .statusBar
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        panel.hidesOnDeactivate = false
        panel.ignoresMouseEvents = true
        panel.contentView = TransparentContainerView(contentView: hostView)
        panel.orderOut(nil)
    }

    func show(state: OverlayState) {
        debugLog("OverlayPanelController.show phase=\(state.phase) textLength=\(state.text.count)")
        hideTask?.cancel()
        model.state = state
        panel.setFrame(frame(for: state), display: true)
        positionPanel()

        if !panel.isVisible {
            panel.alphaValue = 0
            panel.setFrameOrigin(frame(for: state).origin)
            panel.orderFrontRegardless()
            panel.animator().alphaValue = 1

            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.35
                context.timingFunction = CAMediaTimingFunction(name: .easeOut)
                panel.animator().setFrame(frame(for: state), display: true)
            }
        } else {
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.25
                context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
                panel.animator().setFrame(frame(for: state), display: true)
            }
        }
    }

    func hide() {
        debugLog("OverlayPanelController.hide()")
        hideTask?.cancel()
        hideTask = Task { @MainActor in
            guard panel.isVisible else { return }

            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.22
                context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
                panel.animator().alphaValue = 0
                let currentFrame = panel.frame
                let insetFrame = currentFrame.insetBy(dx: -12, dy: -4)
                panel.animator().setFrame(insetFrame, display: true)
            } completionHandler: {
                Task { @MainActor in
                    self.panel.orderOut(nil)
                    self.panel.alphaValue = 1
                    self.model.state = .idle
                }
            }
        }
    }

    private func frame(for state: OverlayState) -> NSRect {
        let width = overlayWidth(for: OverlayRootView.displayText(for: state))
        let visibleFrame = NSScreen.main?.visibleFrame ?? .zero
        let originX = visibleFrame.midX - (width / 2)
        let originY = visibleFrame.minY + 28
        return NSRect(x: originX, y: originY, width: width, height: overlayHeight)
    }

    private func positionPanel() {
        let frame = frame(for: model.state)
        panel.setFrameOrigin(frame.origin)
    }
}

@MainActor
@Observable
final class OverlayViewModel {
    var state: OverlayState = .idle
}

private final class TransparentContainerView: NSView {
    init(contentView: NSView) {
        super.init(frame: NSRect(x: 0, y: 0, width: 240, height: overlayHeight))
        wantsLayer = true
        layer?.backgroundColor = NSColor.clear.cgColor

        contentView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(contentView)
        NSLayoutConstraint.activate([
            contentView.leadingAnchor.constraint(equalTo: leadingAnchor),
            contentView.trailingAnchor.constraint(equalTo: trailingAnchor),
            contentView.topAnchor.constraint(equalTo: topAnchor),
            contentView.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}

@available(macOS 26.0, *)
struct OverlayRootView: View {
    @Bindable var model: OverlayViewModel
    let animateInPreview: Bool
    let previewTime: TimeInterval?
    private let capsuleShape = Capsule()

    init(model: OverlayViewModel, animateInPreview: Bool = false, previewTime: TimeInterval? = nil) {
        _model = Bindable(model)
        self.animateInPreview = animateInPreview
        self.previewTime = previewTime
    }

    var body: some View {
        GlassEffectContainer(spacing: 0) {
            HStack(spacing: overlayWaveformSpacing) {
                WaveformView(
                    rms: model.state.rmsLevel,
                    animateInPreview: animateInPreview,
                    previewTime: previewTime
                )
                    .frame(width: overlayWaveformWidth, height: 32)

                SlidingPreviewText(text: displayText)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
            }
            .padding(.horizontal, overlayHorizontalPadding)
            .frame(height: overlayHeight)
            .overlay {
                OverlayGlassChrome(shape: capsuleShape)
                    .allowsHitTesting(false)
            }
            .overlay {
                FlowingHighlightView(
                    animateInPreview: animateInPreview,
                    previewTime: previewTime
                )
                    .clipShape(capsuleShape)
                    .blendMode(.screen)
                    .allowsHitTesting(false)
            }
            .shadow(color: .black.opacity(0.08), radius: 12, y: 7)
            .glassEffect(.clear.tint(.white.opacity(0.003)), in: capsuleShape)
        }
    }

    fileprivate var displayText: String {
        Self.displayText(for: model.state)
    }

    static func displayText(for state: OverlayState) -> String {
        switch state.phase {
        case .idle:
            return ""
        case .recording:
            return state.text.isEmpty ? "Listening…" : state.text
        case .transcribing:
            return state.text.isEmpty ? "Transcribing…" : state.text
        case .refining:
            return "Refining..."
        case .injecting:
            return state.text.isEmpty ? "Injecting…" : state.text
        }
    }
}

@available(macOS 26.0, *)
private struct SlidingPreviewText: View {
    let text: String

    @State private var contentWidth: CGFloat = 0
    @State private var viewportWidth: CGFloat = 0
    @State private var offset: CGFloat = 0
    @State private var displayLinkStart = Date()

    var body: some View {
        GeometryReader { proxy in
            let width = max(0, proxy.size.width)

            HStack(spacing: 0) {
                Text(text)
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(.white.opacity(0.98))
                    .lineLimit(1)
                    .fixedSize(horizontal: true, vertical: false)
                    .offset(x: offset)
                    .shadow(color: .black.opacity(0.22), radius: 2, y: 1)
                    .background(
                        WidthReader(width: $contentWidth)
                    )
                Spacer(minLength: 0)
            }
            .frame(width: width, height: proxy.size.height, alignment: .leading)
            .clipped()
            .onAppear {
                viewportWidth = width
                syncOffset(animated: false)
            }
            .onChange(of: width) { _, newValue in
                viewportWidth = newValue
                syncOffset(animated: false)
            }
        }
        .frame(maxHeight: .infinity, alignment: .center)
        .onAppear {
            displayLinkStart = .now
            syncOffset(animated: false)
        }
        .onChange(of: text) { _, _ in
            syncOffset(animated: true)
        }
        .onChange(of: contentWidth) { _, _ in
            syncOffset(animated: true)
        }
        .onChange(of: viewportWidth) { _, _ in
            syncOffset(animated: false)
        }
    }

    private func syncOffset(animated: Bool) {
        let overflow = max(0, contentWidth - viewportWidth)
        let targetOffset: CGFloat = overflow > 1 ? -overflow : 0

        guard abs(offset - targetOffset) > 0.5 else {
            offset = targetOffset
            return
        }

        guard animated else {
            offset = targetOffset
            return
        }

        let delta = abs(targetOffset - offset)
        let duration = min(0.36, max(0.18, Double(delta / 140)))
        withAnimation(.interactiveSpring(response: duration, dampingFraction: 0.9, blendDuration: 0.18)) {
            offset = targetOffset
        }
    }
}

@available(macOS 26.0, *)
private struct WidthReader: View {
    @Binding var width: CGFloat

    var body: some View {
        GeometryReader { proxy in
            Color.clear
                .onAppear {
                    width = proxy.size.width
                }
                .onChange(of: proxy.size.width) { _, newValue in
                    width = newValue
                }
        }
    }
}

@available(macOS 26.0, *)
private struct OverlayGlassChrome<S: InsettableShape>: View {
    let shape: S

    var body: some View {
        shape
            .inset(by: 1)
            .strokeBorder(
                LinearGradient(
                    colors: [
                        .white.opacity(0.3),
                        .white.opacity(0.08),
                        .white.opacity(0.015),
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                ),
                lineWidth: 1
            )
    }
}

@available(macOS 26.0, *)
private struct FlowingHighlightView: View {
    let animateInPreview: Bool
    let previewTime: TimeInterval?

    var body: some View {
        if let previewTime {
            shimmer(cycle: previewTime.truncatingRemainder(dividingBy: 4.8) / 4.8)
        } else if isRunningInXcodePreview() && !animateInPreview {
            shimmer(cycle: 0.36)
        } else {
            TimelineView(.animation) { timeline in
                let time = timeline.date.timeIntervalSinceReferenceDate
                let cycle = time.truncatingRemainder(dividingBy: 4.8) / 4.8
                shimmer(cycle: cycle)
            }
        }
    }

    private func shimmer(cycle: Double) -> some View {
        let travel = CGFloat(cycle) * 1.85 - 0.45

        return GeometryReader { proxy in
            let shimmerWidth = max(72, proxy.size.width * 0.22)

            LinearGradient(
                colors: [
                    .white.opacity(0.0),
                    .white.opacity(0.03),
                    .white.opacity(0.12),
                    .white.opacity(0.04),
                    .white.opacity(0.0),
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .frame(width: shimmerWidth, height: proxy.size.height * 1.25)
            .rotationEffect(.degrees(12))
            .blur(radius: 10)
            .offset(
                x: (proxy.size.width * travel) - (shimmerWidth / 2),
                y: -proxy.size.height * 0.06
            )
            .opacity(0.8)
        }
    }
}

private struct WaveformView: View {
    let rms: Float
    let animateInPreview: Bool
    let previewTime: TimeInterval?
    private let weights: [CGFloat] = [0.58, 0.88, 1.0, 0.84, 0.62]
    private let seeds: [Double] = [0.03, 0.16, 0.29, 0.44, 0.58]

    var body: some View {
        if let previewTime {
            bars(time: previewTime)
        } else if isRunningInXcodePreview() && !animateInPreview {
            bars(time: 0.42)
        } else {
            TimelineView(.animation) { timeline in
                bars(time: timeline.date.timeIntervalSinceReferenceDate)
            }
        }
    }

    private func bars(time: TimeInterval) -> some View {
        HStack(spacing: 3) {
            ForEach(Array(weights.enumerated()), id: \.offset) { index, weight in
                RoundedRectangle(cornerRadius: 2)
                    .fill(.white.opacity(0.98))
                    .frame(width: 3, height: barHeight(index: index, weight: weight, time: time))
                    .shadow(color: .black.opacity(0.16), radius: 1, y: 1)
                }
        }
        .frame(maxHeight: .infinity, alignment: .center)
    }

    private func barHeight(index: Int, weight: CGFloat, time: TimeInterval) -> CGFloat {
        let primary = (sin(time * 4.8 + seeds[index] * 10) + 1) * 0.5
        let secondary = (sin(time * 7.9 + seeds[index] * 17) + 1) * 0.5
        let envelope = (primary * 0.72) + (secondary * 0.28)
        let minHeight: CGFloat = 9
        let maxHeight: CGFloat = 24
        let normalizedRMS = min(max(CGFloat(rms), 0), 1)
        let activity = max(0.18, normalizedRMS)
        let range = (maxHeight - minHeight) * weight * activity
        return minHeight + (range * envelope)
    }
}

@available(macOS 26.0, *)
private struct OverlayPreviewScene: View {
    @State private var model: OverlayViewModel

    init(state: OverlayState) {
        let model = OverlayViewModel()
        model.state = state
        _model = State(initialValue: model)
    }

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color(nsColor: .init(red: 0.17, green: 0.25, blue: 0.37, alpha: 1)),
                    Color(nsColor: .init(red: 0.12, green: 0.17, blue: 0.24, alpha: 1)),
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            Circle()
                .fill(Color.white.opacity(0.12))
                .blur(radius: 40)
                .frame(width: 220, height: 220)
                .offset(x: -110, y: -70)

            Circle()
                .fill(Color.cyan.opacity(0.16))
                .blur(radius: 50)
                .frame(width: 180, height: 180)
                .offset(x: 130, y: 60)

            OverlayRootView(model: model)
                .frame(
                    width: overlayWidth(for: OverlayRootView.displayText(for: model.state)),
                    height: overlayHeight
                )
        }
        .frame(width: 460, height: 220)
    }
}

@available(macOS 26.0, *)
#Preview("Overlay Listening") {
    OverlayPreviewScene(
        state: OverlayState(
            text: "Listening…",
            rmsLevel: 0.62,
            phase: .recording
        )
    )
}

@available(macOS 26.0, *)
#Preview("Overlay Long Text") {
    OverlayPreviewScene(
        state: OverlayState(
            text: "Transcribing the selected text into a more natural sentence…",
            rmsLevel: 0.28,
            phase: .transcribing
        )
    )
}
