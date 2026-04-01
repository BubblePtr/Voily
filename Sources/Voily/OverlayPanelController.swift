import AppKit
import SwiftUI
import Observation

private let overlayHeight: CGFloat = 56
private let overlayMinimumWidth: CGFloat = 160
private let overlayMaximumWidth: CGFloat = 560
private let overlayHorizontalPadding: CGFloat = 18
private let overlayWaveformWidth: CGFloat = 32
private let overlayWaveformSpacing: CGFloat = 12

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
            contentRect: NSRect(x: 0, y: 0, width: 240, height: 56),
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
        let width = measuredWidth(for: OverlayRootView.displayText(for: state))
        let visibleFrame = NSScreen.main?.visibleFrame ?? .zero
        let originX = visibleFrame.midX - (width / 2)
        let originY = visibleFrame.minY + 48
        return NSRect(x: originX, y: originY, width: width, height: overlayHeight)
    }

    private func positionPanel() {
        let frame = frame(for: model.state)
        panel.setFrameOrigin(frame.origin)
    }

    private func measuredWidth(for text: String) -> CGFloat {
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 16, weight: .medium),
        ]

        let textWidth = (text as NSString).size(withAttributes: attributes).width
        let chromeWidth = (overlayHorizontalPadding * 2) + overlayWaveformWidth + overlayWaveformSpacing + 26
        return min(max(textWidth + chromeWidth, overlayMinimumWidth), overlayMaximumWidth)
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
private struct OverlayRootView: View {
    @Bindable var model: OverlayViewModel
    private let capsuleShape = Capsule()

    var body: some View {
        GlassEffectContainer(spacing: 0) {
            HStack(spacing: overlayWaveformSpacing) {
                WaveformView(rms: model.state.rmsLevel)
                    .frame(width: overlayWaveformWidth, height: 32)

                SlidingPreviewText(text: displayText)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
            }
            .padding(.horizontal, overlayHorizontalPadding)
            .frame(height: overlayHeight)
            .overlay {
                FlowingHighlightView()
                    .clipShape(capsuleShape)
                    .allowsHitTesting(false)
            }
            .shadow(color: .black.opacity(0.08), radius: 10, y: 4)
            .glassEffect(.clear.tint(.white.opacity(0.06)), in: capsuleShape)
        }
    }

    fileprivate var displayText: String {
        Self.displayText(for: model.state)
    }

    fileprivate static func displayText(for state: OverlayState) -> String {
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
private struct FlowingHighlightView: View {
    var body: some View {
        TimelineView(.animation) { timeline in
            let time = timeline.date.timeIntervalSinceReferenceDate
            let cycle = time.truncatingRemainder(dividingBy: 4.4) / 4.4
            let travel = CGFloat(cycle) * 1.85 - 0.45

            GeometryReader { proxy in
                let shimmerWidth = max(54, proxy.size.width * 0.2)

                LinearGradient(
                    colors: [
                        .white.opacity(0.0),
                        .white.opacity(0.04),
                        .white.opacity(0.14),
                        .white.opacity(0.04),
                        .white.opacity(0.0),
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .frame(width: shimmerWidth, height: proxy.size.height * 1.25)
                .rotationEffect(.degrees(14))
                .blur(radius: 5)
                .offset(
                    x: (proxy.size.width * travel) - (shimmerWidth / 2),
                    y: -proxy.size.height * 0.06
                )
            }
        }
    }
}

private struct WaveformView: View {
    let rms: Float
    private let weights: [CGFloat] = [0.58, 0.88, 1.0, 0.84, 0.62]
    private let seeds: [Double] = [0.03, 0.16, 0.29, 0.44, 0.58]

    var body: some View {
        TimelineView(.animation) { timeline in
            let time = timeline.date.timeIntervalSinceReferenceDate

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
    }

    private func barHeight(index: Int, weight: CGFloat, time: TimeInterval) -> CGFloat {
        let primary = (sin(time * 4.8 + seeds[index] * 10) + 1) * 0.5
        let secondary = (sin(time * 7.9 + seeds[index] * 17) + 1) * 0.5
        let envelope = (primary * 0.72) + (secondary * 0.28)
        let minHeight: CGFloat = 8
        let maxHeight: CGFloat = 22
        let range = (maxHeight - minHeight) * weight
        _ = rms
        return minHeight + (range * envelope)
    }
}
