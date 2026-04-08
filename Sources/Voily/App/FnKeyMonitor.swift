import AppKit
import Carbon.HIToolbox
import QuartzCore

enum FnGestureAction: Equatable {
    case startDictation
    case finishDictation
    case startQuickTranslation
}

struct FnShortcutStateMachine {
    enum State: Equatable {
        case idle
        case firstPressing(startedAt: TimeInterval)
        case waitingForSecondPress(releasedAt: TimeInterval)
        case dictating
    }

    let longPressThreshold: TimeInterval
    let doubleTapWindow: TimeInterval

    private(set) var state: State = .idle

    init(longPressThreshold: TimeInterval = 0.18, doubleTapWindow: TimeInterval = 0.3) {
        self.longPressThreshold = longPressThreshold
        self.doubleTapWindow = doubleTapWindow
    }

    var pendingLongPressFireAt: TimeInterval? {
        guard case let .firstPressing(startedAt) = state else { return nil }
        return startedAt + longPressThreshold
    }

    var pendingDoubleTapExpiryAt: TimeInterval? {
        guard case let .waitingForSecondPress(releasedAt) = state else { return nil }
        return releasedAt + doubleTapWindow
    }

    mutating func handleKeyDown(at time: TimeInterval) -> [FnGestureAction] {
        switch state {
        case .idle:
            state = .firstPressing(startedAt: time)
            return []
        case let .waitingForSecondPress(releasedAt):
            if time - releasedAt <= doubleTapWindow {
                state = .idle
                return [.startQuickTranslation]
            }

            state = .firstPressing(startedAt: time)
            return []
        case .firstPressing, .dictating:
            return []
        }
    }

    mutating func handleKeyUp(at time: TimeInterval) -> [FnGestureAction] {
        switch state {
        case .idle:
            return []
        case let .firstPressing(startedAt):
            if time - startedAt >= longPressThreshold {
                state = .idle
                return [.startDictation, .finishDictation]
            }

            state = .waitingForSecondPress(releasedAt: time)
            return []
        case .waitingForSecondPress:
            return []
        case .dictating:
            state = .idle
            return [.finishDictation]
        }
    }

    mutating func handleLongPressTimer(at time: TimeInterval) -> [FnGestureAction] {
        guard case let .firstPressing(startedAt) = state, time - startedAt >= longPressThreshold else {
            return []
        }

        state = .dictating
        return [.startDictation]
    }

    mutating func handleDoubleTapTimer(at time: TimeInterval) -> [FnGestureAction] {
        guard case let .waitingForSecondPress(releasedAt) = state, time - releasedAt >= doubleTapWindow else {
            return []
        }

        state = .idle
        return []
    }

    mutating func reset() {
        state = .idle
    }
}

final class FnKeyMonitor: @unchecked Sendable {
    private static let systemDefinedRawValue: UInt32 = 14

    var onDictationStart: (@Sendable () -> Void)?
    var onDictationFinish: (@Sendable () -> Void)?
    var onQuickTranslation: (@Sendable () -> Void)?

    private let stateQueue = DispatchQueue(label: "Voily.FnKeyMonitor.State")
    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var tapThread: Thread?
    private var tapRunLoop: CFRunLoop?
    private var isFnPressed = false
    private var stateMachine = FnShortcutStateMachine()
    private var longPressWorkItem: DispatchWorkItem?
    private var doubleTapWorkItem: DispatchWorkItem?

    func start() {
        guard tapThread == nil else { return }
        debugLog("FnKeyMonitor.start()")

        let ready = DispatchSemaphore(value: 0)
        let thread = Thread { [weak self] in
            guard let self else {
                ready.signal()
                return
            }

            self.tapRunLoop = CFRunLoopGetCurrent()
            self.setupEventTap()
            ready.signal()

            guard self.eventTap != nil else {
                self.tapRunLoop = nil
                self.tapThread = nil
                return
            }

            CFRunLoopRun()
        }
        thread.name = "Voily.FnKeyMonitor"
        tapThread = thread
        thread.start()
        ready.wait()
    }

    func stop() {
        debugLog("FnKeyMonitor.stop()")
        stateQueue.sync {
            cancelTimers()
            stateMachine.reset()
            isFnPressed = false
        }

        guard let tapRunLoop else {
            tapThread = nil
            return
        }

        CFRunLoopPerformBlock(tapRunLoop, CFRunLoopMode.commonModes.rawValue) { [weak self] in
            guard let self else { return }
            self.invalidateEventTap()
            self.tapRunLoop = nil
            self.tapThread = nil
            CFRunLoopStop(tapRunLoop)
        }
        CFRunLoopWakeUp(tapRunLoop)
    }

    private func setupEventTap() {
        guard eventTap == nil else { return }

        let mask = (1 << CGEventType.flagsChanged.rawValue) | (1 << Self.systemDefinedRawValue)
        let callback: CGEventTapCallBack = { proxy, type, event, refcon in
            guard let refcon else {
                return Unmanaged.passUnretained(event)
            }

            let monitor = Unmanaged<FnKeyMonitor>.fromOpaque(refcon).takeUnretainedValue()
            return monitor.handle(proxy: proxy, type: type, event: event)
        }

        let refcon = UnsafeMutableRawPointer(Unmanaged.passUnretained(self).toOpaque())
        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: CGEventMask(mask),
            callback: callback,
            userInfo: refcon
        ) else {
            debugLog("Failed to create event tap. Accessibility permission is likely missing.")
            return
        }

