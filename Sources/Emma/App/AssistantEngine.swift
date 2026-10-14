import Foundation

/// Wires mic -> wake word -> utterance capture -> Whisper -> reply routing -> local LLM (LM Studio) -> speech,
/// and runs the phase state machine the panel shows. The work itself lives in focused collaborators:
/// `Transcriber`, `ServiceSupervisor`, `ReplyRouter`, `ReplySession`, `StockReplies` and `ChatHistory`.
@MainActor
final class AssistantEngine: ObservableObject {
    @Published private(set) var phase: Phase = .loading("Starting…")
    @Published private(set) var level: Float = 0
    @Published private(set) var entries: [TranscriptEntry] = []
    @Published private(set) var wakeIsOnDevice = false
    /// True once a recording has passed the first segment and keeps going.
    @Published private(set) var isLongRecording = false
    /// Persisted in UserDefaults; changed through `applySettings`.
    @Published private(set) var settings: Settings
    /// Nil when the local model is ready; otherwise a hint shown in the panel.
    @Published private(set) var llmStatus: String?
    /// Nil when the chosen voice is ready; otherwise a hint shown in the panel.
    @Published private(set) var ttsStatus: String?
    /// Listening for a reply right after Emma spoke, without the wake word.
    @Published private(set) var isFollowUp = false

    private let audio = AudioCapture()
    private lazy var wake = WakeWordDetector(audio: audio)
    private let transcriber = Transcriber()
    /// Segments are transcribed strictly in order; each waits for the previous one.
    private var transcriptionChain: Task<Void, Never>?
    /// The entry that segments of the current recording are appended to.
    private var currentEntryID: UUID?
    /// The current capture started from the wake word (not "Listen now" or a follow-up).
    private var isWakeCapture = false

    private let voice = Voice()
    private lazy var services = ServiceSupervisor(kokoroSpeech: voice.kokoro)

    private var stock = StockReplies()
    private var history = ChatHistory()
    private var session: ReplySession?
    private var replyTask: Task<Void, Never>?
    /// Emma's previous reply, checked for an offer the user might decline.
    private var lastReplyText = ""
    private var lastReplyAt: Date?
    /// Set by an ending reply ("Very well, sir.", "Anytime, sir."): no follow-up window.
    private var skipFollowUp = false

    init() {
        settings = Settings.load()
        stock.update(settings)
        ConversationLog.write("START", "Emma launched")
        audio.setTimings(endSilence: settings.endSilence, noSpeechTimeout: settings.noSpeechTimeout)
        voice.onFinished = { [weak self] in self?.finishReply() }
        voice.onPlaybackChange = { [weak self] playing in self?.playbackChanged(playing) }
        voice.onFallback = { [weak self] in self?.ttsStatus = "Kokoro voice didn't answer; using the Apple voice. Log: ~/Library/Logs/Emma-kokoro.log" }
        services.onLLMStatus = { [weak self] in self?.llmStatus = $0 }
        services.onTTSStatus = { [weak self] in self?.ttsStatus = $0 }
        voice.configure(settings)
        audio.onLevel = { [weak self] level in self?.level = level }
        audio.onUtterance = { [weak self] in self?.enqueue($0, isFinal: $1, hadSpeech: $2) }
        wake.onWake = { [weak self] in self?.beginListening(includePreRoll: true) }
        Task { await boot() }
    }

    // MARK: - Panel and settings actions

    func listenNow() {
        beginListening(includePreRoll: false)
    }

    func clear() {
        entries.removeAll()
        history.clear()
    }

    /// Cuts off the current reply, spoken or still streaming, or ends a follow-up window.
    func stopReply() {
        if isFollowUp { audio.cancelCapture() }
        endSession()
        voice.stop()
        goIdle()
    }

    /// Clamps to the allowed ranges, persists, and applies. A changed model is loaded right away.
    func applySettings(_ draft: Settings) {
        let new = draft.normalized
        let old = settings
        settings = new
        new.save()
        audio.setTimings(endSilence: new.endSilence, noSpeechTimeout: new.noSpeechTimeout)
        voice.configure(new)
        stock.update(new)
        if new != old { services.preload(stock.allRendered) }
        if new.modelID != old.modelID { Task { await services.checkLLM(new) } }
    }

