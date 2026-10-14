import AppKit
import SwiftUI

extension AssistantEngine.Phase {
    var color: Color {
        switch self {
        case .loading: return .gray
        case .idle: return .cyan
        case .listening: return .blue
        case .transcribing: return .purple
        case .thinking: return .orange
        case .speaking: return .green
        case .failed: return .red
        }
    }

    var label: String {
        switch self {
        case .loading: return "Loading"
        case .idle: return "Say \u{201C}Emma\u{201D}"
        case .listening: return "Listening…"
        case .transcribing: return "Transcribing…"
        case .thinking: return "Thinking…"
        case .speaking: return "Speaking…"
        case .failed: return "Error"
        }
    }

    var menuBarSymbol: String {
        switch self {
        case .loading: return "hourglass"
        case .idle: return "circle.circle"
        case .listening: return "waveform.circle.fill"
        case .transcribing: return "ellipsis.circle.fill"
        case .thinking: return "brain"
        case .speaking: return "speaker.wave.2.circle.fill"
        case .failed: return "exclamationmark.circle"
        }
    }
}
