import Foundation

/// Start hours of each part of the day. Late night, before the morning start, belongs to the evening it started in.
struct DayBoundaries: Equatable {
    var morning = 5
    var afternoon = 12
    var evening = 18
}

/// Part of the day used for Emma's greeting.
enum DayPeriod: Equatable {
    case morning
    case afternoon
    case evening

    /// Day and period for `date`. The day is taken `morning` hours earlier so late night stays in the previous evening.
    static func key(for date: Date, boundaries: DayBoundaries = DayBoundaries(),
                    calendar: Calendar = .current) -> (day: DateComponents, period: DayPeriod) {
        let hour = calendar.component(.hour, from: date)
        let period: DayPeriod
        switch hour {
        case boundaries.morning..<boundaries.afternoon: period = .morning
        case boundaries.afternoon..<boundaries.evening: period = .afternoon
        default: period = .evening
        }
        let shifted = date.addingTimeInterval(-Double(boundaries.morning) * 3600)
        return (calendar.dateComponents([.year, .month, .day], from: shifted), period)
    }

    /// "Hello sir. Good morning.", or "Hello. Good morning." with no form of address.
    func greeting(word: String? = "sir") -> String {
        let hello = word.map { "Hello \($0)." } ?? "Hello."
        switch self {
        case .morning: return hello + " Good morning."
        case .afternoon: return hello + " Good afternoon."
        case .evening: return hello + " Good evening."
        }
    }
}

/// Greets on the first reply after launch and on the first reply in each new part of the day.
/// In memory only, so every launch greets again.
struct Greeter {
    var boundaries = DayBoundaries()
    var word: String? = "sir"
    private var last: (day: DateComponents, period: DayPeriod)?

    /// The greeting if this is the first reply in `date`'s period, otherwise nil.
    mutating func greeting(at date: Date, calendar: Calendar = .current) -> String? {
        let key = DayPeriod.key(for: date, boundaries: boundaries, calendar: calendar)
        if let last, last.day == key.day, last.period == key.period { return nil }
        last = key
        return key.period.greeting(word: word)
    }
}
