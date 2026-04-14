import AppKit
import Carbon.HIToolbox
import IOKit.hidsystem
import QuartzCore

enum TriggerKeyGestureAction: Equatable {
    case startDictation
    case finishDictation
    case startQuickTranslation
}

enum TriggerKeySessionMode: Equatable {
    case idle
    case dictating
    case translating
    case suspended
}

struct TriggerKeyGestureStateMachine {
    static let defaultLongPressThreshold: TimeInterval = 0.8

    enum State: Equatable {
        case idle
        case pressing(startedAt: TimeInterval, sessionModeAtPress: TriggerKeySessionMode)
        case ignoringUntilRelease
    }

    let longPressThreshold: TimeInterval

    private(set) var state: State = .idle

    init(longPressThreshold: TimeInterval = Self.defaultLongPressThreshold) {
        self.longPressThreshold = longPressThreshold
    }

    var pendingGestureResolutionFireAt: TimeInterval? {
        guard case let .pressing(startedAt, _) = state else { return nil }
        return startedAt + longPressThreshold
    }

    var hasPendingGesture: Bool {
        if case .pressing = state {
            return true
        }
        return false
    }

    mutating func handleKeyDown(sessionMode: TriggerKeySessionMode, at time: TimeInterval) -> [TriggerKeyGestureAction] {
        switch state {
        case .idle:
            switch sessionMode {
            case .idle, .dictating:
                state = .pressing(startedAt: time, sessionModeAtPress: sessionMode)
            case .translating, .suspended:
                state = .ignoringUntilRelease
            }
            return []
        case .pressing, .ignoringUntilRelease:
            return []
        }
    }

    mutating func handleKeyUp() -> [TriggerKeyGestureAction] {
        switch state {
        case .idle:
            return []
        case let .pressing(_, sessionModeAtPress):
            state = .idle
            switch sessionModeAtPress {
            case .idle:
                return [.startDictation]
            case .dictating:
                return [.finishDictation]
            case .translating, .suspended:
                return []
            }
        case .ignoringUntilRelease:
            state = .idle
            return []
        }
    }

    mutating func handleLongPressTimer(at time: TimeInterval) -> [TriggerKeyGestureAction] {
        guard case let .pressing(startedAt, sessionModeAtPress) = state,
              time - startedAt >= longPressThreshold
        else {
            return []
        }

        state = .ignoringUntilRelease
        switch sessionModeAtPress {
        case .idle:
            return [.startQuickTranslation]
        case .dictating, .translating, .suspended:
            return []
        }
    }

    mutating func cancelPendingGesture() {
        guard state != .idle else { return }
        state = .idle
    }

    mutating func reset() {
        state = .idle
    }
}

struct TriggerKeyMonitorCore {
    private(set) var stateMachine = TriggerKeyGestureStateMachine()
    private(set) var sessionMode: TriggerKeySessionMode = .idle
    private(set) var isTriggerPressed = false
    private(set) var suppressCurrentTriggerRelease = false

    init(longPressThreshold: TimeInterval = TriggerKeyGestureStateMachine.defaultLongPressThreshold) {
        stateMachine = TriggerKeyGestureStateMachine(longPressThreshold: longPressThreshold)
    }

    mutating func setSessionMode(_ mode: TriggerKeySessionMode) {
        sessionMode = mode
    }

    mutating func handleTriggerPressChange(_ pressed: Bool, at time: TimeInterval) -> [TriggerKeyGestureAction] {
        guard pressed != isTriggerPressed else { return [] }

        isTriggerPressed = pressed
        if pressed {
            suppressCurrentTriggerRelease = false
            return stateMachine.handleKeyDown(sessionMode: sessionMode, at: time)
        }

        guard !suppressCurrentTriggerRelease else {
            suppressCurrentTriggerRelease = false
            return []
        }

        return stateMachine.handleKeyUp()
    }

    mutating func handleNonTriggerKeyDown() {
        cancelGestureDueToChord()
    }

    mutating func handleNonTriggerModifierChange() {
        cancelGestureDueToChord()
    }

    mutating func handleLongPressTimer(at time: TimeInterval) -> [TriggerKeyGestureAction] {
        stateMachine.handleLongPressTimer(at: time)
    }

