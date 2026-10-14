import AVFoundation

/// Emma's voice: Kokoro when its sidecar is ready, the Apple voice otherwise. Picks the voice per reply,
/// applies speed and pause, rewrites text for speaking, and logs every spoken sentence.
@MainActor
final class Voice {
    /// Every queued sentence has been spoken after `finish()`.
    var onFinished: (() -> Void)?
    /// Audio started (true) or went quiet (false).
    var onPlaybackChange: ((Bool) -> Void)?
    /// A Kokoro sentence had to fall back to the Apple voice.
    var onFallback: (() -> Void)?

    let kokoro = KokoroSpeech()
    private let apple = AppleSpeech()
    private lazy var current: SpeechOutput = apple

    init() {
        for output in [apple as SpeechOutput, kokoro] {
            output.onFinished = { [weak self] in self?.onFinished?() }
            output.onPlaybackChange = { [weak self] playing in self?.onPlaybackChange?(playing) }
        }
        kokoro.onFallback = { [weak self] in self?.onFallback?() }
    }

    /// Picks the voice for the next reply and applies the voice settings.
    func prepare(_ settings: Settings, kokoroReady: Bool) {
        current = kokoroReady ? kokoro : apple
        configure(settings)
    }

    func configure(_ settings: Settings) {
        kokoro.speed = settings.speechSpeed
        kokoro.pause = settings.sentencePause
        apple.rate = min(AVSpeechUtteranceMaximumSpeechRate, AVSpeechUtteranceDefaultSpeechRate * Float(settings.speechSpeed))
    }

    /// Speaks sentences with symbols and markup rewritten for the voice.
    func speak(_ sentences: [String]) {
        let spoken = sentences.map(SpeechText.clean).filter { !$0.isEmpty }
        spoken.forEach { ConversationLog.write("SAID", $0) }
        spoken.forEach(current.enqueue)
    }

    /// A stock phrase said as is, like a filler.
    func say(_ phrase: String) {
        current.enqueue(phrase)
    }

    /// No more sentences for this reply; `onFinished` fires once they've been spoken.
    func finish() {
        current.finishStream()
    }

    func stop() {
        current.stop()
    }

    /// Says a short line with the given settings, without changing the current reply's voice.
    func preview(_ settings: Settings, kokoroReady: Bool) {
        let output: SpeechOutput = kokoroReady ? kokoro : apple
        configure(settings)
        // Avoids the wake word, since the mic is listening for it.
        output.enqueue("Hi, this is how I sound.")
        output.finishStream()
    }
}
