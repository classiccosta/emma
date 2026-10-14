@testable import Emma
import XCTest

final class SpeechTextTests: XCTestCase {
    func testCleansSymbolsAndMarkup() {
        let cases: [(String, String)] = [
            ("Run `git status` first.", "Run git status first."),
            ("This is **really** _important_.", "This is really important."),
            ("- Buy milk", "Buy milk"),
            ("See https://example.com/docs for more.", "See the link for more."),
            ("Fruit, e.g. apples.", "Fruit, for example apples."),
            ("Tabs i.e. spaces.", "Tabs that is spaces."),
            ("Mac vs. PC.", "Mac versus PC."),
            ("Eggs, milk, etc.", "Eggs, milk, and so on"),
            ("Salt & pepper.", "Salt and pepper."),
            ("Down 5% today.", "Down 5 percent today."),
            ("It's 86°F outside.", "It's 86 degrees Fahrenheit outside."),
            ("About 30 °C.", "About 30 degrees Celsius."),
            ("Takes ~5 minutes.", "Takes about 5 minutes."),
            ("30 × 9/5 + 32 = 86.", "30 times 9/5 plus 32 equals 86."),
            ("Tea/coffee?", "Tea or coffee?"),
            ("Nice work 🎉!", "Nice work !"),
            ("snake_case stays.", "snake_case stays."),
        ]
        for (input, expected) in cases {
            XCTAssertEqual(SpeechText.clean(input), expected, input)
        }
    }

    func testSymbolOnlySentenceBecomesEmpty() {
        XCTAssertEqual(SpeechText.clean("😏"), "")
        XCTAssertEqual(SpeechText.clean("  **  "), "")
    }
}

final class AsideFilterTests: XCTestCase {
    private func filter(_ deltas: [String]) -> String {
        var filter = AsideFilter()
        return deltas.map { filter.feed($0) }.joined() + filter.flush()
    }

    func testDropsLongAsidesAcrossDeltas() {
        XCTAssertEqual(filter(["Lisbon. (Honestly, it's a ", "lovely city.) Anything else?"]),
                       "Lisbon.  Anything else?")
    }

    func testKeepsShortBracketContent() {
        XCTAssertEqual(filter(["It's (30 × 9/5) + 32 = 86."]), "It's 30 × 9/5 + 32 = 86.")
        XCTAssertEqual(filter(["Use the [main] branch."]), "Use the main branch.")
    }

    func testUnclosedAsideIsResolvedAtFlush() {
        XCTAssertEqual(filter(["Sure. (Though I wonder about the"]), "Sure. ")
        XCTAssertEqual(filter(["Sure (ok"]), "Sure ok")
    }

    func testStrayClosingBracketIsKept() {
        XCTAssertEqual(filter(["Step 1) open it. Then (sure) go."]), "Step 1) open it. Then sure go.")
    }

    func testNestedAsideIsDroppedWhole() {
        XCTAssertEqual(filter(["Yes (well, mostly (sometimes) true) okay."]), "Yes  okay.")
    }
}
