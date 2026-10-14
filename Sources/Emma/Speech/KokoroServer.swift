import AVFoundation
import Foundation

/// The Kokoro sidecar (`sidecars/kokoro/tts_server.py`): a local HTTP server that Emma launches with uv.
@MainActor
final class KokoroServer {
    // Constant, valid URL.
    nonisolated static let baseURL = URL(string: "http://127.0.0.1:8880/")!
    static let logURL = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/Logs/Emma-kokoro.log")

    private var process: Process?

    /// Launches the sidecar if it isn't running and waits until the voice model is loaded.
    /// The first run downloads about 340 MB, so this allows up to 10 minutes. `onStatus` reports progress.
    func start(onStatus: (String) -> Void) async -> Bool {
        if await Self.health() == nil {
            guard launch() else { return false }
        }
        for _ in 0..<600 {
            if let health = await Self.health() {
                if health.ready { return true }
                if health.status.hasPrefix("failed") { return false }
                onStatus(health.status)
            } else if process?.isRunning == false {
                return false
            }
            try? await Task.sleep(for: .seconds(1))
        }
        return false
    }

    private func launch() -> Bool {
        guard let script = Bundle.main.url(forResource: "tts_server", withExtension: "py"),
              let uvTool = ToolLocator.find("uv") else { return false }
        FileManager.default.createFile(atPath: Self.logURL.path, contents: nil)
        let log = try? FileHandle(forWritingTo: Self.logURL)
        let process = Process()
        process.executableURL = uvTool
        // The script exits on its own when Emma does.
        process.arguments = ["run", "--script", script.path, "--parent-pid", String(ProcessInfo.processInfo.processIdentifier)]
        process.standardOutput = log
        process.standardError = log
        guard (try? process.run()) != nil else { return false }
        self.process = process
        return true
    }

    nonisolated static func health() async -> (ready: Bool, status: String)? {
        let request = URLRequest(url: baseURL.appendingPathComponent("health"), timeoutInterval: 1)
        guard let (data, _) = try? await URLSession.shared.data(for: request),
              let json = try? JSON.parse(data) else { return nil }
        return (json["ready"] == .bool(true), json["status"]?.string ?? "")
    }

    /// WAV audio for one sentence.
    nonisolated static func synthesize(_ text: String, speed: Double, pause: Double = 0.3) async throws -> Data {
        var request = URLRequest(url: baseURL.appendingPathComponent("speak"), timeoutInterval: 30)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "content-type")
        request.httpBody = try JSON.object(["text": .string(text), "voice": .string(KokoroSpeech.voice), "speed": .number(speed), "pause": .number(pause)]).data()
        let (data, response) = try await URLSession.shared.data(for: request)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else {
            throw LLMError(message: (try? JSON.parse(data))?["error"]?.string ?? "Kokoro synthesis failed.")
        }
        return data
    }
}
