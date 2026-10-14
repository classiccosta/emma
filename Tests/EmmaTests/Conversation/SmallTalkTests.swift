@testable import Emma
import XCTest

final class SmallTalkTests: XCTestCase {
    func testGreetings() {
        // The wake word is stripped first, so "Emma, how are you?" arrives as "how are you?".
        for text in ["Hi.", "Hello Emma", "how are you?", "How's it going?", "good afternoon", "hey there", "Hello, how are you?", "Morning!", "Hey Emma, how are you doing?"] {
            XCTAssertTrue(SmallTalk.isGreeting(text), text)
        }
    }

    func testNotGreetings() {
        for text in ["how are you getting there", "hi, what's the weather", "hello, set a timer", "Lisbon", "", "hey can you help me with git",
                     "good afternoon, remind me to call mum"] {
            XCTAssertFalse(SmallTalk.isGreeting(text), text)
        }
    }

    func testClosings() {
        for text in ["Thanks!", "thank you Emma", "That's all.", "bye", "Perfect, thanks.", "that's all, thanks", "thank you so much",
                     "okay that's it, thanks", "Alright, that's all for today.", "great, thanks a lot", "I'm done for now", "all good, thanks"] {
            XCTAssertTrue(SmallTalk.isClosing(text), text)
        }
        for text in ["thanks, now what about tomorrow", "okay what's next", "thanks, what about tomorrow", "thank you for explaining, now tell me more", "bye the way what's up", ""] {
            XCTAssertFalse(SmallTalk.isClosing(text), text)
        }
    }

    func testInconclusive() {
        for text in ["Um...", "Oh nothing.", "never mind", "I don't know", "Hmm."] {
            XCTAssertTrue(SmallTalk.isInconclusive(text), text)
        }
        for text in ["um, what's the time", "nothing works on my laptop", "I don't know how to undo a commit"] {
            XCTAssertFalse(SmallTalk.isInconclusive(text), text)
        }
    }

    func testHallucinations() {
        XCTAssertTrue(SmallTalk.isHallucination("Thank you."))
        XCTAssertTrue(SmallTalk.isHallucination(" you"))
        XCTAssertTrue(SmallTalk.isHallucination("Thanks for watching!"))
        XCTAssertFalse(SmallTalk.isHallucination("thank you, what's next"))
        XCTAssertFalse(SmallTalk.isHallucination("what time is it"))
    }
}
