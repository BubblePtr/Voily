import AppKit
import SwiftUI
import Observation

let overlayHeight: CGFloat = 52
private let overlayMinimumWidth: CGFloat = 160
private let overlayMaximumWidth: CGFloat = 540
private let overlayHorizontalPadding: CGFloat = 18
private let overlayWaveformWidth: CGFloat = 46
private let overlayWaveformSpacing: CGFloat = 12
private let overlayActionButtonsWidth: CGFloat = 88

@MainActor
func overlayWidth(for state: OverlayState) -> CGFloat {
    let attributes: [NSAttributedString.Key: Any] = [
        .font: NSFont.systemFont(ofSize: 16, weight: .medium),
    ]

    let text = OverlayRootView.displayText(for: state)
    let textWidth = (text as NSString).size(withAttributes: attributes).width
    let controlsWidth = state.controls == .confirmCancel ? overlayActionButtonsWidth : 0
    let chromeWidth = (overlayHorizontalPadding * 2) + overlayWaveformWidth + overlayWaveformSpacing + 26 + controlsWidth
    return min(max(textWidth + chromeWidth, overlayMinimumWidth), overlayMaximumWidth)
}

@available(macOS 26.0, *)
@MainActor
final class OverlayPanelController {
    private let model = OverlayViewModel()
    private let panel: NSPanel
    private let hostView: NSHostingView<OverlayRootView>
    private var hideTask: Task<Void, Never>?

    var onConfirm: (() -> Void)? {
        didSet { model.onConfirm = onConfirm }
    }

    var onCancel: (() -> Void)? {
        didSet { model.onCancel = onCancel }
    }

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
        let targetFrame = frame(for: state)
        let needsFrameUpdate = !panel.frame.equalTo(targetFrame)
        model.state = state
        panel.ignoresMouseEvents = state.controls == .none

        if !panel.isVisible {
            panel.alphaValue = 0
            panel.setFrame(targetFrame, display: true)
            panel.orderFrontRegardless()

            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.18
                context.timingFunction = CAMediaTimingFunction(name: .easeOut)
                panel.animator().alphaValue = 1
            }
            return
        }

        guard needsFrameUpdate else { return }

        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.14
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            panel.animator().setFrame(targetFrame, display: true)
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
                    self.panel.ignoresMouseEvents = true
                }
            }
        }
    }

    private func frame(for state: OverlayState) -> NSRect {
        let width = overlayWidth(for: state)
        let visibleFrame = NSScreen.main?.visibleFrame ?? .zero
        let originX = visibleFrame.midX - (width / 2)
        let originY = visibleFrame.minY + 28
        return NSRect(x: originX, y: originY, width: width, height: overlayHeight)
    }
}

@MainActor
@Observable
final class OverlayViewModel {
    var state: OverlayState = .idle
    var onConfirm: (() -> Void)?
    var onCancel: (() -> Void)?

    func confirm() {
        onConfirm?()
    }

    func cancel() {
        onCancel?()
    }
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

                SlidingPreviewText(text: displayText, isPartial: model.state.phase == .recordingPartial)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)

                if model.state.controls == .confirmCancel {
                    OverlayActionButtons(
                        onConfirm: model.confirm,
                        onCancel: model.cancel
                    )
                }
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
            if state.text.isEmpty {
                return state.controls == .confirmCancel ? "Speak in Chinese…" : "Listening…"
            }
            return state.text
        case .recordingPartial:
            if state.text.isEmpty {
                return state.controls == .confirmCancel ? "Speak in Chinese…" : "Listening…"
            }
            return state.text
        case .transcribing:
            return state.text.isEmpty ? "Transcribing…" : state.text
        case .refining:
            return "Refining..."
        case .translating:
            return state.text.isEmpty ? "Translating..." : state.text
        case .injecting:
            return state.text.isEmpty ? "Injecting…" : state.text
        }
    }
}

@available(macOS 26.0, *)
private struct OverlayActionButtons: View {
    let onConfirm: () -> Void
    let onCancel: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            actionButton(systemName: "xmark", action: onCancel)
                .accessibilityLabel("Discard translation")

