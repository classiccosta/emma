@testable import Emma
import XCTest

/// Drives `Endpointer` with constant-level chunks (the RMS of a constant signal is its value).
final class EndpointerTests: XCTestCase {
    private let chunk = 1_600 // 100 ms at 16 kHz
    private let speech: Float = 0.1
    private let silence: Float = 0

    private func samples(seconds: Double) -> Int { Int(seconds * 16_000) }

    /// Feeds `count` chunks at `value` and returns every segment emitted, with the chunk index it came on.
    private func feed(_ endpointer: inout Endpointer, _ value: Float, chunks count: Int)
        -> [(index: Int, segment: Endpointer.Segment)] {
        var out: [(Int, Endpointer.Segment)] = []
        for index in 0..<count {
            if let segment = endpointer.feed([Float](repeating: value, count: chunk)) {
                out.append((index, segment))
            }
        }
        return out
    }

    func testSpeechThenThreeSecondsOfSilenceEndsUtteranceWithPreRoll() {
        var endpointer = Endpointer()
        XCTAssertTrue(feed(&endpointer, silence, chunks: 20).isEmpty) // 2 s idle, fills the 1.5 s pre-roll
        endpointer.beginCapture(includePreRoll: true)

        XCTAssertTrue(feed(&endpointer, speech, chunks: 20).isEmpty) // 2 s speech
        let out = feed(&endpointer, silence, chunks: 40)

        XCTAssertEqual(out.count, 1)
        XCTAssertEqual(out.first?.index, 29, "ends on the 30th silent chunk, exactly 3 s")
        XCTAssertEqual(out.first?.segment.isFinal, true)
        XCTAssertEqual(out.first?.segment.hadSpeech, true)
        XCTAssertEqual(out.first?.segment.samples.count, samples(seconds: 1.5 + 2 + 3))
        XCTAssertFalse(endpointer.capturing)
    }

    func testPreRollIsDroppedWhenNotRequested() {
        var endpointer = Endpointer()
        _ = feed(&endpointer, silence, chunks: 20)
        endpointer.beginCapture(includePreRoll: false)

        _ = feed(&endpointer, speech, chunks: 20)
        let out = feed(&endpointer, silence, chunks: 30)

        XCTAssertEqual(out.first?.segment.samples.count, samples(seconds: 2 + 3))
    }

    func testShortPauseDoesNotEndUtterance() {
        var endpointer = Endpointer()
        endpointer.beginCapture(includePreRoll: false)

        _ = feed(&endpointer, speech, chunks: 10)
        XCTAssertTrue(feed(&endpointer, silence, chunks: 29).isEmpty) // 2.9 s pause
        XCTAssertTrue(feed(&endpointer, speech, chunks: 10).isEmpty)
        XCTAssertTrue(endpointer.capturing)
    }

    func testNoSpeechTimesOutAfterFiveSeconds() {
        var endpointer = Endpointer()
        endpointer.beginCapture(includePreRoll: false)

        let out = feed(&endpointer, silence, chunks: 60)

        XCTAssertEqual(out.count, 1)
        XCTAssertEqual(out.first?.index, 49)
        XCTAssertEqual(out.first?.segment.isFinal, true)
        XCTAssertEqual(out.first?.segment.samples.count, samples(seconds: 5))
        XCTAssertEqual(out.first?.segment.hadSpeech, false)
    }

    func testNoSpeechTimeoutCanBeOverriddenPerCapture() {
        var endpointer = Endpointer()
        endpointer.beginCapture(includePreRoll: false, noSpeechTimeout: 2)
        let out = feed(&endpointer, silence, chunks: 30)
        XCTAssertEqual(out.first?.index, 19, "times out after 2 s")
        XCTAssertEqual(out.first?.segment.hadSpeech, false)

        endpointer.beginCapture(includePreRoll: false)
        XCTAssertEqual(feed(&endpointer, silence, chunks: 60).first?.index, 49, "next capture is back to 5 s")
    }

    func testLongSpeechIsCutAtLatestPauseAndRecordingContinues() {
        var endpointer = Endpointer()
        endpointer.beginCapture(includePreRoll: false)

        _ = feed(&endpointer, speech, chunks: 1_170) // 0 to 117 s
        _ = feed(&endpointer, silence, chunks: 1) // pause, 117.0 to 117.1 s
        let cut = feed(&endpointer, speech, chunks: 29) // to 120 s

        XCTAssertEqual(cut.count, 1)
        XCTAssertEqual(cut.first?.segment.isFinal, false)
        XCTAssertEqual(cut.first?.segment.samples.count, samples(seconds: 117.1))
        XCTAssertTrue(endpointer.capturing)

        let final = feed(&endpointer, silence, chunks: 30)
        XCTAssertEqual(final.first?.segment.isFinal, true)
        XCTAssertEqual(final.first?.segment.samples.count, samples(seconds: 2.9 + 3),
                       "the rest after the cut is kept, not lost")
    }

    func testLongSpeechWithoutRecentPauseIsCutAtLimit() {
        var endpointer = Endpointer()
        endpointer.beginCapture(includePreRoll: false)

        _ = feed(&endpointer, speech, chunks: 1_100) // 0 to 110 s
        _ = feed(&endpointer, silence, chunks: 1) // pause at 110 s, outside the 5 s search window
        let out = feed(&endpointer, speech, chunks: 99) // to 120 s

        XCTAssertEqual(out.count, 1)
        XCTAssertEqual(out.first?.segment.isFinal, false)
        XCTAssertEqual(out.first?.segment.samples.count, samples(seconds: 120))
    }

    func testSpeechLevelCountsInQuietRoom() {
        var endpointer = Endpointer()
        endpointer.beginCapture(includePreRoll: false)

        XCTAssertTrue(feed(&endpointer, 0.03, chunks: 60).isEmpty, "0.03 is speech, so no 5 s timeout")
    }

    func testNoiseFloorAdaptsToLoudRoom() {
        var endpointer = Endpointer()
        _ = feed(&endpointer, 0.02, chunks: 3_000) // 5 min of steady room noise
        XCTAssertGreaterThan(endpointer.noiseFloor, 0.015)
        endpointer.beginCapture(includePreRoll: false)

        // Same 0.03 level now sits under the raised threshold, so it times out as no speech.
        let out = feed(&endpointer, 0.03, chunks: 60)
        XCTAssertEqual(out.first?.index, 49)
        XCTAssertEqual(out.first?.segment.isFinal, true)
    }

    func testNoiseFloorFreezesWhileCapturing() {
        var endpointer = Endpointer()
        endpointer.beginCapture(includePreRoll: false)
        let before = endpointer.noiseFloor

        _ = feed(&endpointer, speech, chunks: 20)

        XCTAssertEqual(endpointer.noiseFloor, before)
    }
}
