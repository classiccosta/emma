import Foundation

/// Enforces how Emma addresses the user in model-written text: "sir" only in greetings and goodbyes.
/// The prompt asks for the same, but small models drift, so every model sentence passes through here
/// before it is spoken or shown. Stock phrases are already correct and skip it.
enum Address {
    private static let farewell = [
        #"\bhave an? (great|good|nice|lovely|wonderful|fantastic)\b.*\b(day|evening|night|weekend|one|rest|afternoon|morning)\b"#,
        #"\btake care\b"#, #"\bbye\b"#, #"\bgoodbye\b"#, #"\bsee you\b"#, #"\btalk (soon|later)\b"#, #"\banytime\b"#,
        #"\byou'?re welcome\b"#, #"\bglad (i|to) (could )?help\b"#, #"\benjoy (your|the)\b"#, #"\bcatch you later\b"#,
    ].joined(separator: "|")
    private static let greeting = #"^(hello|hi|hey|good (morning|afternoon|evening))\b|what can i do for you|how can i help"#

    static func isFarewell(_ sentence: String) -> Bool {
        TextPattern.matches(sentence, farewell)
    }

    static func isGreetingLike(_ sentence: String) -> Bool {
        TextPattern.matches(sentence, greeting)
    }

    /// One sentence on its own; see `Addresser` for a whole reply.
    static func adjust(_ sentence: String) -> String {
        var addresser = Addresser()
        return addresser.adjust(sentence)
    }

    static func hasSir(_ text: String) -> Bool {
        TextPattern.matches(text, #"\bsir\b"#)
    }

    /// Titles Emma might use: "sir", "madam", and the custom word if there is one.
    static func titles(plus word: String?) -> [String] {
        var titles = ["sir", "madam"]
        if let word, !titles.contains(word.lowercased()) { titles.append(NSRegularExpression.escapedPattern(for: word.lowercased())) }
        return titles
    }

    private static func titlePattern(_ titles: [String]) -> String {
        #"\b("# + titles.joined(separator: "|") + #")\b"#
    }

    static func hasTitle(_ text: String, _ titles: [String]) -> Bool {
        TextPattern.matches(text, titlePattern(titles))
    }

    /// "Have a great day." -> "Have a great day, sir."
    fileprivate static func add(_ word: String, to sentence: String) -> String {
        let trimmed = sentence.trimmingCharacters(in: .whitespaces)
        guard let range = trimmed.range(of: #"[.!?…]+["'\u{201D}\u{2019}]*$"#, options: .regularExpression) else {
            return trimmed + ", " + word
        }
        return trimmed[..<range.lowerBound] + ", " + word + trimmed[range]
    }

    /// "Canberra, sir, not Sydney." -> "Canberra, not Sydney."; "Sir, it's 86." -> "It's 86."
    fileprivate static func remove(_ titles: [String], from sentence: String) -> String {
        var text = sentence.replacingOccurrences(of: #"(,\s*)?"# + titlePattern(titles), with: "",
                                                 options: [.regularExpression, .caseInsensitive])
        for (pattern, template) in [(#"^\s*,\s*"#, ""), (#",\s*,"#, ","), (#"\s+([.!?,…])"#, "$1"), (#"\s{2,}"#, " ")] {
            text = text.replacingOccurrences(of: pattern, with: template, options: .regularExpression)
        }
        text = text.trimmingCharacters(in: .whitespaces)
        return text.prefix(1).uppercased() + text.dropFirst()
    }

    /// The sentence with any "sir" removed.
    static func withoutSir(_ sentence: String) -> String {
        hasSir(sentence) ? remove(["sir"], from: sentence) : sentence
    }

    /// A stock phrase in the chosen form of address: "sir" becomes the word, or is removed for none.
    static func render(_ phrase: String, word: String?) -> String {
        guard hasSir(phrase) else { return phrase }
        guard let word else { return remove(["sir"], from: phrase) }
        return phrase.replacingOccurrences(of: #"\bsir\b"#, with: word, options: .regularExpression)
            .replacingOccurrences(of: #"\bSir\b"#, with: word.prefix(1).uppercased() + word.dropFirst(), options: .regularExpression)
    }
}

/// Applies the form-of-address rule across one reply's sentences, in order: a greeting or goodbye (each
/// switchable) gets the word unless the reply already said it, and every other sentence loses any title.
/// "Anytime, sir. Have a great day." stays as is.
struct Addresser {
    private let word: String?
    private let inGreetings: Bool
    private let inGoodbyes: Bool
    private let titles: [String]
    private var said = false

    init(word: String? = "sir", inGreetings: Bool = true, inGoodbyes: Bool = true) {
        self.word = word
        self.inGreetings = inGreetings
        self.inGoodbyes = inGoodbyes
        titles = Address.titles(plus: word)
    }

    mutating func adjust(_ sentence: String) -> String {
        let hasTitle = Address.hasTitle(sentence, titles)
        let result: String
        if let word, (inGoodbyes && Address.isFarewell(sentence)) || (inGreetings && Address.isGreetingLike(sentence)) {
            let hasWord = Address.hasTitle(sentence, [NSRegularExpression.escapedPattern(for: word.lowercased())])
            if hasWord, !said {
                result = sentence
            } else {
                let bare = hasTitle ? Address.remove(titles, from: sentence) : sentence
                result = said ? bare : Address.add(word, to: bare)
            }
        } else {
            result = hasTitle ? Address.remove(titles, from: sentence) : sentence
        }
        if let word, Address.hasTitle(result, [NSRegularExpression.escapedPattern(for: word.lowercased())]) { said = true }
        return result
    }
}
