import Foundation

/// The streaming state of one model reply: aside filtering, sentence splitting, the model-text rules,
/// and the "One sec." filler timing. A fresh session is made for each reply and dropped afterwards,
/// so nothing has to be reset by hand when a reply ends, fails or is stopped.
@MainActor
final class ReplySession {
    struct Ending {
        /// Sentences still to speak, including any fallback line.
        let last: [String]
        /// What the panel shows: the stock prefix plus every kept model sentence.
        let shown: String
        /// The model's text before the reply rules, for the conversation log.
        let raw: String
        /// Sentences the rules removed, with reasons.
        let cut: [String]
    }

    let entryID: UUID
    /// Stock text shown before the model's sentences, such as the period greeting.
    var prefix = ""
    /// The model's answer has started speaking, so no more fillers.
    private(set) var modelSpoke = false

    private var splitter = SentenceSplitter()
    private var asides = AsideFilter()
    private var filter: ModelTextFilter
    private var sentences: [String] = []
    private var rawText = ""
    private var fillersSaid = 0
    private var lastFillerAt: Date?
    private var fillerTask: Task<Void, Never>?

    init(entryID: UUID, filter: ModelTextFilter) {
        self.entryID = entryID
        self.filter = filter
    }

    /// A streamed delta: the text to show now, and the sentences it completed, after the reply rules.
    func receive(_ delta: String) -> (shown: String, sentences: [String]) {
        let text = asides.feed(delta)
        guard !text.isEmpty else { return ("", []) }
        rawText += text
        let done = filter.process(splitter.feed(text))
        sentences += done
        if !done.isEmpty {
            modelSpoke = true
            fillerTask?.cancel()
        }
        return (text, done)
    }

    /// The stream ended. A made-up app action gets "I can't do that yet."; a reply to a feeling that was
    /// all advice gets an empathy line instead.
    func finish(empathy: () -> String) -> Ending {
        cancel()
        modelSpoke = true
        let tail = asides.flush()
        rawText += tail
        var last = filter.process(splitter.feed(tail) + [splitter.flush()].compactMap { $0 })
        if filter.claimedCapability {
            last.append(Phrases.cantDoYet)
        } else if filter.feelingsOnly, sentences.isEmpty, last.isEmpty {
            last = [empathy()]
        }
        sentences += last
        return Ending(last: last, shown: prefix + sentences.joined(separator: " "), raw: prefix + rawText, cut: filter.cut)
    }

    /// Calls `say` after `delay` seconds of silence while the model hasn't answered and `isWaiting()` still
    /// holds: at most two fillers per reply, at least 4 s apart.
    func scheduleFiller(after delay: Double, isWaiting: @escaping @MainActor () -> Bool, say: @escaping @MainActor () -> Void) {
        fillerTask?.cancel()
        guard !modelSpoke, fillersSaid < 2 else { return }
        let sinceLast = lastFillerAt.map { Date().timeIntervalSince($0) } ?? .infinity
        let wait = Duration.seconds(max(delay, 4 - sinceLast))
        fillerTask = Task { [weak self] in
            try? await Task.sleep(for: wait)
            guard !Task.isCancelled, let self, !self.modelSpoke, isWaiting() else { return }
            self.fillersSaid += 1
            self.lastFillerAt = Date()
            say()
        }
    }

    func cancel() {
        fillerTask?.cancel()
    }
}