    mutating func reset() {
        stateMachine.reset()
        sessionMode = .idle
        isTriggerPressed = false
        suppressCurrentTriggerRelease = false
    }

    private mutating func cancelGestureDueToChord() {
        guard isTriggerPressed || stateMachine.hasPendingGesture else { return }

        if isTriggerPressed {
            suppressCurrentTriggerRelease = true
        }
        stateMachine.cancelPendingGesture()
    }
}

final class TriggerKeyMonitor: @unchecked Sendable {
    private static let systemDefinedRawValue: UInt32 = 14

    var onDictationStart: (@Sendable () -> Void)?
    var onDictationFinish: (@Sendable () -> Void)?
    var onQuickTranslation: (@Sendable () -> Void)?

    private let stateQueue = DispatchQueue(label: "Voily.TriggerKeyMonitor.State")
    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var tapThread: Thread?
    private var tapRunLoop: CFRunLoop?
    private var tapRequested = false
    private var triggerKey: TriggerKey = .fn
    private var core = TriggerKeyMonitorCore()
    private var gestureResolutionWorkItem: DispatchWorkItem?

    var isRunning: Bool {
        stateQueue.sync { tapRequested }
    }

    func setTriggerKey(_ key: TriggerKey) {
        stateQueue.sync {
            triggerKey = key
            cancelTimers()
            core.reset()
        }
    }

    func setSessionMode(_ mode: TriggerKeySessionMode) {
        stateQueue.sync {
            core.setSessionMode(mode)
            syncTimers()
        }
    }

    func start() {
        guard tapThread == nil else { return }
        debugLog("TriggerKeyMonitor.start() triggerKey=\(triggerKey.rawValue)")
        stateQueue.sync {
            tapRequested = true
        }
        let thread = Thread { [weak self] in
            guard let self else { return }

            self.tapRunLoop = CFRunLoopGetCurrent()
            self.setupEventTap()

            let shouldKeepRunning = self.stateQueue.sync { self.tapRequested }
            guard shouldKeepRunning else {
                self.invalidateEventTap()
                self.tapRunLoop = nil
                self.tapThread = nil
                return
            }

            guard self.eventTap != nil else {
                self.tapRunLoop = nil
                self.tapThread = nil
                return
            }

            CFRunLoopRun()
        }
        thread.name = "Voily.TriggerKeyMonitor"
        thread.qualityOfService = .userInteractive
        tapThread = thread
        thread.start()
    }