            actionButton(systemName: "checkmark", action: onConfirm)
                .accessibilityLabel("Finish recording")
        }
    }

    private func actionButton(systemName: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.white.opacity(0.95))
                .frame(width: 28, height: 28)
                .background(
                    Circle()
                        .fill(.white.opacity(0.12))
                )
                .overlay(
                    Circle()
                        .stroke(.white.opacity(0.14), lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
    }
}

@available(macOS 26.0, *)
private struct SlidingPreviewText: View {
    let text: String
    let isPartial: Bool
    private let fadeWidth: CGFloat = 16

    @State private var contentWidth: CGFloat = 0
    @State private var viewportWidth: CGFloat = 0
    @State private var offset: CGFloat = 0

    var body: some View {
        GeometryReader { proxy in
            let width = max(0, proxy.size.width)
            let overflow = max(0, contentWidth - width)

            HStack(spacing: 0) {
                Text(text)
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(.white.opacity(isPartial ? 0.82 : 0.98))
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
            .mask(
                SlidingPreviewFadeMask(
                    width: width,
                    fadeWidth: min(fadeWidth, width * 0.18),
                    showsLeadingFade: overflow > 1 && offset < -0.5,
                    showsTrailingFade: overflow > 1 && offset > -(overflow - 0.5)
                )
            )
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
        .onChange(of: text) { _, _ in
            syncOffset(animated: true)
        }
        .onChange(of: contentWidth) { _, _ in
            syncOffset(animated: true)
        }
        .onChange(of: viewportWidth) { _, _ in
            syncOffset(animated: true)
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
        let duration = min(0.16, max(0.06, Double(delta / 420)))
        withAnimation(.linear(duration: duration)) {
            offset = targetOffset
        }
    }
}

@available(macOS 26.0, *)
private struct SlidingPreviewFadeMask: View {
    let width: CGFloat
    let fadeWidth: CGFloat
    let showsLeadingFade: Bool
    let showsTrailingFade: Bool

    var body: some View {
        let edgeWidth = max(0, min(fadeWidth, width / 2))

        HStack(spacing: 0) {
            LinearGradient(
                colors: [
                    .white.opacity(showsLeadingFade ? 0 : 1),
                    .white,
                ],
                startPoint: .leading,
                endPoint: .trailing
            )
            .frame(width: edgeWidth)

            Rectangle()
                .fill(.white)
                .frame(width: max(0, width - (edgeWidth * 2)))

            LinearGradient(
                colors: [
                    .white,
                    .white.opacity(showsTrailingFade ? 0 : 1),
                ],
                startPoint: .leading,
                endPoint: .trailing
            )
            .frame(width: edgeWidth)
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
    private let positions: [Double] = [-2, -1, 0, 1, 2]
    private let spatialPhaseStep: Double = .pi / 3.2
    private let loopDuration: TimeInterval = 0.84

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
        HStack(spacing: 2.5) {
            ForEach(Array(weights.enumerated()), id: \.offset) { index, weight in
                RoundedRectangle(cornerRadius: 1.5)
                    .fill(.white.opacity(0.98))
                    .frame(width: 2.2, height: barHeight(index: index, weight: weight, time: time))
                    .shadow(color: .black.opacity(0.16), radius: 1, y: 1)
            }
        }
        .frame(maxHeight: .infinity, alignment: .center)
    }

    private func barHeight(index: Int, weight: CGFloat, time: TimeInterval) -> CGFloat {
        let cycle = time.truncatingRemainder(dividingBy: loopDuration) / loopDuration
        let phase = cycle * .pi * 2
        let localPhase = phase - (positions[index] * spatialPhaseStep)
        let primary = (sin(localPhase) + 1) * 0.5
        let secondary = (sin((localPhase * 2) - .pi / 6) + 1) * 0.5
        let envelope = (primary * 0.82) + (secondary * 0.18)
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
                    width: overlayWidth(for: model.state),
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