        eventTap = tap
        runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)

        if let runLoopSource, let tapRunLoop {
            CFRunLoopAddSource(tapRunLoop, runLoopSource, .commonModes)
        }

        CGEvent.tapEnable(tap: tap, enable: true)
        debugLog("FnKeyMonitor event tap enabled")
    }

    private func invalidateEventTap() {
        if let runLoopSource, let tapRunLoop {
            CFRunLoopRemoveSource(tapRunLoop, runLoopSource, .commonModes)
        }
        if let eventTap {
            CFMachPortInvalidate(eventTap)
        }
        runLoopSource = nil
        eventTap = nil
    }

    private func handle(proxy: CGEventTapProxy, type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            debugLog("FnKeyMonitor tap disabled by system, reenabling")
            if let eventTap {
                CGEvent.tapEnable(tap: eventTap, enable: true)
            }
            return Unmanaged.passUnretained(event)
        }

        switch type {
        case .flagsChanged:
            return handleFlagsChanged(event)
        default:
            if type.rawValue == Self.systemDefinedRawValue {
                return handleSystemDefined(event)
            }
            return Unmanaged.passUnretained(event)
        }
    }

    private func handleFlagsChanged(_ event: CGEvent) -> Unmanaged<CGEvent>? {
        let keyCode = event.getIntegerValueField(.keyboardEventKeycode)
        guard keyCode == kVK_Function else {
            return Unmanaged.passUnretained(event)
        }

        let pressed = event.flags.contains(.maskSecondaryFn)
        stateQueue.sync {
            handlePhysicalPressChange(pressed)
        }
        return nil
    }

    private func handleSystemDefined(_ event: CGEvent) -> Unmanaged<CGEvent>? {
        guard let nsEvent = NSEvent(cgEvent: event) else {
            return Unmanaged.passUnretained(event)
        }

        let data1 = nsEvent.data1
        let keyCode = Int((data1 & 0xFFFF0000) >> 16)
        let state = (data1 & 0xFF00) >> 8
        guard keyCode == Int(kVK_Function) else {
            return Unmanaged.passUnretained(event)
        }

        switch state {
        case 0x0A:
            stateQueue.sync {
                handlePhysicalPressChange(true)
            }
            return nil
        case 0x0B:
            stateQueue.sync {
                handlePhysicalPressChange(false)
            }
            return nil
        default:
            return Unmanaged.passUnretained(event)
        }
    }

    private func handlePhysicalPressChange(_ pressed: Bool) {
        guard pressed != isFnPressed else {
            return
        }

        isFnPressed = pressed
        let now = CACurrentMediaTime()
        let actions = if pressed {
            stateMachine.handleKeyDown(at: now)
        } else {
            stateMachine.handleKeyUp(at: now)
        }

        syncTimers()
        dispatch(actions)
    }

    private func syncTimers() {
        longPressWorkItem?.cancel()
        longPressWorkItem = nil

        if let fireAt = stateMachine.pendingLongPressFireAt {
            let workItem = DispatchWorkItem { [weak self] in
                guard let self else { return }
                let actions = self.stateMachine.handleLongPressTimer(at: CACurrentMediaTime())
                self.syncTimers()
                self.dispatch(actions)
            }
            longPressWorkItem = workItem
            stateQueue.asyncAfter(deadline: .now() + max(0, fireAt - CACurrentMediaTime()), execute: workItem)
        }

        doubleTapWorkItem?.cancel()
        doubleTapWorkItem = nil

        if let fireAt = stateMachine.pendingDoubleTapExpiryAt {
            let workItem = DispatchWorkItem { [weak self] in
                guard let self else { return }
                _ = self.stateMachine.handleDoubleTapTimer(at: CACurrentMediaTime())
                self.syncTimers()
            }
            doubleTapWorkItem = workItem
            stateQueue.asyncAfter(deadline: .now() + max(0, fireAt - CACurrentMediaTime()), execute: workItem)
        }
    }

    private func cancelTimers() {
        longPressWorkItem?.cancel()
        longPressWorkItem = nil
        doubleTapWorkItem?.cancel()
        doubleTapWorkItem = nil
    }

    private func dispatch(_ actions: [FnGestureAction]) {
        for action in actions {
            let callback: (@Sendable () -> Void)?
            switch action {
            case .startDictation:
                debugLog("FnKeyMonitor start dictation")
                callback = onDictationStart
            case .finishDictation:
                debugLog("FnKeyMonitor finish dictation")
                callback = onDictationFinish
            case .startQuickTranslation:
                debugLog("FnKeyMonitor start quick translation")
                callback = onQuickTranslation
            }

            DispatchQueue.main.async {
                callback?()
            }
        }
    }
}
