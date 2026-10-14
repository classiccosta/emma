/// Cuts streamed reply text into sentences so speech can start before the reply is complete.
/// Pure state, so it can be driven by synthetic deltas.
struct SentenceSplitter {
    private static let terminators: Set<Character> = [".", "!", "?"]
    /// Characters that may follow a terminator and still belong to the sentence.
    private static let closers: Set<Character> = ["\"", "'", ")", "\u{201D}", "\u{2019}"]
    private static let abbreviations: Set<String> = ["mr", "mrs", "ms", "dr", "st", "vs", "jr", "sr", "prof"]

    private var buffer = ""

    /// Adds a text delta and returns the sentences it completed.
    mutating func feed(_ delta: String) -> [String] {
        buffer += delta
        let chars = Array(buffer)
        var sentences: [String] = []
        var start = 0
        var index = 0
        scan: while index < chars.count {
            let char = chars[index]
            if char == "\n" {
                Self.append(chars[start..<index], to: &sentences)
                start = index + 1
            } else if Self.terminators.contains(char) {
                var end = index + 1
                while end < chars.count, Self.closers.contains(chars[end]) { end += 1 }
                // Wait for the next character to know whether the sentence really ended.
                guard end < chars.count else { break scan }
                if chars[end].isWhitespace, !(char == "." && Self.isAbbreviation(chars[start..<index])) {
                    Self.append(chars[start..<end], to: &sentences)
                    start = end
                }
                index = end
                continue
            }
            index += 1
        }
        buffer = String(chars[start...])
        return sentences
    }

    /// Returns whatever is left once the reply has finished streaming.
    mutating func flush() -> String? {
        let rest = buffer.trimmingCharacters(in: .whitespacesAndNewlines)
        buffer = ""
        return rest.isEmpty ? nil : rest
    }

    private static func append(_ chars: ArraySlice<Character>, to sentences: inout [String]) {
        let sentence = String(chars).trimmingCharacters(in: .whitespacesAndNewlines)
        if !sentence.isEmpty { sentences.append(sentence) }
    }

    /// "Dr." or "e.g." or an initial like "J." before the period.
    private static func isAbbreviation(_ chars: ArraySlice<Character>) -> Bool {
        let word = String(chars).split(whereSeparator: \.isWhitespace).last.map(String.init) ?? ""
        if word.contains(".") { return true }
        if word.count == 1, word.first?.isUppercase == true { return true }
        return abbreviations.contains(word.lowercased())
    }
}
