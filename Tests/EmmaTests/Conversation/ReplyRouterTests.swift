@testable import Emma
import XCTest

final class ReplyRouterTests: XCTestCase {
    private func route(_ text: String, after lastReply: String = "", butler: Bool = true) -> ReplyRouter.Route {
        ReplyRouter.route(text, lastReply: lastReply, butlerCheck: butler)
    }

    func testPriorityOrder() {
        // "no thanks" after an offer is a declined offer, not a closing.
        XCTAssertEqual(route("no thanks", after: "Want me to set a reminder?"), .declinedOffer)
        XCTAssertEqual(route("no thanks"), .model(feelings: false))
        XCTAssertEqual(route("hello Emma"), .greeting)
        XCTAssertEqual(route("thanks, that's all"), .closing)
        XCTAssertEqual(route("um"), .inconclusive)
        XCTAssertEqual(route("um", butler: false), .model(feelings: false))
        XCTAssertEqual(route("I had a really bad day"), .model(feelings: true))
        XCTAssertEqual(route("what's the capital of France"), .model(feelings: false))
    }

    func testNothingAfterTheButlerQuestionIsADecline() {
        XCTAssertEqual(route("nothing", after: Phrases.anythingElse), .declinedOffer)
        XCTAssertEqual(route("nothing"), .inconclusive)
    }

    func testNoiseFilter() {
        XCTAssertFalse(ReplyRouter.shouldAnswer("", ignoreNoise: true, recentReply: true))
        XCTAssertFalse(ReplyRouter.shouldAnswer("Thank you.", ignoreNoise: true, recentReply: false))
        XCTAssertTrue(ReplyRouter.shouldAnswer("Thank you.", ignoreNoise: true, recentReply: true))
        XCTAssertTrue(ReplyRouter.shouldAnswer("Thank you.", ignoreNoise: false, recentReply: false))
        XCTAssertTrue(ReplyRouter.shouldAnswer("what time is it", ignoreNoise: true, recentReply: false))
    }

    func testPreRoll() {
        XCTAssertTrue(ReplyRouter.preRollHasRequest("what time is it"))
        XCTAssertFalse(ReplyRouter.preRollHasRequest(""))
        XCTAssertFalse(ReplyRouter.preRollHasRequest("hello"))
        XCTAssertFalse(ReplyRouter.preRollHasRequest("Thank you."))
    }
}

final class ChatHistoryTests: XCTestCase {
    func testTrimsWholeTurnsFromTheFront() {
        var history = ChatHistory()
        for turn in 1...3 {
            history.append(user: "question \(turn)", assistant: "answer \(turn)", limit: 4)
        }
        XCTAssertEqual(history.messages.count, 4)
        XCTAssertEqual(history.messages.first?["content"], .string("question 2"))
        XCTAssertEqual(history.messages.first?["role"], .string("user"))
    }

    func testToolTurnsAreDroppedWithTheirUserMessage() {
        var history = ChatHistory()
        let user = JSON.object(["role": "user", "content": "q1"])
        let reply: [JSON] = [.object(["role": "assistant", "content": ""]), .object(["role": "tool", "content": "r"]),
                             .object(["role": "assistant", "content": "a1"])]
        history.append(user: user, reply: reply, limit: 10)
        history.append(user: "q2", assistant: "a2", limit: 3)
        XCTAssertEqual(history.messages.map { $0["content"]?.string }, ["q2", "a2"])
    }
}
