import Foundation
import Speech
import AVFoundation

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

@MainActor
final class SpeechTranscriptionService {
    enum SpeechError: Error {
        case recognizerUnavailable
    }

    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    private var transcriptAccumulator = TranscriptAccumulator()

    func start(localeIdentifier: String, onPartial: @escaping @MainActor (String) -> Void) throws {
        stopCurrentTask()

        guard let recognizer = SFSpeechRecognizer(locale: Locale(identifier: localeIdentifier)), recognizer.isAvailable else {
            throw SpeechError.recognizerUnavailable
        }

        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        request.addsPunctuation = true
        recognitionRequest = request
        transcriptAccumulator.reset()

        recognitionTask = recognizer.recognitionTask(with: request) { [weak self] result, error in
            guard let self else { return }

            Task { @MainActor in
                if let result {
                    let text = result.bestTranscription.formattedString
                    let displayText = if result.isFinal {
                        self.transcriptAccumulator.commit(text)
                    } else {
                        self.transcriptAccumulator.updatePartial(text)
                    }
                    onPartial(displayText)
                }

                if error != nil {
                    self.stopCurrentTask()
                }
            }
        }
    }

    func append(_ buffer: AVAudioPCMBuffer) {
        recognitionRequest?.append(buffer)
    }

    func finish() async -> String {
        recognitionRequest?.endAudio()
        try? await Task.sleep(for: .milliseconds(800))
        let text = transcriptAccumulator.finalText
        stopCurrentTask()
        return text
    }

    func cancel() {
        stopCurrentTask()
    }

    private func stopCurrentTask() {
        recognitionTask?.cancel()
        recognitionTask = nil
        recognitionRequest = nil
    }
}
