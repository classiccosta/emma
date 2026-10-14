@testable import Emma
import XCTest

final class CleanTests: XCTestCase {
    private func clean(_ raw: String) -> String { Transcriber.clean(raw) }

    func testStripsWhisperTags() {
        XCTAssertEqual(clean("[BLANK_AUDIO]"), "")
        XCTAssertEqual(clean("(upbeat music)"), "")
        XCTAssertEqual(clean("[Music] set a timer [Music]"), "set a timer")
    }

    func testStripsLeadingWakeWord() {
        XCTAssertEqual(clean("Emma, what time is it?"), "what time is it?")
        XCTAssertEqual(clean("  emma what time is it?"), "what time is it?")
        XCTAssertEqual(clean("EMMA! Stop."), "Stop.")
        XCTAssertEqual(clean("Hey, Emma. What time is it?"), "What time is it?")
        XCTAssertEqual(clean("hey emma turn it up"), "turn it up")
    }

    func testStripsWakeWordExposedByTagRemoval() {
        XCTAssertEqual(clean("[Music] Emma, set a timer"), "set a timer")
    }

    func testKeepsWakeWordAfterTheStart() {
        XCTAssertEqual(clean("Tell Emma hi"), "Tell Emma hi")
        XCTAssertEqual(clean("Emmanuel called"), "Emmanuel called")
        XCTAssertEqual(clean("Emma, ask Emma"), "ask Emma")
    }

    func testWakeWordAloneIsEmpty() {
        XCTAssertEqual(clean("Emma."), "")
        XCTAssertEqual(clean("Hey Emma?"), "")
    }

    /// Current behaviour: any parenthesised text is treated as a Whisper tag and removed,
    /// including words the user actually said.
    func testRemovesAllParenthesisedText() {
        XCTAssertEqual(clean("call mom (urgent)"), "call mom")
    }
}
