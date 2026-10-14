import AppKit
import SwiftUI

/// The Settings window (⌘, or the panel's gear): every conversation rule, grouped in tabs.
/// Changes apply as you make them, after a short pause so typing doesn't trigger work on every keystroke.
struct SettingsWindow: View {
    @EnvironmentObject var engine: AssistantEngine
    @State private var draft = Settings()
    @State private var pendingApply: Task<Void, Never>?

    var body: some View {
        TabView {
            ListeningTab(draft: $draft).tabItem { Label("Listening", systemImage: "ear") }
            ConversationTab(draft: $draft).tabItem { Label("Conversation", systemImage: "bubble.left.and.bubble.right") }
            PhrasesTab(draft: $draft).tabItem { Label("Phrases", systemImage: "text.quote") }
            VoiceTab(draft: $draft).tabItem { Label("Voice", systemImage: "speaker.wave.2") }
            ModelTab(draft: $draft).tabItem { Label("Model", systemImage: "cpu") }
            DiagnosticsTab().tabItem { Label("Diagnostics", systemImage: "stethoscope") }
        }
        .frame(width: 580, height: 620)
        .onAppear {
            draft = engine.settings
            // Emma is a menu bar app, so without this the window opens behind other apps.
            NSApp.activate(ignoringOtherApps: true)
        }
        .onChange(of: draft) {
            pendingApply?.cancel()
            let settings = draft
            pendingApply = Task {
                try? await Task.sleep(for: .milliseconds(400))
                guard !Task.isCancelled else { return }
                engine.applySettings(settings)
            }
        }
        .onDisappear {
            pendingApply?.cancel()
            engine.applySettings(draft)
        }
    }
}

// MARK: - Rows

/// "Title  ───●───  2.0 s", with optional help text under the title.
private struct SliderRow: View {
    let title: String
    @Binding var value: Double
    let range: ClosedRange<Double>
    let step: Double
    var unit = "s"
    var digits = 1
    var help: String?

    var body: some View {
        LabeledContent {
            HStack {
                Slider(value: $value, in: range, step: step)
                Text(String(format: "%.\(digits)f", value) + (unit.isEmpty ? "" : " \(unit)"))
                    .monospacedDigit()
                    .frame(width: 52, alignment: .trailing)
            }
            .frame(width: 260)
        } label: {
            Text(title)
            if let help { Text(help) }
        }
    }
}

private struct HourPicker: View {
    let title: String
    @Binding var hour: Int

    var body: some View {
        Picker(title, selection: $hour) {
            ForEach(0..<24, id: \.self) { Text(String(format: "%02d:00", $0)).tag($0) }
        }
    }
}

// MARK: - Tabs

private struct ListeningTab: View {
    @Binding var draft: Settings

    var body: some View {
        Form {
            Section("Turn-taking") {
                SliderRow(title: "End of speech after", value: $draft.endSilence, range: Settings.endSilenceRange, step: 0.5,
                          help: "Silence that ends your turn. Short values cut you off when you pause to think.")
                SliderRow(title: "No-speech timeout", value: $draft.noSpeechTimeout, range: Settings.noSpeechTimeoutRange, step: 1,
                          help: "How long Emma waits for you to start talking after \"Listen now\".")
                SliderRow(title: "Follow-up window", value: $draft.followUp, range: Settings.followUpRange, step: 1,
                          help: "After Emma speaks, keep listening this long without the wake word. 0 turns it off.")
                SliderRow(title: "Name-only greeting after", value: $draft.bareCallWindow, range: Settings.bareCallRange, step: 0.25,
                          digits: 2, help: "Say just \"Emma\": she greets you after this much silence.")
            }
            Section("Wake word") {
                LabeledContent("Wake word", value: "\u{201C}Emma\u{201D} or \u{201C}Hey Emma\u{201D}")
                Text("Matched as a whole word, so \u{201C}Gemma\u{201D} doesn't wake her. Apple's recognizer is tuned to it, so it isn't editable.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("Noise") {
                Toggle(isOn: $draft.ignoreNoise) {
                    Text("Ignore phantom \u{201C}Thank you.\u{201D}")
                    Text("Whisper invents short phrases from background noise. A \u{201C}thanks\u{201D} right after one of Emma's replies is still answered.")
                }
            }
        }
        .formStyle(.grouped)
    }
}

private struct ConversationTab: View {
    @Binding var draft: Settings

