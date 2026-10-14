import Foundation

/// Utterances the app answers without the model.
enum SmallTalk {
    private static let greetings = [
        "hi", "hello", "hey", "hiya", "yo", "howdy", "morning", "afternoon", "evening",
        "good morning", "good afternoon", "good evening", "hey there", "hi there", "hello there",
        "how are you", "how's it going", "hows it going", "how are things",
    ].map { $0.split(separator: " ").map(String.init) }
    /// Polite extras that still leave it a pure greeting.
    private static let fillerWords: Set = ["emma", "there", "how", "are", "you", "doing", "sir", "again", "it's", "me"]
    private static let closings = [
        "thanks", "thank you", "cheers", "that's all", "thats all", "that's it", "thats it",
        "bye", "goodbye", "bye bye", "see you", "see ya", "thanks a lot", "i'm done", "im done", "all good",
    ].map { $0.split(separator: " ").map(String.init) }
    /// Things Whisper writes for silence or noise.
    private static let hallucinations: Set = [
        "thank you", "thanks", "thanks for watching", "thank you for watching", "you", "bye", "bye bye", "okay", "ok",
    ]

    private static func words(_ text: String) -> [String] {
        text.lowercased()
            .replacingOccurrences(of: "\u{2019}", with: "'")
            .split { !$0.isLetter && $0 != "'" }
            .map(String.init)
    }

    /// "hi", "hello Emma", "good afternoon", "hello, how are you": a greeting with no request in it.
    static func isGreeting(_ utterance: String) -> Bool {
        let words = words(utterance)
        guard !words.isEmpty, words.count <= 6,
              let greeting = greetings.filter({ words.starts(with: $0) }).max(by: { $0.count < $1.count }) else { return false }
        return words.dropFirst(greeting.count).allSatisfy(fillerWords.contains)
    }

    /// Words that may lead a wrap-up: "okay, that's all", "great, thanks".
    private static let closingLeads: Set = ["okay", "ok", "alright", "great", "perfect", "cool", "awesome", "nice", "right"]
    /// Words that may follow it without making it a new request.
    private static let closingExtras: Set = [
        "emma", "sir", "thanks", "thank", "you", "so", "much", "a", "lot", "then", "for", "today", "now", "that's", "all",
    ]

    /// "thanks", "okay that's all for today", "bye Emma": wrapping up, with no new request.
    static func isClosing(_ utterance: String) -> Bool {
        var words = words(utterance)
        while let first = words.first, closingLeads.contains(first) { words.removeFirst() }
        guard !words.isEmpty, words.count <= 6,
              let closing = closings.filter({ words.starts(with: $0) }).max(by: { $0.count < $1.count }) else { return false }
        return words.dropFirst(closing.count).allSatisfy(closingExtras.contains)
    }

    private static let inconclusive: Set = [
        "um", "uh", "umm", "uhm", "hmm", "hm", "er", "erm", "nothing", "oh nothing", "nah nothing", "never mind", "nevermind",
        "forget it", "no worries", "it's fine", "its fine", "i don't know", "i dont know", "dunno", "not sure", "whatever",
        "oh", "well", "so", "anyway", "um nothing", "uh nothing",
    ]

    /// "um", "oh nothing", "never mind": an answer that doesn't ask for anything. Emma checks, butler-style,
    /// whether there's anything else instead of guessing what the user meant.
    static func isInconclusive(_ utterance: String) -> Bool {
        inconclusive.contains(words(utterance).joined(separator: " "))
    }

    private static let feeling = #"\b(i'?m|i am|i feel|i'?ve been|feeling|i had)\b.*\b("#
        + "sad|down|low|stressed|stressing|tired|exhausted|anxious|nervous|depressed|upset|lonely|bored|unmotivated|"
        + "overwhelmed|angry|frustrated|worried|scared|bad day|rough day|terrible day|awful day|hurt"
        + #")\b"#

    /// "I'm kind of sad", "I had a really bad day": the user is sharing a feeling.
    static func isFeeling(_ utterance: String) -> Bool {
        utterance.lowercased().replacingOccurrences(of: "\u{2019}", with: "'")
            .range(of: feeling, options: .regularExpression) != nil
    }

    /// True when the whole transcript is a phrase Whisper typically invents from silence.
    static func isHallucination(_ transcript: String) -> Bool {
        hallucinations.contains(words(transcript).joined(separator: " "))
    }
}