    func stop() {
        debugLog("TriggerKeyMonitor.stop()")
        stateQueue.sync {
            cancelTimers()
            core.reset()
            tapRequested = false
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

        let mask =
            (1 << CGEventType.flagsChanged.rawValue) |
            (1 << CGEventType.keyDown.rawValue) |
            (1 << Self.systemDefinedRawValue)

        let callback: CGEventTapCallBack = { proxy, type, event, refcon in
            guard let refcon else {
                return Unmanaged.passUnretained(event)
            }

            let monitor = Unmanaged<TriggerKeyMonitor>.fromOpaque(refcon).takeUnretainedValue()
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
        debugLog("TriggerKeyMonitor event tap enabled")
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
            debugLog("TriggerKeyMonitor tap disabled by system, reenabling")
            if let eventTap {
                CGEvent.tapEnable(tap: eventTap, enable: true)
            }
            return Unmanaged.passUnretained(event)
        }

        switch type {
        case .flagsChanged:
            return handleFlagsChanged(event)
        case .keyDown:
            return handleKeyDown(event)
        default:
            if type.rawValue == Self.systemDefinedRawValue {
                return handleSystemDefined(event)
            }
            return Unmanaged.passUnretained(event)
        }
    }

    private func handleFlagsChanged(_ event: CGEvent) -> Unmanaged<CGEvent>? {
        let keyCode = Int(event.getIntegerValueField(.keyboardEventKeycode))

        if keyCode == monitoredKeyCode {
            let pressed = isTriggerPressed(event: event, keyCode: keyCode)
            let actions = stateQueue.sync { () -> [TriggerKeyGestureAction] in
                let actions = core.handleTriggerPressChange(pressed, at: CACurrentMediaTime())
                syncTimers()
                return actions
            }
            dispatch(actions)

            if triggerKey == .fn {
                return nil
            }
            return Unmanaged.passUnretained(event)
        }

        if isModifierKey(keyCode) {
            stateQueue.sync {
                core.handleNonTriggerModifierChange()
                syncTimers()
            }
        }

        return Unmanaged.passUnretained(event)
    }

    private func handleKeyDown(_ event: CGEvent) -> Unmanaged<CGEvent>? {
        let keyCode = Int(event.getIntegerValueField(.keyboardEventKeycode))
        guard keyCode != monitoredKeyCode else {
            return Unmanaged.passUnretained(event)
        }

        stateQueue.sync {
            core.handleNonTriggerKeyDown()
            syncTimers()
        }
        return Unmanaged.passUnretained(event)
    }

    private func handleSystemDefined(_ event: CGEvent) -> Unmanaged<CGEvent>? {
        guard triggerKey == .fn else {
            return Unmanaged.passUnretained(event)
        }
        guard let nsEvent = NSEvent(cgEvent: event) else {
            return Unmanaged.passUnretained(event)
        }

        let data1 = nsEvent.data1
        let keyCode = Int((data1 & 0xFFFF0000) >> 16)
        let state = (data1 & 0xFF00) >> 8
        guard keyCode == Int(kVK_Function) else {
            return Unmanaged.passUnretained(event)
        }

        let actions = stateQueue.sync { () -> [TriggerKeyGestureAction] in
            let actions: [TriggerKeyGestureAction]
            switch state {
            case 0x0A:
                actions = core.handleTriggerPressChange(true, at: CACurrentMediaTime())
            case 0x0B:
                actions = core.handleTriggerPressChange(false, at: CACurrentMediaTime())
            default:
                return []
            }
            syncTimers()
            return actions
        }
        dispatch(actions)
        return nil
    }

    private var monitoredKeyCode: Int {
        switch triggerKey {
        case .fn:
            return Int(kVK_Function)
        case .rightCommand:
            return Int(kVK_RightCommand)
        }
    }

    private func isTriggerPressed(event: CGEvent, keyCode: Int) -> Bool {
        switch triggerKey {
        case .fn:
            return event.flags.contains(.maskSecondaryFn)
        case .rightCommand:
            if keyCode != Int(kVK_RightCommand) {
                return false
            }
            return (event.flags.rawValue & UInt64(NX_DEVICERCMDKEYMASK)) != 0
        }
    }

    private func isModifierKey(_ keyCode: Int) -> Bool {
        switch keyCode {
        case Int(kVK_Function),
             Int(kVK_Command),
             Int(kVK_RightCommand),
             Int(kVK_Shift),
             Int(kVK_RightShift),
             Int(kVK_Option),
             Int(kVK_RightOption),
             Int(kVK_Control),
             Int(kVK_RightControl),
             Int(kVK_CapsLock):
            return true
        default:
            return false
        }
    }

    private func syncTimers() {
        gestureResolutionWorkItem?.cancel()
        gestureResolutionWorkItem = nil

        if let fireAt = core.stateMachine.pendingGestureResolutionFireAt {
            let workItem = DispatchWorkItem { [weak self] in
                guard let self else { return }
                let actions = self.core.handleLongPressTimer(at: CACurrentMediaTime())
                self.syncTimers()
                self.dispatch(actions)
            }
            gestureResolutionWorkItem = workItem
            stateQueue.asyncAfter(deadline: .now() + max(0, fireAt - CACurrentMediaTime()), execute: workItem)
        }
    }

    private func cancelTimers() {
        gestureResolutionWorkItem?.cancel()
        gestureResolutionWorkItem = nil
    }

    private func dispatch(_ actions: [TriggerKeyGestureAction]) {
        for action in actions {
            let callback: (@Sendable () -> Void)?
            switch action {
            case .startDictation:
                debugLog("TriggerKeyMonitor start dictation")
                callback = onDictationStart
            case .finishDictation:
                debugLog("TriggerKeyMonitor finish dictation")
                callback = onDictationFinish
            case .startQuickTranslation:
                debugLog("TriggerKeyMonitor start quick translation")
                callback = onQuickTranslation
            }

            DispatchQueue.main.async {
                callback?()
            }
        }
    }
}
