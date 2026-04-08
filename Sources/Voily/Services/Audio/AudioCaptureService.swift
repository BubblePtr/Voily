import AVFoundation

final class AudioCaptureService {
    enum AudioCaptureError: Error {
        case unavailableInput
    }

    private let engine = AVAudioEngine()
    private var isRunning = false
    func start(onBuffer: @escaping (AVAudioPCMBuffer) -> Void, onLevel: @escaping (Float) -> Void) throws {
        guard !isRunning else { return }

        let inputNode = engine.inputNode
        let format = inputNode.inputFormat(forBus: 0)
        guard format.sampleRate > 0 else {
            throw AudioCaptureError.unavailableInput
        }

        inputNode.removeTap(onBus: 0)
        inputNode.installTap(onBus: 0, bufferSize: 2048, format: format) { buffer, _ in
            onBuffer(buffer)

            let rms = Self.calculateRMS(buffer: buffer)
            onLevel(rms)
        }

        engine.prepare()
        try engine.start()
        isRunning = true
    }

    func stop() {
        guard isRunning else { return }
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        isRunning = false
    }

    private static func calculateRMS(buffer: AVAudioPCMBuffer) -> Float {
        guard let channelData = buffer.floatChannelData else { return 0 }

        let channel = channelData[0]
        let frameCount = Int(buffer.frameLength)
        guard frameCount > 0 else { return 0 }

        var sum: Float = 0
        for index in 0 ..< frameCount {
            let value = channel[index]
            sum += value * value
        }

        let rms = sqrt(sum / Float(frameCount))
        return min(max(rms * 10, 0), 1)
    }
}
