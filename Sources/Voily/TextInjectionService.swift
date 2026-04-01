import AppKit

enum TextInjectionResult: Equatable {
    case success
    case accessibilityDenied
    case pasteFailed
    case pasteboardRestoreFailed
}

@MainActor
final class TextInjectionService {
    func inject(text: String) async -> TextInjectionResult {
        guard AXIsProcessTrusted() else {
            return .accessibilityDenied
        }

        let pasteboard = NSPasteboard.general
        let snapshot = PasteboardSnapshot(pasteboard: pasteboard)

        pasteboard.clearContents()
        guard pasteboard.setString(text, forType: .string) else {
            return .pasteFailed
        }

        let pasteResult = postPasteShortcut()
        try? await Task.sleep(for: .milliseconds(80))

        guard snapshot.restore(to: pasteboard) else {
            return .pasteboardRestoreFailed
        }

        return pasteResult ? .success : .pasteFailed
    }

    private func postPasteShortcut() -> Bool {
        guard
            let keyDown = CGEvent(keyboardEventSource: nil, virtualKey: 9, keyDown: true),
            let keyUp = CGEvent(keyboardEventSource: nil, virtualKey: 9, keyDown: false)
        else {
            return false
        }

        keyDown.flags = .maskCommand
        keyUp.flags = .maskCommand
        keyDown.post(tap: .cghidEventTap)
        keyUp.post(tap: .cghidEventTap)
        return true
    }
}

private struct PasteboardSnapshot {
    private let items: [[NSPasteboard.PasteboardType: Data]]

    init(pasteboard: NSPasteboard) {
        self.items = pasteboard.pasteboardItems?.map { item in
            var restored: [NSPasteboard.PasteboardType: Data] = [:]
            for type in item.types {
                if let data = item.data(forType: type) {
                    restored[type] = data
                }
            }
            return restored
        } ?? []
    }

    func restore(to pasteboard: NSPasteboard) -> Bool {
        pasteboard.clearContents()

        if items.isEmpty {
            return true
        }

        let newItems = items.map { item -> NSPasteboardItem in
            let pasteboardItem = NSPasteboardItem()
            for (type, data) in item {
                pasteboardItem.setData(data, forType: type)
            }
            return pasteboardItem
        }

        return pasteboard.writeObjects(newItems)
    }
}