    var body: some View {
        Form {
            Section("Form of address") {
                Picker("Call me", selection: $draft.addressForm) {
                    ForEach(AddressForm.allCases) { Text($0.label).tag($0) }
                }
                if draft.addressForm == .custom {
                    TextField("Word", text: $draft.customAddress, prompt: Text("e.g. boss"))
                }
                Toggle("In greetings", isOn: $draft.addressInGreetings)
                Toggle("In goodbyes", isOn: $draft.addressInGoodbyes)
            }
            Section("Replies") {
                Picker("Reply length", selection: $draft.replyLength) {
                    ForEach(ReplyLength.allCases) { Text($0.label).tag($0) }
                }
                Picker("Jokes", selection: $draft.jokes) {
                    ForEach(JokeFrequency.allCases) { Text($0.label).tag($0) }
                }
                Toggle(isOn: $draft.offerMoreDetail) {
                    Text("Offer more detail")
                    Text("\u{201C}Want the longer version?\u{201D} Off: you ask when you want more.")
                }
                Picker(selection: $draft.emotionalTone) {
                    ForEach(EmotionalTone.allCases) { Text($0.label).tag($0) }
                } label: {
                    Text("Emotional tone")
                    Text("How Emma acknowledges feelings. She never gives emotional advice.")
                }
            }
            Section("Flow") {
                Toggle(isOn: $draft.butlerCheck) {
                    Text("Butler check")
                    Text("After \u{201C}um\u{201D} or \u{201C}oh nothing\u{201D}, ask if there's anything else.")
                }
                Toggle("Thinking fillers", isOn: $draft.fillersEnabled)
                if draft.fillersEnabled {
                    SliderRow(title: "Filler after", value: $draft.fillerDelay, range: Settings.fillerDelayRange, step: 0.5,
                              help: "Silence while waiting for the model before \u{201C}One sec.\u{201D}")
                }
            }
            Section("Greetings") {
                Toggle(isOn: $draft.periodGreeting) {
                    Text("Time-of-day greeting")
                    Text("\u{201C}Hello sir. Good morning.\u{201D} on the first reply of each part of the day.")
                }
                if draft.periodGreeting {
                    HourPicker(title: "Morning from", hour: $draft.morningStart)
                    HourPicker(title: "Afternoon from", hour: $draft.afternoonStart)
                    HourPicker(title: "Evening from", hour: $draft.eveningStart)
                }
            }
        }
        .formStyle(.grouped)
    }
}

private struct PhrasesTab: View {
    @Binding var draft: Settings

