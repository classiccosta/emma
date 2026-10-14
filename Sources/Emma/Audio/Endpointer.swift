/// Decides where utterances start and end in a stream of 16 kHz mono samples.
/// Pure state, no audio engine or queues, so it can be driven by synthetic signals.
/// The owner must serialize calls (`AudioCapture` uses its `emma.audio` queue).
struct Endpointer {
    struct Segment: Equatable {
        let samples: [Float]
        /// False for intermediate segments of a long recording that is still going.
        let isFinal: Bool
        /// False when the capture timed out without any speech.
        var hadSpeech = true
    }

    let sampleRate: Double = AudioCapture.sampleRate
    /// Audio kept from before the wake word fired, so "Emma, what time is it" isn't clipped.
    let preRollSeconds: Double = 1.5
    /// Silence after speech that ends an utterance. Adjustable from the panel's settings.
    var endSilenceSeconds: Double = 3.0
    /// Give up if nothing is said after the wake word. Adjustable from the panel's settings.
    var noSpeechTimeoutSeconds: Double = 5.0
    /// Long speech is chopped into segments of this length (cut at the latest pause)
    /// and handed off for transcription while recording continues.
    let segmentSeconds: Double = 120.0
    /// How far back from the segment boundary to look for a pause to cut at.
    let cutSearchSeconds: Double = 5.0

    /// RMS of the most recent chunk fed in.
    private(set) var level: Float = 0
    private(set) var noiseFloor: Float = 0.003
    private(set) var capturing = false

    private var preRoll: [Float] = []
    private var captured: [Float] = []
    private var capturedSinceStart = 0
    /// Position in `captured` right after the most recent quiet frame.
    private var lastQuietEnd = 0
    private var speechStarted = false
    private var silentSamples = 0
    /// `noSpeechTimeoutSeconds`, or the override passed to the current `beginCapture`.
    private var activeNoSpeechTimeout: Double = 5.0

    /// Start collecting an utterance. `includePreRoll` keeps the audio that contained the wake word.
    /// `noSpeechTimeout` overrides `noSpeechTimeoutSeconds` for this capture only.
    mutating func beginCapture(includePreRoll: Bool, noSpeechTimeout: Double? = nil) {
        activeNoSpeechTimeout = noSpeechTimeout ?? noSpeechTimeoutSeconds
        captured = includePreRoll ? preRoll : []
        capturedSinceStart = 0
        lastQuietEnd = 0
        speechStarted = false
        silentSamples = 0
        capturing = true
    }

    /// Drops the current capture without emitting a segment.
    mutating func cancelCapture() {
        capturing = false
        captured = []
    }

    /// Feeds one chunk and returns a segment when one is complete.
    mutating func feed(_ samples: [Float]) -> Segment? {
        guard !samples.isEmpty else { return nil }
        let rms = (samples.reduce(0) { $0 + $1 * $1 } / Float(samples.count)).squareRoot()
        level = rms

        if !capturing {
            // Track background noise so the speech threshold adapts to the room.
            noiseFloor = rms < noiseFloor ? (noiseFloor + rms) / 2 : noiseFloor * 0.999 + rms * 0.001
            preRoll.append(contentsOf: samples)
            let maxPreRoll = Int(preRollSeconds * sampleRate)
            if preRoll.count > maxPreRoll { preRoll.removeFirst(preRoll.count - maxPreRoll) }
            return nil
        }

        captured.append(contentsOf: samples)
        capturedSinceStart += samples.count

        let isSpeech = rms > max(noiseFloor * 3, 0.006)
        if isSpeech {
            speechStarted = true
            silentSamples = 0
        } else {
            silentSamples += samples.count
            lastQuietEnd = captured.count
        }

        let sr = sampleRate
        let done = (speechStarted && Double(silentSamples) >= endSilenceSeconds * sr)
            || (!speechStarted && Double(capturedSinceStart) >= activeNoSpeechTimeout * sr)

        if done {
            capturing = false
            let utterance = captured
            captured = []
            preRoll = []
            return Segment(samples: utterance, isFinal: true, hadSpeech: speechStarted)
        } else if Double(captured.count) >= segmentSeconds * sr {
            // Still talking at the segment limit: chop at the latest pause and keep recording.
            let earliestCut = captured.count - Int(cutSearchSeconds * sr)
            let cut = lastQuietEnd > earliestCut ? lastQuietEnd : captured.count
            let segment = Array(captured[..<cut])
            captured.removeFirst(cut)
            lastQuietEnd = 0
            return Segment(samples: segment, isFinal: false)
        }
        return nil
    }
}
