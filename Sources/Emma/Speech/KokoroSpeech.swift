import AVFoundation
import Foundation

/// Speaks reply sentences with Kokoro. The first sentence is synthesized alone so speech starts fast;
/// sentences that arrive while a request is in flight are then sent together, so the intonation flows
/// across them instead of every sentence getting the same flat contour. Synthesis overlaps playback.
/// A batch that fails to synthesize is spoken with the Apple voice instead, so a reply is never lost.
@MainActor
final class KokoroSpeech: NSObject, SpeechOutput {
    private enum Clip {
        case wav(Data)
        case apple(String)
    }

    var onFinished: (() -> Void)?
    var onPlaybackChange: ((Bool) -> Void)?
    private var reportedPlaying = false
    /// Called when a sentence had to fall back to the Apple voice.
    var onFallback: (() -> Void)?
    /// Kokoro's "Emma" (UK, female), the only voice the sidecar keeps.
    nonisolated static let voice = "bf_emma"
    var speed = 1.0
    /// Silence after each sentence, in seconds.
    var pause = 0.3

    private let fallback = AppleSpeech()
    /// Sentences waiting to be synthesized. Only one request is in flight at a time, which keeps clips in order.
    private var pending: [String] = []
    private var synthesizing = false
    private var clips: [Clip] = []
    private var player: AVAudioPlayer?
    private var fallbackPlaying = false
    private var streamDone = false
    /// Bumped by `stop()` so results from cancelled requests are dropped.
    private var generation = 0
    /// Pre-synthesized clips, keyed by speed and text, so stock phrases play with no delay.
    private var cache: [String: Data] = [:]

    private var isPlaying: Bool { player != nil || fallbackPlaying }

    override init() {
        super.init()
        fallback.onFinished = { [weak self] in
            self?.fallbackPlaying = false
            self?.playNext()
        }
    }

    /// Synthesizes `sentences` ahead of time so `enqueue` can play them instantly.
    func preload(_ sentences: [String]) async {
        for sentence in sentences where cache[cacheKey(sentence)] == nil {
            if let data = try? await KokoroServer.synthesize(sentence, speed: speed, pause: pause) {
                cache[cacheKey(sentence)] = data
            }
        }
    }

    private func cacheKey(_ sentence: String) -> String {
        "\(speed)|\(pause)|\(sentence)"
    }

    func enqueue(_ sentence: String) {
        pending.append(sentence)
        synthesizeNext()
    }

    /// Sends everything pending as one request, except that a pre-synthesized phrase plays on its own.
    private func synthesizeNext() {
        guard !synthesizing, let first = pending.first else { return }
        let speed = speed
        let generation = generation
        let pause = pause
        let keys = Dictionary(pending.map { ($0, cacheKey($0)) }, uniquingKeysWith: { first, _ in first })
        let isCached = { [cache] (sentence: String) in keys[sentence].flatMap { cache[$0] } != nil }
        let batch = isCached(first) ? [first] : Array(pending.prefix { !isCached($0) })
        pending.removeFirst(batch.count)
        let text = batch.joined(separator: " ")
        let cached = cache[cacheKey(text)]
        synthesizing = true
        Task { [weak self] in
            let clip: Clip
            do {
                if let cached {
                    clip = .wav(cached)
                } else {
                    clip = .wav(try await KokoroServer.synthesize(text, speed: speed, pause: pause))
                }
            } catch {
                clip = .apple(text)
            }
            self?.received(clip, generation: generation)
        }
    }

    func finishStream() {
        streamDone = true
        playNext()
    }

    func stop() {
        generation += 1
        pending.removeAll()
        synthesizing = false
        clips.removeAll()
        streamDone = false
        player?.stop()
        player = nil
        if fallbackPlaying { fallback.stop() }
        fallbackPlaying = false
        reportedPlaying = false
    }

    private func received(_ clip: Clip, generation: Int) {
        guard generation == self.generation else { return }
        synthesizing = false
        if case .apple = clip { onFallback?() }
        clips.append(clip)
        synthesizeNext()
        playNext()
    }

    /// Starts the next clip if nothing is playing, or reports the end of the reply.
    private func playNext() {
        guard !isPlaying else { return }
        guard !clips.isEmpty else {
            report(playing: false)
            if streamDone, pending.isEmpty, !synthesizing {
                streamDone = false
                onFinished?()
            }
            return
        }
        switch clips.removeFirst() {
        case .wav(let data):
            guard let player = try? AVAudioPlayer(data: data) else { return playNext() }
            player.delegate = self
            self.player = player
            report(playing: true)
            player.play()
        case .apple(let sentence):
            fallbackPlaying = true
            report(playing: true)
            fallback.enqueue(sentence)
            fallback.finishStream()
        }
    }

    private func report(playing: Bool) {
        guard playing != reportedPlaying else { return }
        reportedPlaying = playing
        onPlaybackChange?(playing)
    }

        fileprivate func playerEnded(_ id: ObjectIdentifier) {
        guard let player, ObjectIdentifier(player) == id else { return }
        self.player = nil
        playNext()
    }
}

extension KokoroSpeech: AVAudioPlayerDelegate {
    nonisolated func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        let id = ObjectIdentifier(player)
        Task { @MainActor in self.playerEnded(id) }
    }

    nonisolated func audioPlayerDecodeErrorDidOccur(_ player: AVAudioPlayer, error: Error?) {
        let id = ObjectIdentifier(player)
        Task { @MainActor in self.playerEnded(id) }
    }
}