    var body: some View {
        Form {
            Section {
                Text("\u{201C}sir\u{201D} in a phrase is replaced by your form of address.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            PhraseListEditor(title: "Thinking fillers", list: $draft.phrases.fillers, defaults: Phrases.fillers)
            PhraseListEditor(title: "Greeting replies", list: $draft.phrases.greetReplies, defaults: Phrases.greetReplies)
            PhraseListEditor(title: "Goodbye replies", list: $draft.phrases.closings, defaults: Phrases.closings)
            PhraseListEditor(title: "Declined-offer replies", list: $draft.phrases.declineAcks, defaults: Phrases.declineAcks)
            Section("Butler question") {
                TextField("Butler question", text: $draft.phrases.anythingElse)
                    .labelsHidden()
                Button("Reset to default") { draft.phrases.anythingElse = Phrases.anythingElse }
            }
            PhraseListEditor(title: "Empathy lines", list: $draft.phrases.empathy, defaults: Phrases.empathy)
        }
        .formStyle(.grouped)
    }
}

/// An editable list of phrases: edit inline, remove with −, add, or reset to the defaults.
private struct PhraseListEditor: View {
    let title: String
    @Binding var list: [String]
    let defaults: [String]

    var body: some View {
        Section(title) {
            ForEach(list.indices, id: \.self) { index in
                HStack {
                    TextField("Phrase", text: Binding(
                        get: { index < list.count ? list[index] : "" },
                        set: { if index < list.count { list[index] = $0 } }
                    ))
                    .labelsHidden()
                    Button {
                        if index < list.count { list.remove(at: index) }
                    } label: {
                        Image(systemName: "minus.circle")
                    }
                    .buttonStyle(.borderless)
                    .disabled(list.count <= 1)
                    .help("Remove")
                }
            }
            HStack {
                Button("Add phrase") { list.append("") }
                Spacer()
                Button("Reset to defaults") { list = defaults }
                    .disabled(list == defaults)
            }
        }
    }
}

private struct VoiceTab: View {
    @EnvironmentObject var engine: AssistantEngine
    @Binding var draft: Settings

    var body: some View {
        Form {
            Section("Speech") {
                Toggle("Speak replies", isOn: $draft.speakReplies)
                SliderRow(title: "Speed", value: $draft.speechSpeed, range: Settings.speechSpeedRange, step: 0.05, unit: "×", digits: 2)
                SliderRow(title: "Pause between sentences", value: $draft.sentencePause, range: Settings.sentencePauseRange,
                          step: 0.05, digits: 2)
                HStack {
                    Spacer()
                    Button("Preview") { engine.previewVoice(draft) }
                        .disabled(engine.phase != .idle)
                }
            }
            Section("Voice") {
                LabeledContent("Voice", value: "Kokoro \u{201C}Emma\u{201D}, British female")
                LabeledContent("Fallback", value: "Apple voice, if Kokoro is unavailable")
            }
        }
        .formStyle(.grouped)
    }
}

private struct ModelTab: View {
    @Binding var draft: Settings
    @State private var modelID = ""
    @State private var showInstructions = false

    var body: some View {
        Form {
            Section("LM Studio") {
                TextField(text: $modelID, prompt: Text(LocalLLMClient.defaultModel)) {
                    Text("Model")
                    Text("As shown by `lms ls`. Press Return to load it.")
                }
                .onSubmit { draft.modelID = modelID }
                SliderRow(title: "Temperature", value: $draft.temperature, range: Settings.temperatureRange, step: 0.05, unit: "",
                          digits: 2, help: "Higher is more varied, and more likely to add quips.")
                Stepper(value: $draft.maxTokens, in: Settings.maxTokensRange, step: 25) {
                    LabeledContent("Max reply length", value: "\(draft.maxTokens) tokens")
                }
            }
            Section("Memory") {
                Stepper(value: $draft.historyMessages, in: Settings.historyRange, step: 2) {
                    LabeledContent("Remember", value: "\(draft.historyMessages) messages")
                }
                SliderRow(title: "New conversation after", value: $draft.conversationResetMinutes,
                          range: Settings.conversationResetRange, step: 1, unit: "min", digits: 0)
            }
            Section("Instructions") {
                Text("Emma's instructions to the model are built from the Conversation settings.")
                    .font(.caption).foregroundStyle(.secondary)
                Button("Show Emma's instructions") { showInstructions = true }
            }
        }
        .formStyle(.grouped)
        .onAppear { modelID = draft.modelID }
        .sheet(isPresented: $showInstructions) {
            VStack(alignment: .leading, spacing: 12) {
                Text("Emma's instructions").font(.headline)
                ScrollView {
                    Text(PersonaPrompt.build(draft))
                        .font(.system(.callout, design: .monospaced))
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                HStack {
                    Spacer()
                    Button("Done") { showInstructions = false }.keyboardShortcut(.defaultAction)
                }
            }
            .padding(20)
            .frame(width: 560, height: 520)
        }
    }
}

private struct DiagnosticsTab: View {
    @EnvironmentObject var engine: AssistantEngine

    var body: some View {
        Form {
            Section("Status") {
                LabeledContent("Language model", value: engine.llmStatus ?? "Ready")
                LabeledContent("Voice (Kokoro)", value: engine.ttsStatus ?? "Ready")
            }
            Section {
                HStack {
                    Button("Open conversation log") { NSWorkspace.shared.open(ConversationLog.url) }
                    Button("Show in Finder") { NSWorkspace.shared.activateFileViewerSelecting([ConversationLog.url]) }
                    Spacer()
                    Button("Clear log", role: .destructive) { ConversationLog.clear() }
                }
                Button("Open voice server log") { NSWorkspace.shared.open(KokoroServer.logURL) }
            } header: {
                Text("Logs")
            } footer: {
                Text("The conversation log records what Emma heard, which rule answered, and what she said. It keeps the newest few hundred lines.")
            }
        }
        .formStyle(.grouped)
    }
}
