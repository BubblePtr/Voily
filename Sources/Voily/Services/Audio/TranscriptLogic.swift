import Foundation

struct TranscriptAccumulator {
    private(set) var committedText = ""
    private(set) var liveText = ""

    var displayText: String {
        Self.merge(base: committedText, incoming: liveText)
    }

    var finalText: String {
        displayText.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    mutating func reset() {
        committedText = ""
        liveText = ""
    }

    @discardableResult
    mutating func updatePartial(_ text: String) -> String {
        let normalized = Self.normalize(text)
        guard !normalized.isEmpty else { return displayText }

        if normalized == committedText || committedText.hasSuffix(normalized) {
            liveText = ""
        } else {
            liveText = normalized
        }
        return displayText
    }

    @discardableResult
    mutating func appendDelta(_ text: String) -> String {
        let normalized = Self.normalize(text)
        guard !normalized.isEmpty else { return displayText }

        let existing = Self.normalize(liveText)
        liveText = existing.isEmpty
            ? normalized
            : Self.merge(base: existing, incoming: normalized)
        return displayText
    }

    @discardableResult
    mutating func commit(_ text: String) -> String {
        let normalized = Self.normalize(text)
        if !normalized.isEmpty {
            committedText = Self.merge(base: committedText, incoming: normalized)
        }
        liveText = ""
        return committedText
    }

    private static func normalize(_ text: String) -> String {
        text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func merge(base: String, incoming: String) -> String {
        let lhs = normalize(base)
        let rhs = normalize(incoming)

        guard !lhs.isEmpty else { return rhs }
        guard !rhs.isEmpty else { return lhs }

        if rhs == lhs || lhs.hasSuffix(rhs) || lhs.hasPrefix(rhs) {
            return lhs
        }
        if rhs.hasPrefix(lhs) {
            return rhs
        }

        let overlap = overlapLength(lhs, rhs)
        let suffixStart = rhs.index(rhs.startIndex, offsetBy: overlap)
        let suffix = String(rhs[suffixStart...])
        guard !suffix.isEmpty else { return lhs }
        return lhs + separator(between: lhs, and: suffix) + suffix
    }

    private static func overlapLength(_ lhs: String, _ rhs: String) -> Int {
        let maxLength = min(lhs.count, rhs.count)
        guard maxLength > 0 else { return 0 }

        for length in stride(from: maxLength, through: 1, by: -1) {
            let lhsStart = lhs.index(lhs.endIndex, offsetBy: -length)
            let rhsEnd = rhs.index(rhs.startIndex, offsetBy: length)
            if lhs[lhsStart...] == rhs[..<rhsEnd] {
                return length
            }
        }
        return 0
    }

    private static func separator(between lhs: String, and rhs: String) -> String {
        guard
            let lhsScalar = lhs.unicodeScalars.last,
            let rhsScalar = rhs.unicodeScalars.first
        else {
            return ""
        }

        if CharacterSet.whitespacesAndNewlines.contains(lhsScalar)
            || CharacterSet.whitespacesAndNewlines.contains(rhsScalar)
            || CharacterSet.punctuationCharacters.contains(rhsScalar)
        {
            return ""
        }

        if rhsScalar.isASCII,
           CharacterSet.alphanumerics.contains(rhsScalar),
           lhsScalar.isASCII,
           CharacterSet.alphanumerics.contains(lhsScalar)
        {
            return " "
        }

        return ""
    }
}

struct PartialTranscriptDisplayThrottle {
    let minimumInterval: TimeInterval

    private(set) var pendingText: String?
    private var lastEmissionTime: TimeInterval?
    private var lastEmittedText = ""

    init(minimumInterval: TimeInterval = 0.22) {
        self.minimumInterval = minimumInterval
    }

    mutating func reset() {
        pendingText = nil
        lastEmissionTime = nil
        lastEmittedText = ""
    }

    mutating func push(_ text: String, at time: TimeInterval) -> String? {
        let normalized = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else { return nil }
        guard normalized != lastEmittedText else {
            pendingText = nil
            return nil
        }

        guard let lastEmissionTime else {
            return emit(normalized, at: time)
        }

        if time - lastEmissionTime >= minimumInterval {
            return emit(normalized, at: time)
        }

        pendingText = normalized
        return nil
    }

    mutating func flush(at time: TimeInterval) -> String? {
        guard let pendingText else { return nil }
        return emit(pendingText, at: time)
    }

    func delayUntilNextEmission(at time: TimeInterval) -> TimeInterval? {
        guard pendingText != nil else { return nil }
        guard let lastEmissionTime else { return 0 }
        return max(0, minimumInterval - (time - lastEmissionTime))
    }

    private mutating func emit(_ text: String, at time: TimeInterval) -> String? {
        guard text != lastEmittedText else {
            pendingText = nil
            return nil
        }
        lastEmittedText = text
        lastEmissionTime = time
        pendingText = nil
        return text
    }
}
