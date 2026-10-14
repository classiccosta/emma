import Foundation

/// LM Studio's local server: reachability, starting it, and loading the model ahead of the first question.
enum LMStudio {
    // Constant, valid URL.
    static let baseURL = URL(string: "http://localhost:1234/v1/")!

    static func request(_ path: String, body: JSON? = nil, timeout: TimeInterval = 120) throws -> URLRequest {
        var request = URLRequest(url: baseURL.appendingPathComponent(path), timeoutInterval: timeout)
        if let body {
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "content-type")
            request.httpBody = try body.data()
        }
        return request
    }

    /// Starts the request, turning "connection refused" into a readable error.
    static func perform(_ request: URLRequest) async throws -> (URLSession.AsyncBytes, URLResponse) {
        do {
            return try await URLSession.shared.bytes(for: request)
        } catch let error as URLError where error.code == .cannotConnectToHost {
            throw LLMError(message: "LM Studio server isn't running. Start it with `lms server start`.")
        }
    }

    static func error(status: Int, body: Data, model: String) -> LLMError {
        let json = try? JSON.parse(body)
        let message = json?["error"]?["message"]?.string ?? json?["error"]?.string
        if status == 404 || message?.localizedCaseInsensitiveContains("not found") == true {
            return LLMError(message: "Model \(model) isn't downloaded in LM Studio. Run `lms get \(model)`.")
        }
        return LLMError(message: message ?? "LM Studio request failed (HTTP \(status)).")
    }

    static func isRunning() async -> Bool {
        guard let request = try? request("models", timeout: 1),
              let (_, response) = try? await URLSession.shared.data(for: request) else { return false }
        return (response as? HTTPURLResponse)?.statusCode == 200
    }

    /// Runs `lms server start` if LM Studio is installed. Returns once the server answers or after about 15 s.
    static func startServer() async -> Bool {
        guard let cli = ToolLocator.find("lms") else { return false }
        let process = Process()
        process.executableURL = cli
        process.arguments = ["server", "start"]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        guard (try? process.run()) != nil else { return false }
        for _ in 0..<15 {
            if await isRunning() { return true }
            try? await Task.sleep(for: .seconds(1))
        }
        return false
    }

    /// A one-token request with the real system prompt, so LM Studio loads the model (or pages it back
    /// into RAM after idle) and caches the prompt prefix before the actual question.
    static func warmUp(model: String, system: String) async throws {
        let messages: [JSON] = [.object(["role": "system", "content": .string(system)]),
                                .object(["role": "user", "content": "hi"])]
        let body = JSON.object(["model": .string(model), "max_tokens": .number(1), "messages": .array(messages)])
        let (bytes, response) = try await perform(request("chat/completions", body: body))
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        var raw = Data()
        for try await byte in bytes { raw.append(byte) }
        guard status == 200 else { throw error(status: status, body: raw, model: model) }
    }
}
