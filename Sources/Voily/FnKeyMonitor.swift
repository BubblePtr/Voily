import AppKit
import Carbon.HIToolbox

final class FnKeyMonitor {
    private static let systemDefinedRawValue: UInt32 = 14

    var onPress: (() -> Void)?
    var onRelease: (() -> Void)?

    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var isFnPressed = false

    func start() {
        guard eventTap == nil else { return }
        debugLog("FnKeyMonitor.start()")

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

        if let runLoopSource {
            CFRunLoopAddSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
        }

        CGEvent.tapEnable(tap: tap, enable: true)
        debugLog("FnKeyMonitor event tap enabled")
    }

    func stop() {
        debugLog("FnKeyMonitor.stop()")
        if let runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
        }

        if let eventTap {
            CFMachPortInvalidate(eventTap)
        }

        runLoopSource = nil
        eventTap = nil
        isFnPressed = false
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
        debugLog("FnKeyMonitor flagsChanged fn pressed=\(pressed)")
        if pressed != isFnPressed {
            isFnPressed = pressed

            if pressed {
                debugLog("FnKeyMonitor onPress from flagsChanged")
                onPress?()
            } else {
                debugLog("FnKeyMonitor onRelease from flagsChanged")
                onRelease?()
            }
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

        debugLog("FnKeyMonitor systemDefined fn state=0x\(String(state, radix: 16))")

        switch state {
        case 0x0A:
            if !isFnPressed {
                isFnPressed = true
                debugLog("FnKeyMonitor onPress from systemDefined")
                onPress?()
            }
            return nil
        case 0x0B:
            if isFnPressed {
                isFnPressed = false
                debugLog("FnKeyMonitor onRelease from systemDefined")
                onRelease?()
            }
            return nil
        default:
            return Unmanaged.passUnretained(event)
        }
    }
}
