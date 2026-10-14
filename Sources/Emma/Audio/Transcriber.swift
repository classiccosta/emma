import Foundation
@preconcurrency import WhisperKit

/// Speech-to-text with WhisperKit: loads the model once, then turns 16 kHz mono samples into cleaned text.
@MainActor
final class Transcriber {
    /// WhisperKit model, matched against argmaxinc/whisperkit-coreml.
    /// Try "base.en" (faster) or "large-v3-v20240930_turbo_632MB" (more accurate).
    static let modelName = "small.en"

    // Whisper sees 30 s windows; VAD chunking splits longer speech at pauses
    // instead of letting the decoder skip text between windows.
    private static let decodingOptions = DecodingOptions(task: .transcribe, language: "en", temperature: 0,
                                                         skipSpecialTokens: true, withoutTimestamps: false,
                                                         chunkingStrategy: .vad)

    private var whisper: WhisperKit?

    /// Downloads (first run) and loads the model.
    func load() async throws {
        let config = WhisperKitConfig(model: Self.modelName, verbose: false, logLevel: .error,
                                      prewarm: true, load: true, download: true)
        whisper = try await WhisperKit(config)
    }

    /// Cleaned text for the samples, and how long Whisper took. Empty text if the model isn't loaded.
    func transcribe(_ samples: [Float]) async -> (text: String, seconds: Double) {
        guard let whisper else { return ("", 0) }
        let started = Date()
        let results = await Self.run(whisper, samples: samples)
        return (Self.clean(results.map(\.text).joined(separator: " ")), Date().timeIntervalSince(started))
    }

    /// Nonisolated so WhisperKit's default (non-Sendable) callbacks are created off the main actor.
    private nonisolated static func run(_ whisper: WhisperKit, samples: [Float]) async -> [TranscriptionResult] {
        (try? await whisper.transcribe(audioArray: samples, decodeOptions: decodingOptions)) ?? []
    }

    /// Drops the wake word and Whisper's bracketed non-speech tags like "[BLANK_AUDIO]".
    nonisolated static func clean(_ raw: String) -> String {
        var text = raw.replacingOccurrences(of: #"\[[^\]]*\]|\([^)]*\)"#, with: "", options: .regularExpression)
        text = text.replacingOccurrences(of: #"^\s*(hey[\s,]+)?emma\b[\s,.!?]*"#, with: "",
                                         options: [.regularExpression, .caseInsensitive])
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
