@testable import Emma
import XCTest

final class GreetingTests: XCTestCase {
    private let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")! // swiftlint:disable:this force_unwrapping
        return calendar
    }()

    /// 14 October 2026 (or `day`) at `hour:minute` UTC.
    private func date(day: Int = 14, _ hour: Int, _ minute: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 10, day: day, hour: hour, minute: minute))! // swiftlint:disable:this force_unwrapping
    }

    func testPeriodBoundaries() {
        struct Case {
            let hour: Int, minute: Int, period: DayPeriod, day: Int
        }
        let cases = [
            Case(hour: 4, minute: 59, period: .evening, day: 13), // late night belongs to the previous day's evening
            Case(hour: 5, minute: 0, period: .morning, day: 14),
            Case(hour: 11, minute: 59, period: .morning, day: 14),
            Case(hour: 12, minute: 0, period: .afternoon, day: 14),
            Case(hour: 17, minute: 59, period: .afternoon, day: 14),
            Case(hour: 18, minute: 0, period: .evening, day: 14),
            Case(hour: 23, minute: 59, period: .evening, day: 14),
        ]
        for test in cases {
            let key = DayPeriod.key(for: date(test.hour, test.minute), calendar: calendar)
            XCTAssertEqual(key.period, test.period, "\(test.hour):\(test.minute)")
            XCTAssertEqual(key.day.day, test.day, "\(test.hour):\(test.minute)")
        }
    }

    func testGreetsOncePerPeriod() {
        var greeter = Greeter()
        XCTAssertEqual(greeter.greeting(at: date(9), calendar: calendar), "Hello sir. Good morning.")
        XCTAssertNil(greeter.greeting(at: date(10, 30), calendar: calendar))
        XCTAssertEqual(greeter.greeting(at: date(13), calendar: calendar), "Hello sir. Good afternoon.")
        XCTAssertNil(greeter.greeting(at: date(17), calendar: calendar))
    }

    func testLateNightStaysInTheSameEvening() {
        var greeter = Greeter()
        XCTAssertEqual(greeter.greeting(at: date(23), calendar: calendar), "Hello sir. Good evening.")
        XCTAssertNil(greeter.greeting(at: date(day: 15, 0, 30), calendar: calendar))
        XCTAssertNil(greeter.greeting(at: date(day: 15, 4), calendar: calendar))
        XCTAssertEqual(greeter.greeting(at: date(day: 15, 8), calendar: calendar), "Hello sir. Good morning.")
    }

    func testSamePeriodNextDayGreetsAgain() {
        var greeter = Greeter()
        XCTAssertNotNil(greeter.greeting(at: date(9), calendar: calendar))
        XCTAssertNotNil(greeter.greeting(at: date(day: 15, 9), calendar: calendar))
    }
}
