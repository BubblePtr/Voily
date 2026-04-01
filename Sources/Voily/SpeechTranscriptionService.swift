import Foundation
import Speech
import AVFoundation

@MainActor
final class SpeechTranscriptionService {
    enum SpeechError: Error {
        case recognizerUnavailable
    }

    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    private var latestText = ""
    private var latestFinalText = ""
    func start(localeIdentifier: String, onPartial: @escaping @MainActor (String) -> Void) throws {
        stopCurrentTask()

        guard let recognizer = SFSpeechRecognizer(locale: Locale(identifier: localeIdentifier)), recognizer.isAvailable else {
            throw SpeechError.recognizerUnavailable
        }

        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        request.addsPunctuation = true
        recognitionRequest = request
        latestText = ""
        latestFinalText = ""

        recognitionTask = recognizer.recognitionTask(with: request) { [weak self] result, error in
            guard let self else { return }

            Task { @MainActor in
                if let result {
                    let text = result.bestTranscription.formattedString
                    self.latestText = text
                    if result.isFinal {
                        self.latestFinalText = text
                    }

                    onPartial(text)
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
        let text = latestFinalText.isEmpty ? latestText : latestFinalText
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
