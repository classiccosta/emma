import Foundation

/// Stock phrases Emma says without asking the model. Pre-synthesized, so they play instantly.
/// "sir" appears only in greetings, questions and endings, never in fillers.
enum Phrases {
    /// Said when an answer is slow to start, so silence doesn't feel like she stopped listening.
    static let fillers = [
        "Give me a moment to check.",
        "Let me check.",
        "One sec.",
        "Hmm, let me see.",
        "Bear with me a moment.",
        "Let me think about that.",
        "Checking now.",
        "Hang on a sec.",
    ]

    /// Said when the user turns down one of Emma's offers.
    static let declineAcks = [
        "Yes sir.",
        "Of course, sir.",
        "Very well, sir.",
        "Understood, sir.",
        "No problem, sir.",
        "Alright, sir.",
        "Sure thing, sir.",
    ]

    /// Said after a bare greeting like "Hi Emma", inviting the actual request.
    static let greetReplies = [
        "What can I do for you, sir?",
        "How can I help, sir?",
        "What do you need, sir?",
        "I'm here, sir. What's up?",
        "Yes sir?",
    ]

    /// Said when the user wraps up ("thanks", "that's all", "bye"); the conversation ends there.
    static let closings = [
        "Anytime, sir.",
        "You're welcome, sir.",
        "Happy to help, sir.",
        "No problem, sir.",
        "Glad I could help, sir.",
    ]

    /// Asked, butler-style, when the user's answer is inconclusive ("um", "oh nothing", "never mind").
    static let anythingElse = "Is there anything else I can do for you, sir?"

    /// Used when every sentence of the model's reply to a feeling was advice and got cut.
    static let empathy = ["I'm sorry, that sounds tough.", "That sounds like a lot.", "I'm sorry to hear that."]

    /// Said instead of a reply in which the model pretended to use an app.
    static let cantDoYet = "I can't do that yet."

    static let all = fillers + declineAcks + greetReplies + closings + empathy + [anythingElse]
}
