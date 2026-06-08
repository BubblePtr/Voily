import Foundation

public struct TranscriptAccumulator: Sendable {
    public private(set) var committedText = ""
    public private(set) var liveText = ""

    public init() {}

    public var displayText: String {
        Self.merge(base: committedText, incoming: liveText)
    }

    public var finalText: String {
        displayText.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    public mutating func reset() {
        committedText = ""
        liveText = ""
    }

    @discardableResult
    public mutating func updatePartial(_ text: String) -> String {
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
    public mutating func commitLiveText() -> String {
        let normalized = Self.normalize(liveText)
        if !normalized.isEmpty {
            committedText = Self.mergeAllowingSuffixRevision(base: committedText, incoming: normalized)
        }
        liveText = ""
        return committedText
    }

    @discardableResult
    public mutating func reviseCommittedSuffix(_ text: String) -> String {
        let normalized = Self.normalize(text)
        if !normalized.isEmpty {
            committedText = Self.mergeAllowingSuffixRevision(base: committedText, incoming: normalized)
        }
        return displayText
    }

    @discardableResult
    public mutating func appendDelta(_ text: String) -> String {
        let normalized = Self.normalize(text)
        guard !normalized.isEmpty else { return displayText }

        let existing = Self.normalize(liveText)
        liveText = existing.isEmpty
            ? normalized
            : Self.merge(base: existing, incoming: normalized)
        return displayText
    }

    @discardableResult
    public mutating func updateOverlappingPartial(_ text: String) -> String {
        let normalized = Self.normalize(text)
        guard !normalized.isEmpty else { return displayText }

        let merged = Self.mergeAllowingSuffixRevision(base: displayText, incoming: normalized)
        if committedText.isEmpty {
            liveText = merged
        } else if merged == committedText || committedText.hasSuffix(merged) {
            liveText = ""
        } else if merged.hasPrefix(committedText) {
            liveText = Self.normalize(String(merged.dropFirst(committedText.count)))
        } else {
            liveText = normalized
        }
        return displayText
    }

    @discardableResult
    public mutating func commit(_ text: String) -> String {
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

        return merge(base: lhs, incoming: rhs, minimumOverlapLength: 1)
    }

    private static func mergeAllowingSuffixRevision(base: String, incoming: String) -> String {
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
        if let revised = revisedSuffixMerge(base: lhs, incoming: rhs) {
            return revised
        }
        return merge(base: lhs, incoming: rhs, minimumOverlapLength: 2)
    }

    private static func merge(
        base lhs: String,
        incoming rhs: String,
        minimumOverlapLength: Int
    ) -> String {
        let overlap = overlapLength(lhs, rhs)
        guard overlap >= minimumOverlapLength else {
            return lhs + separator(between: lhs, and: rhs) + rhs
        }

        let suffixStart = rhs.index(rhs.startIndex, offsetBy: overlap)
        let suffix = String(rhs[suffixStart...])
        guard !suffix.isEmpty else { return lhs }
        return lhs + separator(between: lhs, and: suffix) + suffix
    }

    private static func revisedSuffixMerge(base lhs: String, incoming rhs: String) -> String? {
        let lhsCharacters = Array(lhs)
        let rhsCharacters = Array(rhs)
        let maxOverlap = min(lhsCharacters.count, rhsCharacters.count, 48)
        let minimumOverlap = 4
        guard maxOverlap >= minimumOverlap else { return nil }

        var bestCandidate: (lhsLength: Int, rhsLength: Int, edits: Int, score: Int)?
        for lhsLength in stride(from: maxOverlap, through: minimumOverlap, by: -1) {
            for rhsLength in candidatePrefixLengths(around: lhsLength, maxLength: maxOverlap) {
                let lhsSuffix = Array(lhsCharacters.suffix(lhsLength))
                let rhsPrefix = Array(rhsCharacters.prefix(rhsLength))
                guard lhsSuffix != rhsPrefix else { continue }

                let maxLength = max(lhsLength, rhsLength)
                let allowedEdits = max(1, Int(Double(maxLength) * 0.34))
                let edits = editDistance(lhsSuffix, rhsPrefix, maxDistance: allowedEdits)
                guard edits <= allowedEdits else { continue }

                let score = maxLength - (edits * 2)
                guard score >= minimumOverlap else { continue }

                if let current = bestCandidate {
                    if score < current.score {
                        continue
                    }
                    let candidateLength = max(lhsLength, rhsLength)
                    let currentLength = max(current.lhsLength, current.rhsLength)
                    if score == current.score, candidateLength < currentLength {
                        continue
                    }
                    if score == current.score, candidateLength == currentLength, edits >= current.edits {
                        continue
                    }
                }
                bestCandidate = (lhsLength, rhsLength, edits, score)
            }
        }

        guard let bestCandidate else { return nil }
        let stableEnd = lhs.index(lhs.endIndex, offsetBy: -bestCandidate.lhsLength)
        let stablePrefix = String(lhs[..<stableEnd])
        guard !stablePrefix.isEmpty else { return rhs }
        return stablePrefix + separator(between: stablePrefix, and: rhs) + rhs
    }

    private static func candidatePrefixLengths(around length: Int, maxLength: Int) -> [Int] {
        var seen = Set<Int>()
        return [length, length - 1, length + 1, length - 2, length + 2].compactMap { candidate in
            guard candidate >= 4, candidate <= maxLength, !seen.contains(candidate) else { return nil }
            seen.insert(candidate)
            return candidate
        }
    }

    private static func editDistance(
        _ lhs: [Character],
        _ rhs: [Character],
        maxDistance: Int
    ) -> Int {
        guard abs(lhs.count - rhs.count) <= maxDistance else {
            return maxDistance + 1
        }

        var previous = Array(0 ... rhs.count)
        var current = Array(repeating: 0, count: rhs.count + 1)

        for (lhsIndex, lhsCharacter) in lhs.enumerated() {
            current[0] = lhsIndex + 1
            var rowMinimum = current[0]

            for (rhsIndex, rhsCharacter) in rhs.enumerated() {
                let substitutionCost = lhsCharacter == rhsCharacter ? 0 : 1
                current[rhsIndex + 1] = min(
                    previous[rhsIndex + 1] + 1,
                    current[rhsIndex] + 1,
                    previous[rhsIndex] + substitutionCost
                )
                rowMinimum = min(rowMinimum, current[rhsIndex + 1])
            }

            guard rowMinimum <= maxDistance else {
                return maxDistance + 1
            }
            swap(&previous, &current)
        }

        return previous[rhs.count]
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

public struct PartialTranscriptDisplayThrottle: Sendable {
    public let minimumInterval: TimeInterval

    public private(set) var pendingText: String?
    private var lastEmissionTime: TimeInterval?
    private var lastEmittedText = ""

    public init(minimumInterval: TimeInterval = 0.22) {
        self.minimumInterval = minimumInterval
    }

    public mutating func reset() {
        pendingText = nil
        lastEmissionTime = nil
        lastEmittedText = ""
    }

    public mutating func push(_ text: String, at time: TimeInterval) -> String? {
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

    public mutating func flush(at time: TimeInterval) -> String? {
        guard let pendingText else { return nil }
        return emit(pendingText, at: time)
    }

    public func delayUntilNextEmission(at time: TimeInterval) -> TimeInterval? {
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
