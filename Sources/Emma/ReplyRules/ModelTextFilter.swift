import Foundation

/// Everything applied to the model's sentences for one reply, in order: drop "Want more detail?" offers,
/// drop padding after the first sentence (the first is the answer), and apply the "sir" rule.
struct ModelTextFilter {
    /// The user shared a feeling: keep one acknowledging sentence and no advice, since Emma doesn't give emotional advice.
    var feelingsOnly = false
    private var addresser: Addresser
    private let dropDetailOffers: Bool
    private let dropPadding: Bool
    private var kept = 0
    /// Sentences removed so far, with the reason, for the conversation log.
    private(set) var cut: [String] = []
    /// The model claimed it used an app; the reply gets "I can't do that yet." instead.
    private(set) var claimedCapability = false

    init(feelingsOnly: Bool = false, addresser: Addresser = Addresser(), dropDetailOffers: Bool = true, dropPadding: Bool = true) {
        self.feelingsOnly = feelingsOnly
        self.addresser = addresser
        self.dropDetailOffers = dropDetailOffers
        self.dropPadding = dropPadding
    }

    mutating func process(_ sentences: [String]) -> [String] {
        sentences.compactMap { sentence in
            if claimedCapability || ReplyHeuristics.isCapabilityClaim(sentence) {
                claimedCapability = true
                cut.append("made-up app action: \(sentence)")
                return nil
            }
            if dropDetailOffers, ReplyHeuristics.isDetailOffer(sentence) {
                cut.append("detail offer: \(sentence)")
                return nil
            }
            if dropPadding, kept > 0, ReplyHeuristics.isPadding(sentence) {
                cut.append("padding: \(sentence)")
                return nil
            }
            if feelingsOnly, kept > 0 || ReplyHeuristics.isAdvice(sentence) {
                cut.append("emotional advice: \(sentence)")
                return nil
            }
            kept += 1
            return addresser.adjust(sentence)
        }
    }
}

extension ModelTextFilter {
    /// The per-reply filter configured from the conversation settings.
    init(settings: Settings, feelingsOnly: Bool) {
        self.init(feelingsOnly: feelingsOnly,
                  addresser: Addresser(word: settings.addressWord, inGreetings: settings.addressInGreetings,
                                       inGoodbyes: settings.addressInGoodbyes),
                  dropDetailOffers: !settings.offerMoreDetail, dropPadding: settings.replyLength != .shortParagraph)
    }
}
