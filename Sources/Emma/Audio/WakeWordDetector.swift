import Foundation
import Speech

/// Spots "Emma" using Apple's on-device speech recognizer.
/// Keyless and free; the recognizer only runs while we're idle and is
/// recycled every ~50 s so its running transcript never grows large.
@MainActor
final class WakeWordDetector {
    var onWake: (() -> Void)?
    private(set) var isOnDevice = false

    private let audio: AudioCapture
    private let recognizer = SFSpeechRecognizer(locale: Locale(identifier: "en-US"))

    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?
    private var recycleTimer: Timer?
    private var generation = 0
    private var hits = 0

    init(audio: AudioCapture) {
        self.audio = audio
    }

    func start() {
        stop()
        guard let recognizer, recognizer.isAvailable else {
            scheduleRestart(after: 2)
            return
        }

        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        request.contextualStrings = ["Emma", "Hey Emma"]
        isOnDevice = recognizer.supportsOnDeviceRecognition
        if isOnDevice { request.requiresOnDeviceRecognition = true }

        generation += 1
        let current = generation
        hits = 0
        self.request = request
        audio.setWakeRequest(request)

        task = recognizer.recognitionTask(with: request) { [weak self] result, error in
            let text = result?.bestTranscription.formattedString
            let isFinal = result?.isFinal ?? false
            let failed = error != nil
            DispatchQueue.main.async {
                self?.handle(text: text, isFinal: isFinal, failed: failed, generation: current)
            }
        }

        // Scheduled on the main run loop, so the callback is already on the main actor.
        recycleTimer = Timer.scheduledTimer(withTimeInterval: 50, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated { self?.start() }
        }
    }

    func stop() {
        generation += 1
        recycleTimer?.invalidate()
        recycleTimer = nil
        audio.setWakeRequest(nil)
        request?.endAudio()
        task?.cancel()
        request = nil
        task = nil
    }

    private func handle(text: String?, isFinal: Bool, failed: Bool, generation: Int) {
        guard generation == self.generation else { return }

        if let text {
            // Partial results repeat the whole running transcript, so count occurrences.
            let count = Self.wakeCount(in: text)
            if count > hits {
                hits = count
                stop()
                onWake?()
                return
            }
        }
        if failed {
            scheduleRestart(after: 1)
        } else if isFinal {
            start()
        }
    }

    private func scheduleRestart(after seconds: TimeInterval) {
        let current = generation
        DispatchQueue.main.asyncAfter(deadline: .now() + seconds) { [weak self] in
            guard let self, self.generation == current else { return }
            self.start()
        }
    }

    /// Whole-word, case-insensitive count of "emma", so "Gemma" and "dilemma" don't wake her.
    nonisolated static func wakeCount(in text: String) -> Int {
        text.ranges(of: #/(?i)\bemma\b/#).count
    }
}