    /// Says a short line with the draft voice settings, without saving them.
    func previewVoice(_ draft: Settings) {
        guard phase == .idle else { return }
        voice.preview(draft.normalized, kokoroReady: services.kokoroReady)
    }

    // MARK: - Boot and listening

    private func boot() async {
        if let denied = await Permissions.request() {
            phase = .failed(denied)
            return
        }
        do {
            try audio.start()
        } catch {
            phase = .failed("Microphone failed to start: \(error.localizedDescription)")
            return
        }
        phase = .loading("Loading Whisper \(Transcriber.modelName)… first run downloads and optimizes the model (a few minutes).")
        do {
            try await transcriber.load()
        } catch {
            phase = .failed("Whisper failed to load: \(error.localizedDescription)")
            return
        }
        goIdle()
        await services.checkLLM(settings)
        await services.checkTTS(preload: stock.allRendered)
    }

    private func goIdle() {
        phase = .idle
        isFollowUp = false
        wake.start()
        wakeIsOnDevice = wake.isOnDevice
    }

    private func beginListening(includePreRoll: Bool) {
        guard phase == .idle else { return }
        wake.stop()
        phase = .listening
        isWakeCapture = includePreRoll
        audio.beginCapture(includePreRoll: includePreRoll, noSpeechTimeout: includePreRoll ? settings.bareCallWindow : nil)
        services.prewarm(settings)
    }

    private func enqueue(_ samples: [Float], isFinal: Bool, hadSpeech: Bool) {
        // Silence after a reply: skip Whisper, which tends to invent "Thank you." from silence.
        if isFinal, !hadSpeech, isFollowUp {
            ConversationLog.write("IDLE", "follow-up window ended in silence")
            goIdle()
            return
        }
        if isFinal, !hadSpeech, isWakeCapture {
            isWakeCapture = false
            answerBareCall(samples)
            return
        }
        if isFinal {
            isWakeCapture = false
            isFollowUp = false
            phase = .transcribing
        } else {
            isLongRecording = true
        }
        let previous = transcriptionChain
        transcriptionChain = Task {
            await previous?.value
            await transcribe(samples, isFinal: isFinal)
        }
    }

    private func transcribe(_ samples: [Float], isFinal: Bool) async {
        defer {
            if isFinal {
                let finishedID = currentEntryID
                currentEntryID = nil
                isLongRecording = false
                transcriptionChain = nil
                if let finishedID, let entry = entries.first(where: { $0.id == finishedID }) {
                    respond(to: entry)
                } else {
                    goIdle()
                }
            }
        }
        let (text, seconds) = await transcriber.transcribe(samples)
        let audioSeconds = Double(samples.count) / AudioCapture.sampleRate
        let recentReply = lastReplyAt.map { Date().timeIntervalSince($0) < 30 } ?? false
        let keep = ReplyRouter.shouldAnswer(text, ignoreNoise: settings.ignoreNoise, recentReply: recentReply)
        if !text.isEmpty { ConversationLog.write(keep ? "HEARD" : "DROPPED", text) }
        guard keep else { return }

        if let id = currentEntryID, let index = entries.firstIndex(where: { $0.id == id }) {
            entries[index].append(text, audioSeconds: audioSeconds, transcribeSeconds: seconds)
        } else {
            let entry = TranscriptEntry(text: text, audioSeconds: audioSeconds, transcribeSeconds: seconds)
            entries.append(entry)
            currentEntryID = entry.id
        }
    }
}

// MARK: - Replies

