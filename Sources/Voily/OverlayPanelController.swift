import AppKit
import SwiftUI
import Observation

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
        panel.contentView = VisualEffectContainerView(contentView: hostView)
        panel.orderOut(nil)
    }

    func show(state: OverlayState) {
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
        let width = measuredWidth(for: state.text)
        let visibleFrame = NSScreen.main?.visibleFrame ?? .zero
        let originX = visibleFrame.midX - (width / 2)
        let originY = visibleFrame.minY + 48
        return NSRect(x: originX, y: originY, width: width, height: 56)
    }

    private func positionPanel() {
        let frame = frame(for: model.state)
        panel.setFrameOrigin(frame.origin)
    }

    private func measuredWidth(for text: String) -> CGFloat {
        let shownText = text.isEmpty ? "Listening…" : text
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 16, weight: .medium),
        ]

        let textWidth = (shownText as NSString).size(withAttributes: attributes).width
        return min(max(textWidth + 120, 160), 560)
    }
}

@MainActor
@Observable
final class OverlayViewModel {
    var state: OverlayState = .idle
}

private final class VisualEffectContainerView: NSVisualEffectView {
    init(contentView: NSView) {
        super.init(frame: NSRect(x: 0, y: 0, width: 240, height: 56))
        material = .hudWindow
        blendingMode = .withinWindow
        state = .active
        wantsLayer = true
        layer?.cornerRadius = 28
        layer?.cornerCurve = .continuous

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

private struct OverlayRootView: View {
    @Bindable var model: OverlayViewModel

    var body: some View {
        HStack(spacing: 14) {
            WaveformView(rms: model.state.rmsLevel)
                .frame(width: 44, height: 32)

            Text(displayText)
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(.white.opacity(0.96))
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)
                .animation(.easeInOut(duration: 0.25), value: displayText)
        }
        .padding(.horizontal, 18)
        .frame(height: 56)
    }

    private var displayText: String {
        switch model.state.phase {
        case .idle:
            return ""
        case .recording:
            return model.state.text.isEmpty ? "Listening…" : model.state.text
        case .transcribing:
            return model.state.text.isEmpty ? "Transcribing…" : model.state.text
        case .refining:
            return "Refining..."
        case .injecting:
            return model.state.text.isEmpty ? "Injecting…" : model.state.text
        }
    }
}

private struct WaveformView: View {
    let rms: Float
    private let weights: [CGFloat] = [0.5, 0.8, 1.0, 0.75, 0.55]
    private let seeds: [Double] = [0.0, 0.17, 0.31, 0.47, 0.61]

    var body: some View {
        TimelineView(.animation) { timeline in
            let time = timeline.date.timeIntervalSinceReferenceDate

            HStack(spacing: 4) {
                ForEach(Array(weights.enumerated()), id: \.offset) { index, weight in
                    RoundedRectangle(cornerRadius: 2)
                        .fill(.white.opacity(0.95))
                        .frame(width: 5, height: barHeight(index: index, weight: weight, time: time))
                }
            }
            .frame(maxHeight: .infinity, alignment: .center)
        }
    }

    private func barHeight(index: Int, weight: CGFloat, time: TimeInterval) -> CGFloat {
        let base = max(6, CGFloat(rms) * 30 * weight + 6)
        let jitter = 1 + (sin(time * 11 + seeds[index] * 8) * 0.04)
        return min(32, max(6, base * jitter))
    }
}
