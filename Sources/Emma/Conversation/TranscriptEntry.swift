import Foundation

/// One exchange in the panel: what the user said and Emma's reply.
struct TranscriptEntry: Identifiable {
    let id = UUID()
    var date = Date()
    var text: String
    var audioSeconds: Double
    var transcribeSeconds: Double
    /// Emma's reply, filled in as it streams.
    var reply = ""
}

extension TranscriptEntry {
    /// Adds the next transcribed segment of a long recording.
    mutating func append(_ segment: String, audioSeconds: Double, transcribeSeconds: Double) {
        text += " " + segment
        self.audioSeconds += audioSeconds
        self.transcribeSeconds += transcribeSeconds
    }
}