extension AssistantEngine {
    /// Answers a finished transcript: a stock reply when `ReplyRouter` finds one, otherwise the model.
    private func respond(to entry: TranscriptEntry) {
        // A bare-call greeting may already be playing; the playback callback keeps the phase honest.
        if phase != .speaking { phase = .thinking }
        if let lastReplyAt, Date().timeIntervalSince(lastReplyAt) > settings.conversationResetMinutes * 60 {
            history.clear()
        }
        voice.prepare(settings, kokoroReady: services.kokoroReady)

        let route = ReplyRouter.route(entry.text, lastReply: lastReplyText, butlerCheck: settings.butlerCheck)
        lastReplyText = ""
        switch route {
        case .declinedOffer: reply([stock.declineAck()], to: entry, route: "declined offer", ends: true, remember: true)
        case .greeting:
            // A greeting starts a fresh conversation; the follow-up window stays open for the actual question.
            history.clear()
            reply(stock.greeting(), to: entry, route: "greeting")
        case .closing: reply([stock.closing()], to: entry, route: "closing", ends: true)
        case .inconclusive:
            // A question: "no" / "nothing" afterwards counts as a declined offer.
            let question = stock.anythingElse
            reply([question], to: entry, route: "inconclusive")
            lastReplyText = question
        case .model(let feelings): askModel(entry, feelings: feelings)
        }
    }

    /// A fixed reply without the model. `ends` skips the follow-up window; `remember` puts the exchange
    /// in the model's history (a declined offer, so the model knows).
    private func reply(_ parts: [String], to entry: TranscriptEntry, route: String, ends: Bool = false, remember: Bool = false) {
        ConversationLog.write("ROUTE", route)
        let text = parts.joined(separator: " ")
        if remember {
            history.append(user: entry.text, assistant: text, limit: settings.historyMessages)
            lastReplyAt = Date()
        }
        updateReply(entry.id) { $0 = text }
        skipFollowUp = ends
        speakOrFinish(parts)
    }

    /// Streams the model's reply, speaking it sentence by sentence through a fresh `ReplySession`.
    private func askModel(_ entry: TranscriptEntry, feelings: Bool) {
        let session = ReplySession(entryID: entry.id, filter: ModelTextFilter(settings: settings, feelingsOnly: feelings))
        self.session = session
        // Fixed text, not from the model, and kept out of its history. Spoken while the model thinks.
        if let greeting = stock.periodGreeting() {
            updateReply(entry.id) { $0 = greeting + " " }
            if settings.speakReplies { voice.speak([greeting]) }
        }
        session.prefix = entries.first { $0.id == entry.id }?.reply ?? ""
        scheduleFiller()
        services.noteModelUse()
        ConversationLog.write("ROUTE", "model")
        let model: any ChatModel = LocalLLMClient(model: settings.modelID, systemPrompt: PersonaPrompt.build(settings),
                                                  temperature: settings.temperature, maxTokens: settings.maxTokens)
        let user = JSON.object(["role": "user", "content": .string(entry.text)])
        let past = history.messages
        replyTask = Task { [weak self] in
            do {
                let result = try await model.respond(history: past, user: user) { text in
                    self?.receive(text, session: session)
                }
                guard !Task.isCancelled else { return }
                self?.complete(result, user: user, session: session)
            } catch {
                guard !Task.isCancelled else { return }
                self?.failReply(error, entryID: entry.id)
            }
        }
    }

    private func receive(_ delta: String, session: ReplySession) {
        guard session === self.session else { return }
        let (shown, sentences) = session.receive(delta)
        guard !shown.isEmpty else { return }
        updateReply(session.entryID) { $0 += shown }
        if settings.speakReplies { voice.speak(sentences) }
    }

    private func complete(_ result: LocalLLMClient.Result, user: JSON, session: ReplySession) {
        guard session === self.session else { return }
        llmStatus = nil
        history.append(user: user, reply: result.messages, limit: settings.historyMessages)
        lastReplyAt = Date()
        let ending = session.finish { stock.empathyLine() }
        ConversationLog.write("MODEL", ending.raw)
        ending.cut.forEach { ConversationLog.write("CUT", $0) }
        // The panel shows exactly what was spoken: stock prefix plus the filtered model sentences.
        updateReply(session.entryID) { $0 = ending.shown }
        lastReplyText = ending.shown
        speakOrFinish(ending.last)
    }

