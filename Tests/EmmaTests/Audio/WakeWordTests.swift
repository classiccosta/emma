@testable import Emma
import XCTest

final class WakeWordTests: XCTestCase {
    func testCountsWholeWordEmma() {
        XCTAssertEqual(WakeWordDetector.wakeCount(in: "Emma"), 1)
        XCTAssertEqual(WakeWordDetector.wakeCount(in: "hey emma what time is it"), 1)
        XCTAssertEqual(WakeWordDetector.wakeCount(in: "Emma, EMMA."), 2)
    }

    func testIgnoresEmmaInsideOtherWords() {
        XCTAssertEqual(WakeWordDetector.wakeCount(in: "Gemma is a model"), 0)
        XCTAssertEqual(WakeWordDetector.wakeCount(in: "what a dilemma"), 0)
        XCTAssertEqual(WakeWordDetector.wakeCount(in: "Emmanuel called"), 0)
    }
}
