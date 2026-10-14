import Foundation

/// A client-side tool the model can call. Calendar, Reminders and Notes tools plug in here later.
protocol EmmaTool: Sendable {
    var name: String { get }
    var description: String { get }
    /// JSON schema for the arguments.
    var parameters: JSON { get }
    func run(_ arguments: JSON) async throws -> String
}

struct LLMError: LocalizedError {
    let message: String
    var errorDescription: String? { message }
}

/// What the reply pipeline needs from a chat model, so a fake can stand in for tests.
protocol ChatModel: Sendable {
    func respond(history: [JSON], user: JSON,
                 onText: @escaping @MainActor @Sendable (String) -> Void) async throws -> LocalLLMClient.Result
}

/// Streams replies from LM Studio's OpenAI-compatible local server and runs the tool-call loop.
struct LocalLLMClient: Sendable {
    static let defaultModel = "qwen/qwen3-4b-2507"
    /// Upper bound on request/tool rounds for one user turn.
    private static let maxRounds = 8

    let model: String
    /// Built from the conversation settings by `PersonaPrompt`.
    let systemPrompt: String
    var temperature = 0.5
    var maxTokens = 200
    var tools: [any EmmaTool] = []

    struct Result: Sendable {
        /// Messages to append to the history after the user turn: assistant turns and tool results.
        let messages: [JSON]
    }

    /// Sends `user` after `history`, streaming visible text to `onText`, and runs tools until the model is done.
    func respond(history: [JSON], user: JSON,
                 onText: @escaping @MainActor @Sendable (String) -> Void) async throws -> Result {
        var added: [JSON] = []
        for _ in 0..<Self.maxRounds {
            let system = JSON.object(["role": "system", "content": .string(systemPrompt + "\n\n" + Self.now())])
            let turn = try await send(messages: [system] + history + [user] + added, onText: onText)
            added.append(turn.message)
            // Small models sometimes report "stop" alongside tool calls, so go by the calls themselves.
            guard !turn.toolCalls.isEmpty else { return Result(messages: added) }
            for call in turn.toolCalls {
                added.append(.object(["role": "tool", "tool_call_id": .string(call.id),
                                      "content": .string(await run(call))]))
            }
        }
        throw LLMError(message: "Too many tool calls.")
    }

    /// "Today is Tuesday, 14 October, 3:20 PM." so remarks about the day are grounded.
    private static func now() -> String {
        "Today is " + Date().formatted(.dateTime.weekday(.wide).day().month(.wide).hour().minute()) + "."
    }

    private func run(_ call: ChatStream.ToolCall) async -> String {
        guard let tool = tools.first(where: { $0.name == call.name }) else {
            return "Error: unknown tool \(call.name)."
        }
        guard let arguments = try? JSON.parse(Data((call.arguments.isEmpty ? "{}" : call.arguments).utf8)) else {
            return "Error: arguments were not valid JSON."
        }
        do {
            return try await tool.run(arguments)
        } catch {
            return "Error: \(error.localizedDescription)"
        }
    }

    private func send(messages: [JSON],
                      onText: @escaping @MainActor @Sendable (String) -> Void) async throws -> ChatStream {
        var body: [String: JSON] = [
            "model": .string(model),
            "stream": .bool(true),
            "temperature": .number(temperature),
            // A safety cap only; the prompt keeps replies short.
            "max_tokens": .number(Double(maxTokens)),
            "messages": .array(messages),
        ]
        if !tools.isEmpty {
            body["tools"] = .array(tools.map { tool in
                .object(["type": "function",
                         "function": .object(["name": .string(tool.name), "description": .string(tool.description),
                                              "parameters": tool.parameters])])
            })
        }

        let (bytes, response) = try await LMStudio.perform(LMStudio.request("chat/completions", body: .object(body)))
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard status == 200 else {
            var raw = Data()
            for try await byte in bytes { raw.append(byte) }
            throw LMStudio.error(status: status, body: raw, model: model)
        }

        var stream = ChatStream()
        for try await line in bytes.lines where line.hasPrefix("data:") {
            let payload = line.dropFirst(5).trimmingCharacters(in: .whitespaces)
            guard payload != "[DONE]" else { break }
            let chunk = try JSON.parse(Data(payload.utf8))
            if let message = chunk["error"]?["message"]?.string ?? chunk["error"]?.string {
                throw LLMError(message: message)
            }
            if let text = stream.apply(chunk) {
                await onText(text)
            }
        }
        return stream
    }
}

extension LocalLLMClient: ChatModel {}
