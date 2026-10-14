@testable import Emma
import XCTest

final class FillersTests: XCTestCase {
    func testCyclesThroughEveryPhraseBeforeRepeating() {
        for pool in [Phrases.fillers, Phrases.declineAcks, Phrases.greetReplies, Phrases.closings] {
            var rotation = PhraseRotation(pool: pool)
            let first = (0..<pool.count).map { _ in rotation.next() }
            XCTAssertEqual(Set(first), Set(pool))
        }
    }

    func testSirOnlyInGreetingsQuestionsAndEndings() {
        for phrase in Phrases.greetReplies + Phrases.declineAcks + Phrases.closings {
            XCTAssertTrue(phrase.lowercased().contains("sir"), phrase)
        }
        for phrase in Phrases.fillers {
            XCTAssertFalse(phrase.lowercased().contains("sir"), phrase)
        }
    }

    func testNeverRepeatsAcrossReshuffle() {
        // The same order every time would repeat the last phrase first; the rotation must avoid it.
        var rotation = PhraseRotation(pool: ["a", "b", "c"]) { $0.reversed() }
        let said = (0..<9).map { _ in rotation.next() }
        for (previous, next) in zip(said, said.dropFirst()) {
            XCTAssertNotEqual(previous, next, "\(said)")
        }
    }
}

final class DeclineTests: XCTestCase {
    func testOffers() {
        XCTAssertTrue(Decline.isOffer("Done. Want me to set a reminder?"))
        XCTAssertTrue(Decline.isOffer("Would you like the recipe?"))
        XCTAssertTrue(Decline.isOffer("Yep. I meant the bouquet details. Want it?"))
        XCTAssertTrue(Decline.isOffer("Want the recipe?"))
        XCTAssertTrue(Decline.isOffer(Phrases.anythingElse))
        XCTAssertTrue(Decline.isDecline("Nothing, thanks."))
        XCTAssertTrue(Decline.isDecline("No, nothing else."))
        XCTAssertTrue(Decline.isOffer("Hello sir. Good morning. Lisbon. Should I look up flights?"))
        XCTAssertFalse(Decline.isOffer("Oh no, I'm sorry. Is the vet able to see him today?"))
        XCTAssertFalse(Decline.isOffer("Lisbon."))
        XCTAssertFalse(Decline.isOffer("Want me to check? Actually, never mind, it's Lisbon."))
        XCTAssertFalse(Decline.isOffer(""))
    }

    func testDeclines() {
        for utterance in ["no", "No thanks.", "nah I'm good", "not now", "That's all.", "Nope, that's fine", "no thank you emma"] {
            XCTAssertTrue(Decline.isDecline(utterance), utterance)
        }
    }

    func testNotDeclines() {
        for utterance in ["no, what's the weather", "yes please", "no idea what you mean, explain",
                          "sure", "", "no I want you to book it for tomorrow at nine"] {
            XCTAssertFalse(Decline.isDecline(utterance), utterance)
        }
    }
}
