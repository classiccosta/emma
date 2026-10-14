import Foundation

/// Goes through the pool in shuffled order, reshuffling when it runs out,
/// and never says the same phrase twice in a row.
struct PhraseRotation {
    private let pool: [String]
    private let shuffle: ([String]) -> [String]
    private var queue: [String] = []
    private var last: String?

    init(pool: [String], shuffle: @escaping ([String]) -> [String] = { $0.shuffled() }) {
        self.pool = pool
        self.shuffle = shuffle
    }

    mutating func next() -> String {
        if queue.isEmpty {
            queue = shuffle(pool)
            if queue.count > 1, queue.first == last { queue.swapAt(0, queue.count - 1) }
        }
        let phrase = queue.removeFirst()
        last = phrase
        return phrase
    }
}

/// Emma's rotating stock replies and the once-per-period greeting, built from the settings,
/// so the engine only asks for the next one. "sir" in the phrases becomes the chosen form of address,
/// in greeting phrases only if it's on for greetings and in goodbye phrases only if it's on for goodbyes.
struct StockReplies {
    private var greeter = Greeter()
    private var phrases = PhraseSettings()
    private var fillers = PhraseRotation(pool: Phrases.fillers)
    private var declineAcks = PhraseRotation(pool: Phrases.declineAcks)
    private var greetReplies = PhraseRotation(pool: Phrases.greetReplies)
    private var closings = PhraseRotation(pool: Phrases.closings)
    private var empathy = PhraseRotation(pool: Phrases.empathy)
    private var word: String? = "sir"
    private var greetWord: String? = "sir"
    private var byeWord: String? = "sir"
    private var periodGreetingOn = true

    init(settings: Settings = Settings()) {
        update(settings)
    }

    /// Takes new settings. Rotations restart only when their phrase lists change.
    mutating func update(_ settings: Settings) {
        word = settings.addressWord
        greetWord = settings.addressInGreetings ? word : nil
        byeWord = settings.addressInGoodbyes ? word : nil
        periodGreetingOn = settings.periodGreeting
        greeter.word = greetWord
        greeter.boundaries = DayBoundaries(morning: settings.morningStart, afternoon: settings.afternoonStart,
                                           evening: settings.eveningStart)
        let new = settings.phrases
        if new.fillers != phrases.fillers { fillers = PhraseRotation(pool: new.fillers) }
        if new.declineAcks != phrases.declineAcks { declineAcks = PhraseRotation(pool: new.declineAcks) }
        if new.greetReplies != phrases.greetReplies { greetReplies = PhraseRotation(pool: new.greetReplies) }
        if new.closings != phrases.closings { closings = PhraseRotation(pool: new.closings) }
        if new.empathy != phrases.empathy { empathy = PhraseRotation(pool: new.empathy) }
        phrases = new
    }

    /// Every phrase as it will be spoken, for pre-synthesis.
    var allRendered: [String] {
        let greetings = phrases.greetReplies.map { Address.render($0, word: greetWord) } + [Phrases.cantDoYet]
        let periods = [DayPeriod.morning, .afternoon, .evening].map { $0.greeting(word: greetWord) }
        let rest = phrases.fillers.map { Address.render($0, word: word) } + phrases.empathy.map { Address.render($0, word: word) }
            + (phrases.closings + phrases.declineAcks).map { Address.render($0, word: byeWord) }
            + [Address.render(phrases.anythingElse, word: greetWord)]
        return Array(Set(greetings + periods + rest))
    }

    /// "Hello sir. Good afternoon." if this is the first reply in this part of the day, else nil.
    mutating func periodGreeting(at date: Date = Date()) -> String? {
        periodGreetingOn ? greeter.greeting(at: date) : nil
    }

    /// The period greeting if due ("Hello sir. Good evening." is enough on its own), otherwise a greet reply.
    mutating func greeting(at date: Date = Date()) -> [String] {
        if let greeting = periodGreeting(at: date) { return [greeting] }
        return [Address.render(greetReplies.next(), word: greetWord)]
    }

    var anythingElse: String { Address.render(phrases.anythingElse, word: greetWord) }
    mutating func filler() -> String { Address.render(fillers.next(), word: word) }
    mutating func closing() -> String { Address.render(closings.next(), word: byeWord) }
    mutating func declineAck() -> String { Address.render(declineAcks.next(), word: byeWord) }
    mutating func empathyLine() -> String { Address.render(empathy.next(), word: word) }
}
