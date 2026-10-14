import Foundation

/// Keeps Emma's two local services usable: LM Studio (the reply model) and the Kokoro voice sidecar.
/// Starts them, loads the model ahead of the first question, and reports a status line for the panel.
/// Failures are never fatal: without the model Emma still transcribes, and without Kokoro she uses the Apple voice.
@MainActor
final class ServiceSupervisor {
    /// Nil when ready, otherwise a hint for the panel.
    var onLLMStatus: ((String?) -> Void)?
    var onTTSStatus: ((String?) -> Void)?
    private(set) var kokoroReady = false

    private let kokoroServer = KokoroServer()
    private let kokoroSpeech: KokoroSpeech
    /// Last time the model was used or warmed; after a minute idle, macOS may have paged it out.
    private var lastModelUse: Date?

    init(kokoroSpeech: KokoroSpeech) {
        self.kokoroSpeech = kokoroSpeech
    }

    /// Makes sure LM Studio's server is up and the model is loaded.
    func checkLLM(_ settings: Settings) async {
        onLLMStatus?("Starting local model…")
        if await !LMStudio.isRunning() {
            guard await LMStudio.startServer() else {
                onLLMStatus?("LM Studio server isn't running. Open LM Studio or run `lms server start`.")
                return
            }
        }
        do {
            try await LMStudio.warmUp(model: settings.modelID, system: PersonaPrompt.build(settings))
            onLLMStatus?(nil)
        } catch {
            onLLMStatus?(error.localizedDescription)
        }
    }

    /// Starts the Kokoro sidecar for Emma's voice and pre-synthesizes the stock phrases.
    func checkTTS(preload phrases: [String]) async {
        onTTSStatus?("Starting Kokoro voice…")
        kokoroReady = await kokoroServer.start { [weak self] status in
            self?.onTTSStatus?("Kokoro: \(status)…")
        }
        onTTSStatus?(kokoroReady ? nil : "Kokoro voice unavailable; using the Apple voice. Log: ~/Library/Logs/Emma-kokoro.log")
        if kokoroReady { await kokoroSpeech.preload(phrases) }
    }

    func preload(_ phrases: [String]) {
        guard kokoroReady else { return }
        Task { await kokoroSpeech.preload(phrases) }
    }

    /// While the user is still talking, pages the model (and the voice) back into RAM if they've been idle.
    /// On this 8 GB Mac an idle model gets swapped out, and the first request then takes about 10 s.
    func prewarm(_ settings: Settings) {
        if let lastModelUse, Date().timeIntervalSince(lastModelUse) < 60 { return }
        noteModelUse()
        let model = settings.modelID
        let system = PersonaPrompt.build(settings)
        Task { try? await LMStudio.warmUp(model: model, system: system) }
        if kokoroReady { Task { _ = try? await KokoroServer.synthesize("Hi.", speed: 1) } }
    }

    func noteModelUse() {
        lastModelUse = Date()
    }
}
