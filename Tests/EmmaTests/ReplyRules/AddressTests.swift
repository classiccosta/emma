@testable import Emma
import XCTest

final class AddressTests: XCTestCase {
    func testSirOnlyInGreetingsAndGoodbyes() {
        let cases: [(String, String)] = [
            ("Alright, have a great rest of your day.", "Alright, have a great rest of your day, sir."),
            ("Want the longer version, sir?", "Want the longer version?"),
            ("Canberra, sir, not Sydney.", "Canberra, not Sydney."),
            ("Sir, it's 86 degrees.", "It's 86 degrees."),
            ("Yes sir, it's done.", "Yes, it's done."),
            ("What can I do for you, sir?", "What can I do for you, sir?"),
            ("Take care, sir.", "Take care, sir."),
            ("Bye!", "Bye, sir!"),
            ("Anytime", "Anytime, sir"),
            ("You’re welcome.", "You’re welcome, sir."),
            ("Do you want the recipe?", "Do you want the recipe?"),
            ("Is the vet able to see him today, sir?", "Is the vet able to see him today?"),
            ("Hello sir. ", "Hello sir. "),
            ("Hey, what’s on your mind today?", "Hey, what’s on your mind today, sir?"),
            ("I desire coffee.", "I desire coffee."),
        ]
        for (input, expected) in cases {
            XCTAssertEqual(Address.adjust(input), expected, input)
        }
    }

    func testDetailOffersAreRecognised() {
        for offer in ["Want the longer version?", "Want more detail?", "Want it?", "Would you like more details?",
                      "Want me to walk you through it?", "Should I elaborate?"] {
            XCTAssertTrue(ReplyHeuristics.isDetailOffer(offer), offer)
        }
        for other in ["Is the vet able to see him today?", "Want me to set a reminder?", "It has more details.", "Want it."] {
            XCTAssertFalse(ReplyHeuristics.isDetailOffer(other), other)
        }
    }

    func testPadding() {
        XCTAssertTrue(ReplyHeuristics.isPadding("Quick and easy—just like that."))
        XCTAssertTrue(ReplyHeuristics.isPadding("No need to wait—just hit that combo and it’s there."))
        XCTAssertTrue(ReplyHeuristics.isPadding("Honestly, it’s like nature’s version of a mood ring, if you think about it long enough."))
        XCTAssertTrue(ReplyHeuristics.isPadding("Oh, and it's got a name, not just a function."))
        XCTAssertTrue(ReplyHeuristics.isPadding("Like when you walk into a room and the door's gone."))
        XCTAssertTrue(ReplyHeuristics.isPadding("😅"))
        XCTAssertTrue(ReplyHeuristics.isPadding("Quietly."))
        XCTAssertTrue(ReplyHeuristics.isPadding("Seriously, just do it."))
        XCTAssertTrue(ReplyHeuristics.isPadding("That's valid too."))
        XCTAssertFalse(ReplyHeuristics.isPadding("Press Command plus N to open a new Finder window."))
        XCTAssertFalse(ReplyHeuristics.isPadding("Or, if you're in a hurry, use git reset --hard to discard the changes."))
        XCTAssertFalse(ReplyHeuristics.isPadding("The image saves to your Desktop automatically."))
        XCTAssertFalse(ReplyHeuristics.isPadding("That's it for the setup, now restart the app and log in again with your new password."))
    }

    func testModelTextFilterKeepsTheAnswerAndDropsPaddingAndOffers() {
        var filter = ModelTextFilter()
        XCTAssertEqual(filter.process(["Press Command plus N to open a new Finder window.", "Quick and easy—just like that."]),
                       ["Press Command plus N to open a new Finder window."])
        XCTAssertEqual(filter.process(["Want more detail?"]), [])
        XCTAssertEqual(filter.cut.count, 2)

        // A padding-like first sentence is the answer, so it stays.
        var first = ModelTextFilter()
        XCTAssertEqual(first.process(["That's it."]), ["That's it."])
    }

    func testFeelingsKeepOneAcknowledgementAndNoAdvice() {
        var filter = ModelTextFilter(feelingsOnly: true)
        XCTAssertEqual(filter.process(["I'm sorry that sounds tough.", "Maybe take a deep breath and walk around the block."]),
                       ["I'm sorry that sounds tough."])
        var advice = ModelTextFilter(feelingsOnly: true)
        XCTAssertEqual(advice.process(["Hmm, maybe try a walk outside?"]), [])
        XCTAssertTrue(SmallTalk.isFeeling("I had a really bad day"))
        XCTAssertTrue(SmallTalk.isFeeling("I am kind of sad. What can I do?"))
        XCTAssertFalse(SmallTalk.isFeeling("how do I take a screenshot"))
    }

    func testSirAtMostOnceInAGoodbye() {
        var addresser = Addresser()
        XCTAssertEqual(addresser.adjust("Anytime, sir."), "Anytime, sir.")
        XCTAssertEqual(addresser.adjust("Have a great rest of your day."), "Have a great rest of your day.")

        var other = Addresser()
        XCTAssertEqual(other.adjust("Anytime."), "Anytime, sir.")
        XCTAssertEqual(other.adjust("Have a good night, sir!"), "Have a good night!")
    }
}

final class CapabilityClaimTests: XCTestCase {
    func testClaimsAreCut() {
        for claim in ["Opened a new note titled groceries.", "Here’s what’s in the notes app: “Team meeting tomorrow at 10.”",
                      "I'll open Safari for you.", "Done, I set a reminder for 5pm.", "Your calendar shows two meetings.",
                      "I've added it to your calendar."] {
            XCTAssertTrue(ReplyHeuristics.isCapabilityClaim(claim), claim)
        }
        for honest in ["You can set a timer in the Clock app.", "I can't open apps yet.", "I can't see your calendar yet.", "Press Command plus N to open a new Finder window.",
                       "Canberra, not Sydney."] {
            XCTAssertFalse(ReplyHeuristics.isCapabilityClaim(honest), honest)
        }
    }

    func testFilterDropsTheClaimAndWhatFollows() {
        var filter = ModelTextFilter()
        XCTAssertEqual(filter.process(["Got it.", "Opened a new note titled groceries.", "What should I add first?"]), ["Got it."])
        XCTAssertTrue(filter.claimedCapability)
    }
}
