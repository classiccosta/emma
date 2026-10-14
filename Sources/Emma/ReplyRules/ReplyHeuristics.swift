import Foundation

/// Recognisers for model sentences Emma shouldn't say: offers of more detail, padding after the answer,
/// emotional advice, and claims of having used an app. Used by `ModelTextFilter`.
enum ReplyHeuristics {
    /// "Want the longer version?", "Want more detail?", "Want it?": the user doesn't want these offered.
    private static let detailOffer = [
        #"\b(longer version|more detail|more details|more info|more information|full details|the details)\b"#,
        #"\b(go (deeper|further|into more)|elaborate|expand on|break it down|walk you through)\b"#,
        #"^(want|wanna|would you like|do you want|need) (it|that|them|more|those)\??$"#,
    ].joined(separator: "|")

    /// A question offering more detail. Dropped from model replies: the user asks when they want more.
    static func isDetailOffer(_ sentence: String) -> Bool {
        let trimmed = sentence.trimmingCharacters(in: .whitespaces)
        return trimmed.hasSuffix("?") && TextPattern.matches(trimmed, detailOffer)
    }

    private static let padding = [
        "quick and easy", "just like that", "no need to wait", "that's it", "there you go", "easy as that",
        "simple as that", "you've got this", "you're all set", "done and done", "easy peasy", "and voilà", "and voila",
        "nothing to it", "piece of cake",
    ]

    /// Openers of the jokey tails the model adds after an answer: "Honestly, it's like…", "Oh, and…".
    private static let asideOpeners = [
        "honestly", "oh, and", "oh and", "also,", "though", "like when", "like how", "it's like", "kind of like", "kinda like",
        "fun fact", "bonus", "p.s", "ps ", "spoiler", "quick tip", "side note", "just saying", "no pressure", "still got",
        "seriously", "trust me", "that's valid", "believe me", "for real",
    ]

    /// A line that adds nothing after the answer: a short reassurance ("Quick and easy—just like that."),
    /// a jokey aside opener ("Honestly, it's like…"), or nothing but emoji.
    static func isPadding(_ sentence: String) -> Bool {
        let text = sentence.lowercased().replacingOccurrences(of: "\u{2019}", with: "'").trimmingCharacters(in: .whitespaces)
        if !text.contains(where: { $0.isLetter || $0.isNumber }) { return true }
        if asideOpeners.contains(where: { text.hasPrefix($0) }) { return true }
        let words = text.split { $0.isWhitespace || $0 == "—" || $0 == "-" }
        // "Quietly." / "Promise." after an answer: too short to carry information.
        if words.count <= 2 { return true }
        return words.count <= 12 && padding.contains { text.contains($0) }
    }

    private static let advice = #"\b(maybe|try|trying|how about|you could|you should|you might|consider|why not|have you tried|take a|go for a|make sure)\b"#

    private static let things = #"(note|notes|reminder|reminders|calendar|event|meeting|email|emails|message|music|song|playlist|app|file|files|folder|timer|alarm|safari|finder|browser|tab|screen)"#
    private static let claims = [
        // "Opened a new note", "Done, I set a reminder", "I've added it to your calendar"; not "You can set a timer in the app".
        #"^((got it|done|okay|ok|sure|alright)[,.!]?\s*)?(i('ve| have)?\s+)?(just\s+)?(opened|created|added|set|scheduled|sent|played|started|saved|deleted|checked|launched|made|wrote)\b.*\b"#
            + things + #"\b"#,
        #"\bi('ll| will| can| am going to|'m going to) (open|access|check|read|create|add|set|play|send|launch|pull up|look in)\b.*\b"#
            + things + #"\b"#,
        #"\bhere'?s what'?s (in|on)\b"#,
        #"\byour (notes|calendar|reminders|emails?|files|downloads) (say|show|has|have|contain)"#,
    ].joined(separator: "|")

    /// "Opened a new note.", "Here's what's in your notes:": Emma claiming she used an app. She can't yet,
    /// so these are made up.
    static func isCapabilityClaim(_ sentence: String) -> Bool {
        TextPattern.matches(sentence, claims) && !TextPattern.matches(sentence, #"\b(can'?t|cannot|can not|unable|not able|don'?t have access)\b"#)
    }

    /// A suggestion, like "Maybe take a deep breath." Dropped when the user is sharing a feeling.
    static func isAdvice(_ sentence: String) -> Bool {
        TextPattern.matches(sentence, advice)
    }
}
