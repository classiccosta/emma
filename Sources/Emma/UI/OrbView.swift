import AppKit
import SwiftUI

/// A single breathing circle that swells with mic level while listening.
struct OrbView: View {
    let phase: AssistantEngine.Phase
    let level: Float

    var body: some View {
        TimelineView(.animation) { timeline in
            let t = timeline.date.timeIntervalSinceReferenceDate
            let breathe = 1 + 0.04 * sin(t * 2)
            let boost = phase == .listening ? CGFloat(min(level * 10, 1)) * 0.35 : 0
            let spin = phase == .transcribing || phase == .thinking ? 1 + 0.06 * sin(t * 8) : 1
            let talk = phase == .speaking ? 1 + 0.08 * abs(sin(t * 9)) : 1

            ZStack {
                Circle()
                    .stroke(phase.color.opacity(0.35), lineWidth: 2)
                    .frame(width: 96, height: 96)
                    .scaleEffect((1.2 + boost) * breathe)
                Circle()
                    .fill(phase.color.opacity(0.85))
                    .frame(width: 80, height: 80)
                    .scaleEffect((breathe + boost) * spin * talk)
            }
            .animation(.easeOut(duration: 0.12), value: boost)
        }
        .frame(height: 140)
    }
}
