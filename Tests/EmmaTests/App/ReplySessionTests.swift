@testable import Emma
import XCTest

final class ReplySessionTests: XCTestCase {
    @MainActor
    func testStreamsSentencesAndKeepsThePrefix() {
        let session = ReplySession(entryID: UUID(), filter: ModelTextFilter())
        session.prefix = "Hello sir. Good evening. "
        XCTAssertEqual(session.receive("Press Command plus N").sentences, [])
        XCTAssertEqual(session.receive(" to open a window. Quick and easy—just like that.").sentences,
                       ["Press Command plus N to open a window."])
        XCTAssertTrue(session.modelSpoke)
        let ending = session.finish { "unused" }
        XCTAssertEqual(ending.last, [])
        XCTAssertEqual(ending.shown, "Hello sir. Good evening. Press Command plus N to open a window.")
        XCTAssertEqual(ending.cut, ["padding: Quick and easy—just like that."])
    }

    @MainActor
    func testMadeUpAppActionGetsTheFallback() {
        let session = ReplySession(entryID: UUID(), filter: ModelTextFilter())
        _ = session.receive("Got it. Opened a new note titled groceries.")
        let ending = session.finish { "unused" }
        XCTAssertEqual(ending.last, [Phrases.cantDoYet])
        XCTAssertEqual(ending.shown, "Got it. " + Phrases.cantDoYet)
    }

    @MainActor
    func testFeelingAllAdviceGetsAnEmpathyLine() {
        let session = ReplySession(entryID: UUID(), filter: ModelTextFilter(feelingsOnly: true))
        _ = session.receive("Maybe try a walk outside.")
        XCTAssertEqual(session.finish { "That sounds tough." }.last, ["That sounds tough."])
    }

    @MainActor
    func testBracketAsidesAreDroppedFromTheShownText() {
        let session = ReplySession(entryID: UUID(), filter: ModelTextFilter())
        XCTAssertEqual(session.receive("Lisbon. (Honestly, it is a lovely city.) ").shown, "Lisbon.  ")
    }

    @MainActor
    func testFillerFiresOnlyWhileWaiting() async {
        let session = ReplySession(entryID: UUID(), filter: ModelTextFilter())
        var said = 0
        session.scheduleFiller(after: 0.05, isWaiting: { true }, say: { said += 1 })
        try? await Task.sleep(for: .milliseconds(150))
        XCTAssertEqual(said, 1)

        // Once the model has spoken, no filler.
        let answered = ReplySession(entryID: UUID(), filter: ModelTextFilter())
        _ = answered.receive("Lisbon. ")
        answered.scheduleFiller(after: 0.05, isWaiting: { true }, say: { said += 1 })
        try? await Task.sleep(for: .milliseconds(150))
        XCTAssertEqual(said, 1)
    }
}
