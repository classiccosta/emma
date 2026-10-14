import Foundation

/// The Messages-style history sent to the model with each request.
struct ChatHistory {
    private(set) var messages: [JSON] = []

    var isEmpty: Bool { messages.isEmpty }

    mutating func clear() {
        messages.removeAll()
    }

    /// Appends one exchange, then drops whole turns from the front (a turn starts at a user message)
    /// until at most `limit` messages remain.
    mutating func append(user: JSON, reply: [JSON], limit: Int) {
        messages.append(user)
        messages.append(contentsOf: reply)
        while messages.count > limit {
            messages.removeFirst()
            while let first = messages.first, first["role"]?.string != "user" { messages.removeFirst() }
        }
    }

    /// A stock exchange the model should know about, like a declined offer.
    mutating func append(user text: String, assistant reply: String, limit: Int) {
        append(user: .object(["role": "user", "content": .string(text)]),
               reply: [.object(["role": "assistant", "content": .string(reply)])], limit: limit)
    }
}
