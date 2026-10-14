import AppKit
import SwiftUI

struct PanelView: View {
    @EnvironmentObject var engine: AssistantEngine

    var body: some View {
        VStack(spacing: 12) {
            HStack {
                Text("Emma").font(.headline)
                Spacer()
                Text(statusLabel)
                    .font(.subheadline)
                    .foregroundStyle(engine.phase.color)
            }

            OrbView(phase: engine.phase, level: engine.level)

            switch engine.phase {
            case .loading(let message), .failed(let message):
                Text(message)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            default:
                EmptyView()
            }

            transcript

            HStack {
                Button("Listen now") { engine.listenNow() }
                    .disabled(engine.phase != .idle)
                Button("Clear") { engine.clear() }
                    .disabled(engine.entries.isEmpty)
                if engine.phase == .thinking || engine.phase == .speaking || engine.isFollowUp {
                    Button("Stop") { engine.stopReply() }
                }
                Spacer()
                SettingsLink {
                    Image(systemName: "gearshape")
                }
                .help("Settings (⌘,)")
                Button("Quit") { NSApplication.shared.terminate(nil) }
            }
            .controlSize(.small)

            if engine.phase == .idle, let status = engine.llmStatus ?? engine.ttsStatus {
                Text(status)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if engine.phase == .idle, !engine.wakeIsOnDevice {
                Text("Wake word is using Apple's server recognizer (on-device model not installed).")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(16)
        .frame(width: 360)
    }

    private var statusLabel: String {
        guard engine.phase == .listening else { return engine.phase.label }
        if engine.isFollowUp { return "Go ahead…" }
        return engine.isLongRecording ? "Long recording…" : engine.phase.label
    }

    private var transcript: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 10) {
                    if engine.entries.isEmpty {
                        Text("Transcripts appear here.")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .center)
                            .padding(.top, 40)
                    }
                    ForEach(engine.entries) { entry in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(entry.text).textSelection(.enabled)
                            if !entry.reply.isEmpty {
                                Text(entry.reply)
                                    .foregroundStyle(.secondary)
                                    .textSelection(.enabled)
                            }
                            Text("\(entry.date.formatted(date: .omitted, time: .standard)) · \(String(format: "%.1fs audio · %.2fs whisper", entry.audioSeconds, entry.transcribeSeconds))")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                        .id(entry.id)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(height: 220)
            .onChange(of: engine.entries.count) {
                if let last = engine.entries.last { proxy.scrollTo(last.id, anchor: .bottom) }
            }
            .onChange(of: engine.entries.last?.reply) {
                if let last = engine.entries.last { proxy.scrollTo(last.id, anchor: .bottom) }
            }
        }
    }
}
