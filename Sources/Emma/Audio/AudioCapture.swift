import AVFoundation
import Speech

/// Owns the microphone. Every buffer is
/// 1. forwarded untouched to the wake-word recognizer (if one is attached), and
/// 2. resampled to 16 kHz mono for Whisper, kept in a short pre-roll ring,
///    and — while capturing — accumulated until the speaker goes quiet.
final class AudioCapture: @unchecked Sendable {
    static let sampleRate: Double = 16_000

    var onLevel: ((Float) -> Void)?
    /// Called on the main queue with 16 kHz mono samples. `isFinal` is false for
    /// intermediate segments of a long recording that is still going.
    /// `hadSpeech` is false when the capture timed out in silence.
    var onUtterance: (([Float], _ isFinal: Bool, _ hadSpeech: Bool) -> Void)?

    private let engine = AVAudioEngine()
    private let queue = DispatchQueue(label: "emma.audio")
    // Constant, valid format: init only fails for unsupported parameters.
    private let targetFormat = AVAudioFormat(commonFormat: .pcmFormatFloat32,
                                             sampleRate: AudioCapture.sampleRate,
                                             channels: 1, interleaved: false)! // swiftlint:disable:this force_unwrapping
    private var converter: AVAudioConverter?

    private let requestLock = NSLock()
    private var wakeRequest: SFSpeechAudioBufferRecognitionRequest?

    /// Only touched on `queue`.
    private var endpointer = Endpointer()

    func start() throws {
        let input = engine.inputNode
        let inputFormat = input.outputFormat(forBus: 0)
        guard inputFormat.sampleRate > 0 else {
            throw NSError(domain: "Emma", code: 1,
                          userInfo: [NSLocalizedDescriptionKey: "No microphone input available"])
        }
        converter = AVAudioConverter(from: inputFormat, to: targetFormat)

        input.installTap(onBus: 0, bufferSize: 1024, format: inputFormat) { [weak self] buffer, _ in
            self?.handle(buffer)
        }
        engine.prepare()
        try engine.start()
    }

    func setWakeRequest(_ request: SFSpeechAudioBufferRecognitionRequest?) {
        requestLock.lock()
        wakeRequest = request
        requestLock.unlock()
    }

    /// Start collecting an utterance. `includePreRoll` keeps the audio that contained the wake word.
    func beginCapture(includePreRoll: Bool, noSpeechTimeout: Double? = nil) {
        queue.async { self.endpointer.beginCapture(includePreRoll: includePreRoll, noSpeechTimeout: noSpeechTimeout) }
    }

    func cancelCapture() {
        queue.async { self.endpointer.cancelCapture() }
    }

    /// Endpointing timings, in seconds. Take effect on the next audio chunk.
    func setTimings(endSilence: Double, noSpeechTimeout: Double) {
        queue.async {
            self.endpointer.endSilenceSeconds = endSilence
            self.endpointer.noSpeechTimeoutSeconds = noSpeechTimeout
        }
    }

    private func handle(_ buffer: AVAudioPCMBuffer) {
        requestLock.lock()
        wakeRequest?.append(buffer)
        requestLock.unlock()

        guard let samples = resample(buffer) else { return }
        queue.async { self.process(samples) }
    }

    private func resample(_ buffer: AVAudioPCMBuffer) -> [Float]? {
        guard let converter else { return nil }
        let ratio = AudioCapture.sampleRate / buffer.format.sampleRate
        let capacity = AVAudioFrameCount(Double(buffer.frameLength) * ratio) + 32
        guard let out = AVAudioPCMBuffer(pcmFormat: targetFormat, frameCapacity: capacity) else { return nil }

        var consumed = false
        var error: NSError?
        converter.convert(to: out, error: &error) { _, status in
            if consumed {
                status.pointee = .noDataNow
                return nil
            }
            consumed = true
            status.pointee = .haveData
            return buffer
        }
        guard error == nil, let data = out.floatChannelData else { return nil }
        return Array(UnsafeBufferPointer(start: data[0], count: Int(out.frameLength)))
    }

    private func process(_ samples: [Float]) {
        guard !samples.isEmpty else { return }
        let segment = endpointer.feed(samples)
        let level = endpointer.level
        DispatchQueue.main.async { self.onLevel?(level) }
        if let segment {
            DispatchQueue.main.async { self.onUtterance?(segment.samples, segment.isFinal, segment.hadSpeech) }
        }
    }
}
