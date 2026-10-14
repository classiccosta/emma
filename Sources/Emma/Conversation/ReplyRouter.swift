import Foundation

/// Decides what answers an utterance, in one place and in priority order. Pure, so the order is unit-tested.
enum ReplyRouter {
    enum Route: Equatable {
        /// The previous reply offered something and this turns it down: "Very well, sir."
        case declinedOffer
        /// "hi", "hello Emma", "how are you": greet back without the model.
        case greeting
        /// "thanks", "that's all": close the conversation.
        case closing
        /// "um", "oh nothing": ask "Is there anything else I can do for you, sir?"
        case inconclusive
        /// Everything else goes to the model. `feelings` turns on the no-emotional-advice filter.
        case model(feelings: Bool)
    }

    /// Whether a transcript should be answered at all. Whisper invents "Thank you." and the like from noise:
    /// those count only as a real wrap-up right after one of Emma's replies.
    static func shouldAnswer(_ text: String, ignoreNoise: Bool, recentReply: Bool) -> Bool {
        guard !text.isEmpty else { return false }
        let noise = ignoreNoise && SmallTalk.isHallucination(text)
        return !noise || (recentReply && SmallTalk.isClosing(text))
    }

    /// The route for `text`, given Emma's previous reply. Declining an offer comes first, since "no thanks"
    /// would otherwise read as a closing; the butler check comes last among the stock replies.
    static func route(_ text: String, lastReply: String, butlerCheck: Bool) -> Route {
        if Decline.isOffer(lastReply), Decline.isDecline(text) { return .declinedOffer }
        if SmallTalk.isGreeting(text) { return .greeting }
        if SmallTalk.isClosing(text) { return .closing }
        if butlerCheck, SmallTalk.isInconclusive(text) { return .inconclusive }
        return .model(feelings: SmallTalk.isFeeling(text))
    }

    /// For a bare "Emma": true when the pre-roll audio also held a real request worth answering.
    static func preRollHasRequest(_ text: String) -> Bool {
        !text.isEmpty && !SmallTalk.isGreeting(text) && !SmallTalk.isHallucination(text)
    }
}