    private func failReply(_ error: Error, entryID: UUID) {
        ConversationLog.write("ERROR", error.localizedDescription)
        endSession()
        voice.stop()
        updateReply(entryID) { $0 = "Error: \(error.localizedDescription)" }
        llmStatus = error.localizedDescription
        goIdle()
    }

    private func endSession() {
        session?.cancel()
        session = nil
        replyTask?.cancel()
        replyTask = nil
    }

    /// Just "Emma" (or "Hey Emma") with nothing after it: greet at once, without Whisper or the model,
    /// then the follow-up window takes the actual request. Meanwhile Whisper checks the pre-roll in case a
    /// whole question was said before the wake word fired; if so, it is answered after the greeting.
    private func answerBareCall(_ samples: [Float]) {
        ConversationLog.write("ROUTE", "bare call (name only)")
        let entry = TranscriptEntry(text: "Emma", audioSeconds: Double(samples.count) / AudioCapture.sampleRate, transcribeSeconds: 0)
        entries.append(entry)
        phase = .thinking
        voice.prepare(settings, kokoroReady: services.kokoroReady)
        let parts = stock.greeting()
        updateReply(entry.id) { $0 = parts.joined(separator: " ") }
        if settings.speakReplies { voice.speak(parts) }
        replyTask = Task { [weak self] in
            guard let self else { return }
            let (text, _) = await self.transcriber.transcribe(samples)
            guard !Task.isCancelled else { return }
            self.replyTask = nil
            guard ReplyRouter.preRollHasRequest(text), let index = self.entries.firstIndex(where: { $0.id == entry.id }) else {
                return self.speakOrFinish([])
            }
            self.entries[index].text = text
            self.updateReply(entry.id) { $0 += " " }
            self.respond(to: self.entries[index])
        }
    }

    // MARK: - Speaking

    /// Speaks the last piece of a reply, then `finishReply` runs once speech ends.
    private func speakOrFinish(_ last: [String]) {
        guard settings.speakReplies else {
            finishReply()
            return
        }
        voice.speak(last)
        voice.finish()
    }

    /// Keeps the phase truthful: "Speaking" only while audio plays, "Thinking" while waiting on the model.
    /// Each stretch of silence before the answer starts gets a filler.
    private func playbackChanged(_ playing: Bool) {
        guard phase == .thinking || phase == .speaking else { return }
        if playing {
            phase = .speaking
        } else if replyTask != nil {
            phase = .thinking
            scheduleFiller()
        }
    }

    /// Says a rotating filler after `settings.fillerDelay` of silence while the model hasn't answered yet.
    private func scheduleFiller() {
        guard settings.speakReplies, settings.fillersEnabled, let session else { return }
        session.scheduleFiller(after: settings.fillerDelay, isWaiting: { [weak self] in
            self?.phase == .thinking && self?.replyTask != nil
        }, say: { [weak self] in
            guard let self else { return }
            let filler = self.stock.filler()
            ConversationLog.write("FILLER", filler)
            self.voice.say(filler)
        })
    }

    /// After a reply, listens for a follow-up without the wake word if that is turned on.
    private func finishReply() {
        replyTask = nil
        session = nil
        guard phase == .thinking || phase == .speaking else { return }
        guard settings.followUp > 0, !skipFollowUp else {
            skipFollowUp = false
            goIdle()
            return
        }
        phase = .listening
        isFollowUp = true
        let window = settings.followUp
        Task {
            // Let the speaker's tail die out so Emma doesn't hear itself.
            try? await Task.sleep(for: .milliseconds(300))
            guard phase == .listening, isFollowUp else { return }
            audio.beginCapture(includePreRoll: false, noSpeechTimeout: window)
        }
    }

    private func updateReply(_ entryID: UUID, _ change: (inout String) -> Void) {
        guard let index = entries.firstIndex(where: { $0.id == entryID }) else { return }
        change(&entries[index].reply)
    }
}
