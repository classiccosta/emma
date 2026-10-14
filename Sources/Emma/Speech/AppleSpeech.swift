import AVFoundation

@MainActor
final class AppleSpeech: NSObject, SpeechOutput {
    var onFinished: (() -> Void)?
    var onPlaybackChange: ((Bool) -> Void)?
    var rate = AVSpeechUtteranceDefaultSpeechRate

    private let synthesizer = AVSpeechSynthesizer()
    private let voice = AppleSpeech.bestVoice()
    private var pending: Set<ObjectIdentifier> = []
    private var streamDone = false

    override init() {
        super.init()
        synthesizer.delegate = self
    }

    func enqueue(_ sentence: String) {
        let utterance = AVSpeechUtterance(string: sentence)
        utterance.voice = voice
        utterance.rate = rate
        if pending.isEmpty { onPlaybackChange?(true) }
        pending.insert(ObjectIdentifier(utterance))
        synthesizer.speak(utterance)
    }

    func finishStream() {
        streamDone = true
        checkFinished()
    }

    func stop() {
        pending.removeAll()
        streamDone = false
        synthesizer.stopSpeaking(at: .immediate)
    }

    fileprivate func utteranceEnded(_ id: ObjectIdentifier) {
        guard pending.remove(id) != nil else { return }
        if pending.isEmpty { onPlaybackChange?(false) }
        checkFinished()
    }

    private func checkFinished() {
        guard streamDone, pending.isEmpty else { return }
        streamDone = false
        onFinished?()
    }

    /// An enhanced or premium en-US voice if one is installed, else the system default.
    /// Picking only by quality avoids the novelty voices, which are all default quality.
    private static func bestVoice() -> AVSpeechSynthesisVoice? {
        let better = AVSpeechSynthesisVoice.speechVoices()
            .filter { $0.language == "en-US" && $0.quality != .default }
            .max { $0.quality.rawValue < $1.quality.rawValue }
        return better ?? AVSpeechSynthesisVoice(language: "en-US")
    }
}

extension AppleSpeech: AVSpeechSynthesizerDelegate {
    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        let id = ObjectIdentifier(utterance)
        Task { @MainActor in self.utteranceEnded(id) }
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        let id = ObjectIdentifier(utterance)
        Task { @MainActor in self.utteranceEnded(id) }
    }
}
