import Foundation

/// Removes bracketed asides from streamed reply text. Small models keep adding
/// "(Honestly, ...)" asides despite the prompt, which makes replies long and odd to hear.
/// Asides of three or more words are dropped; shorter ones like "(30 × 9/5)" keep their content.
/// Pure state, so it can be driven by synthetic deltas.
struct AsideFilter {
    private var depth = 0
    private var aside = ""

    /// Returns the part of `delta` that is safe to show and speak now.
    mutating func feed(_ delta: String) -> String {
        var out = ""
        for char in delta {
            switch char {
            case "(", "[":
                depth += 1
                if depth > 1 { aside.append(char) }
            case ")" where depth > 0, "]" where depth > 0:
                depth -= 1
                if depth == 0 {
                    out += resolved()
                } else {
                    aside.append(char)
                }
            default:
                if depth > 0 { aside.append(char) } else { out.append(char) }
            }
        }
        return out
    }

    /// Ends the stream. An aside that never closed is resolved like a closed one.
    mutating func flush() -> String {
        guard depth > 0 else { return "" }
        depth = 0
        return resolved()
    }

    private mutating func resolved() -> String {
        defer { aside = "" }
        let words = aside.split { !$0.isLetter && $0 != "'" }.filter { $0.count > 1 }
        return words.count >= 3 ? "" : aside
    }
}
