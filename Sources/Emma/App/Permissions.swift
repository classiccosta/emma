import AVFoundation
import Speech

/// The microphone and speech recognition permissions Emma needs before she can listen.
enum Permissions {
    /// Asks for both. Nil when granted, otherwise the message to show.
    @MainActor
    static func request() async -> String? {
        guard await AVCaptureDevice.requestAccess(for: .audio) else {
            return "Microphone access denied. Allow Emma in System Settings › Privacy & Security › Microphone, then relaunch."
        }
        let speech = await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { continuation.resume(returning: $0) }
        }
        guard speech == .authorized else {
            return "Speech recognition denied. Allow Emma in System Settings › Privacy & Security › Speech Recognition, then relaunch."
        }
        return nil
    }
}
