import Foundation

/// Rewrites one sentence so the voice never reads symbols or markup aloud.
/// The transcript panel keeps the original text.
enum SpeechText {
    private static let replacements: [(pattern: String, template: String)] = [
        (#"https?://\S+|www\.\S+"#, "the link"),
        (#"`+"#, ""),
        (#"\*+|(?<!\w)_+|_+(?!\w)|#+\s*"#, ""),
        (#"^\s*[-•]\s+"#, ""),
        (#"(?i)\be\.g\.,?"#, "for example"),
        (#"(?i)\bi\.e\.,?"#, "that is"),
        (#"(?i)\bvs\.?(?=\s)"#, "versus"),
        (#"(?i)\betc\."#, "and so on"),
        (#"\s*&\s*"#, " and "),
        (#"(\d)\s*%"#, "$1 percent"),
        (#"(\d)\s*°\s*F\b"#, "$1 degrees Fahrenheit"),
        (#"(\d)\s*°\s*C\b"#, "$1 degrees Celsius"),
        (#"°"#, " degrees"),
        (#"(^|\s)~\s*(?=\d)"#, "$1about "),
        (#"\s*[×]\s*"#, " times "),
        (#"(?<=\s)=(?=\s)"#, "equals"),
        (#"(?<=\s)\+(?=\s)"#, "plus"),
        (#"(?<=[A-Za-z])/(?=[A-Za-z])"#, " or "),
        (#"[\p{Extended_Pictographic}\x{FE0F}\x{200D}]"#, ""),
        (#"\s+"#, " "),
    ]

    static func clean(_ sentence: String) -> String {
        var text = sentence
        for (pattern, template) in replacements {
            text = text.replacingOccurrences(of: pattern, with: template, options: .regularExpression)
        }
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
