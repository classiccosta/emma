import Foundation

/// A small rolling log of conversations, for tuning Emma's rules from real use:
/// what Whisper heard, which rule handled it, the model's raw reply, and what was actually spoken.
/// Kept to the last few hundred lines in `~/Library/Logs/Emma-conversation.log`.
@MainActor
enum ConversationLog {
    static let url = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/Logs/Emma-conversation.log")
    /// When the file passes `maxLines`, only the newest `keepLines` are kept.
    private static let maxLines = 400
    private static let keepLines = 200
    private static var lineCount: Int?
    /// Local time, so entries match the clock the user remembers.
    private static let formatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return formatter
    }()

    /// Appends "2026-10-14 16:28:25  HEARD     what's the capital of France".
    static func write(_ kind: String, _ text: String = "") {
        let stamp = formatter.string(from: Date())
        let line = "\(stamp)  \(kind.padding(toLength: 8, withPad: " ", startingAt: 0))  \(text)\n"
        if lineCount == nil { lineCount = currentLines().count }
        guard let data = line.data(using: .utf8) else { return }
        if let handle = try? FileHandle(forWritingTo: url) {
            handle.seekToEndOfFile()
            handle.write(data)
            try? handle.close()
        } else {
            try? data.write(to: url)
        }
        lineCount = (lineCount ?? 0) + 1
        if let count = lineCount, count > maxLines { trim() }
    }

    /// Empties the log (Settings › Diagnostics).
    static func clear() {
        try? Data().write(to: url)
        lineCount = 0
        write("START", "log cleared")
    }

    private static func currentLines() -> [Substring] {
        guard let text = try? String(contentsOf: url, encoding: .utf8) else { return [] }
        return text.split(separator: "\n", omittingEmptySubsequences: true)
    }

    private static func trim() {
        let kept = currentLines().suffix(keepLines)
        try? (kept.joined(separator: "\n") + "\n").write(to: url, atomically: true, encoding: .utf8)
        lineCount = kept.count
    }
}
