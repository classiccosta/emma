import Foundation

/// Assembles streamed chat-completion chunks into text and tool calls.
/// Pure state, so it is unit-tested with recorded chunks.
struct ChatStream {
    struct ToolCall: Equatable {
        var id = ""
        var name = ""
        var arguments = ""
    }

    private(set) var text = ""
    private(set) var finishReason: String?
    private var calls: [Int: ToolCall] = [:]

    var toolCalls: [ToolCall] {
        calls.keys.sorted().compactMap { calls[$0] }
    }

    /// The assistant message to append to the history.
    var message: JSON {
        var message: [String: JSON] = ["role": "assistant", "content": .string(text)]
        if !toolCalls.isEmpty {
            message["tool_calls"] = .array(toolCalls.map { call in
                .object(["id": .string(call.id), "type": "function",
                         "function": .object(["name": .string(call.name), "arguments": .string(call.arguments)])])
            })
        }
        return .object(message)
    }

    /// Applies one chunk and returns any new visible text.
    mutating func apply(_ chunk: JSON) -> String? {
        guard case .array(let choices)? = chunk["choices"], let choice = choices.first else { return nil }
        if let reason = choice["finish_reason"]?.string { finishReason = reason }
        guard let delta = choice["delta"] else { return nil }
        if case .array(let deltas)? = delta["tool_calls"] {
            for piece in deltas {
                let index = piece["index"]?.int ?? 0
                var call = calls[index] ?? ToolCall()
                if let id = piece["id"]?.string, !id.isEmpty { call.id = id }
                if let name = piece["function"]?["name"]?.string, !name.isEmpty { call.name = name }
                call.arguments += piece["function"]?["arguments"]?.string ?? ""
                calls[index] = call
            }
        }
        guard let piece = delta["content"]?.string, !piece.isEmpty else { return nil }
        text += piece
        return piece
    }
}
