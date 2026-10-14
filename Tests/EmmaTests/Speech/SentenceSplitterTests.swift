@testable import Emma
import XCTest

final class SentenceSplitterTests: XCTestCase {
    private func split(_ deltas: [String]) -> [String] {
        var splitter = SentenceSplitter()
        var sentences = deltas.flatMap { splitter.feed($0) }
        if let rest = splitter.flush() { sentences.append(rest) }
        return sentences
    }

    func testSplitsOnTerminators() {
        XCTAssertEqual(split(["It is sunny. Is it warm? Yes! Bring water"]),
                       ["It is sunny.", "Is it warm?", "Yes!", "Bring water"])
    }

    func testWaitsForTheNextCharacter() {
        var splitter = SentenceSplitter()
        XCTAssertEqual(splitter.feed("Paris is the capital."), [])
        XCTAssertEqual(splitter.feed(" It has"), ["Paris is the capital."])
        XCTAssertEqual(splitter.flush(), "It has")
    }

    func testSentencesAcrossDeltas() {
        XCTAssertEqual(split(["The ca", "pital is Par", "is. Pop", "ulation is 2.1 million."]),
                       ["The capital is Paris.", "Population is 2.1 million."])
    }

    func testKeepsAbbreviationsAndInitials() {
        XCTAssertEqual(split(["Dr. Smith met J. Doe, e.g. at noon. Done."]),
                       ["Dr. Smith met J. Doe, e.g. at noon.", "Done."])
    }

    func testClosingQuotesAndNewlines() {
        XCTAssertEqual(split(["He said \"hi.\" Then left\nNew line"]),
                       ["He said \"hi.\"", "Then left", "New line"])
    }

    func testFlushOfEmptyBufferIsNil() {
        var splitter = SentenceSplitter()
        XCTAssertNil(splitter.flush())
        _ = splitter.feed("Done. ")
        XCTAssertNil(splitter.flush())
    }
}
