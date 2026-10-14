import Foundation

/// Case-insensitive regex matching with curly apostrophes normalised, shared by the reply rules.
enum TextPattern {
    static func matches(_ text: String, _ pattern: String) -> Bool {
        text.lowercased().replacingOccurrences(of: "\u{2019}", with: "'")
            .range(of: pattern, options: .regularExpression) != nil
    }
}
