import AVFoundation

/// Speaks reply sentences as they arrive. A protocol so a neural voice can replace Apple's later.
@MainActor
protocol SpeechOutput: AnyObject {
    /// Called once every queued sentence has been spoken after `finishStream()`.
    var onFinished: (() -> Void)? { get set }
    /// Called with true when audio starts playing and false when it goes quiet, even mid-reply.
    var onPlaybackChange: ((Bool) -> Void)? { get set }
    func enqueue(_ sentence: String)
    /// No more sentences are coming for this reply.
    func finishStream()
    /// Silences speech immediately; `onFinished` is not called.
    func stop()
}
