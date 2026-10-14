import Foundation

/// Spots "Want me to …?" offers in Emma's replies and short "no thanks" answers to them,
/// which get a plain "Yes sir." instead of a model reply.
enum Decline {
    private static let offerPhrases = [
        "would you like", "want me to", "shall i", "should i", "do you want",
        "can i help", "need me to", "would it help", "anything else",
    ]
    private static let declines = [
        "no", "nope", "nah", "no thanks", "no thank you", "not now", "not right now", "maybe later",
        "i'm good", "im good", "i'm fine", "im fine", "that's all", "thats all", "that's fine", "thats fine",
        "never mind", "nevermind", "don't", "dont", "skip it", "nothing", "nothing else", "oh nothing", "not really",
    ].map { $0.split(separator: " ").map(String.init) }
    /// Words that turn a "no" into a new request, as in "no, what's the weather".
    private static let requestWords: Set = [
        "what", "what's", "whats", "how", "why", "when", "where", "who", "which",
        "can", "could", "tell", "explain", "instead",
    ]

    /// True when the reply's last sentence is a question offering to do something.
    static func isOffer(_ reply: String) -> Bool {
        let sentences = reply.split(whereSeparator: { ".!?".contains($0) && $0 != "?" })
        guard let last = sentences.last?.trimmingCharacters(in: .whitespaces), last.hasSuffix("?") else { return false }
        let question = last.lowercased()
        // The model's usual offer is a clipped "Want it?" / "Want me to…?".
        return question.hasPrefix("want ") || question.hasPrefix("wanna ") || offerPhrases.contains { question.contains($0) }
    }

    /// True for a short refusal with no new request attached.
    static func isDecline(_ utterance: String) -> Bool {
        let words = utterance.lowercased()
            .replacingOccurrences(of: "\u{2019}", with: "'")
            .split { !$0.isLetter && $0 != "'" }
            .map(String.init)
        guard !words.isEmpty, words.count <= 6, !words.contains(where: requestWords.contains) else { return false }
        return declines.contains { words.starts(with: $0) }
    }
}
