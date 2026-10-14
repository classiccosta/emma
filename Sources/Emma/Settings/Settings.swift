import Foundation

/// How Emma addresses the user in greetings and goodbyes.
enum AddressForm: String, Codable, CaseIterable, Identifiable {
    case sir, madam, custom, none
    var id: Self { self }
    var label: String {
        switch self {
        case .sir: return "Sir"
        case .madam: return "Madam"
        case .custom: return "Custom"
        case .none: return "None"
        }
    }
}

enum ReplyLength: String, Codable, CaseIterable, Identifiable {
    case oneSentence, upToTwo, shortParagraph
    var id: Self { self }
    var label: String {
        switch self {
        case .oneSentence: return "One sentence"
        case .upToTwo: return "Up to two sentences"
        case .shortParagraph: return "Short paragraph"
        }
    }
}

enum JokeFrequency: String, Codable, CaseIterable, Identifiable {
    case never, rarely, sometimes
    var id: Self { self }
    var label: String { rawValue.capitalized }
}

/// How Emma responds when the user shares a feeling. She never gives emotional advice, whatever the tone.
enum EmotionalTone: String, Codable, CaseIterable, Identifiable {
    case warm, neutral, brief
    var id: Self { self }
    var label: String { rawValue.capitalized }
}

/// The editable stock phrases. "sir" in them is replaced by the chosen form of address.
struct PhraseSettings: Codable, Equatable {
    var fillers = Phrases.fillers
    var greetReplies = Phrases.greetReplies
    var closings = Phrases.closings
    var declineAcks = Phrases.declineAcks
    var anythingElse = Phrases.anythingElse
    var empathy = Phrases.empathy

    init() {}

    /// Blank entries dropped, and an emptied list refilled with its defaults.
    var normalized: PhraseSettings {
        func clean(_ list: [String], _ fallback: [String]) -> [String] {
            let kept = list.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
            return kept.isEmpty ? fallback : kept
        }
        var phrases = self
        phrases.fillers = clean(fillers, Phrases.fillers)
        phrases.greetReplies = clean(greetReplies, Phrases.greetReplies)
        phrases.closings = clean(closings, Phrases.closings)
        phrases.declineAcks = clean(declineAcks, Phrases.declineAcks)
        phrases.empathy = clean(empathy, Phrases.empathy)
        let question = anythingElse.trimmingCharacters(in: .whitespacesAndNewlines)
        phrases.anythingElse = question.isEmpty ? Phrases.anythingElse : question
        return phrases
    }

    var all: [String] { fillers + greetReplies + closings + declineAcks + empathy + [anythingElse] }
}

/// User-adjustable settings, edited in the Settings window and applied immediately.
struct Settings: Codable, Equatable {
    static let endSilenceRange: ClosedRange<Double> = 0.5...10
    static let noSpeechTimeoutRange: ClosedRange<Double> = 1...30
    static let followUpRange: ClosedRange<Double> = 0...15
    static let bareCallRange: ClosedRange<Double> = 0.5...3
    static let speechSpeedRange: ClosedRange<Double> = 0.8...1.4
    static let sentencePauseRange: ClosedRange<Double> = 0.1...0.6
    static let fillerDelayRange: ClosedRange<Double> = 1...5
    static let temperatureRange: ClosedRange<Double> = 0...1
    static let maxTokensRange: ClosedRange<Int> = 50...400
    static let historyRange: ClosedRange<Int> = 10...40
    static let conversationResetRange: ClosedRange<Double> = 1...30

    // Listening
    /// Silence after speech that ends an utterance.
    var endSilence = 3.0
    /// How long to wait for speech after the wake word.
    var noSpeechTimeout = 5.0
    /// How long to keep listening for a reply after Emma speaks, without the wake word. 0 turns it off.
    var followUp = 6.0
    /// After the wake word, this long without more speech means a bare "Emma": she greets at once.
    var bareCallWindow = 1.0
    /// Drop Whisper's phantom "Thank you." and the like when there was no recent reply.
    var ignoreNoise = true

    // Conversation
    var addressForm = AddressForm.sir
    var customAddress = ""
    var addressInGreetings = true
    var addressInGoodbyes = true
    var replyLength = ReplyLength.oneSentence
    var jokes = JokeFrequency.rarely
    /// Allow "Want more detail?" offers. Off by default: the user asks when they want more.
    var offerMoreDetail = false
    var emotionalTone = EmotionalTone.warm
    /// Ask "Is there anything else I can do for you, sir?" after an inconclusive answer.
    var butlerCheck = true
    var fillersEnabled = true
    /// Silence while waiting for the model before a filler like "One sec." is said.
    var fillerDelay = 2.0
    var periodGreeting = true
    var morningStart = 5
    var afternoonStart = 12
    var eveningStart = 18
    var phrases = PhraseSettings()

    // Voice
    /// Speak replies aloud. When off, replies are only shown.
    var speakReplies = true
    /// Slightly under 1 sounds more relaxed and conversational.
    var speechSpeed = 0.95
    /// Silence added after each spoken sentence.
    var sentencePause = 0.3

    // Model
    /// LM Studio model identifier.
    var modelID = LocalLLMClient.defaultModel
    /// Lower than LM Studio's default: at 0.7 the model kept tacking quips onto good answers.
    var temperature = 0.5
    var maxTokens = 200
    /// Most messages kept in the conversation history.
    var historyMessages = 20
    /// A new conversation starts after this many minutes without a reply.
    var conversationResetMinutes = 10.0

    init() {}

    /// The word Emma uses, or nil for "None".
    var addressWord: String? {
        switch addressForm {
        case .sir: return "sir"
        case .madam: return "madam"
        case .custom:
            let word = customAddress.trimmingCharacters(in: .whitespacesAndNewlines)
            return word.isEmpty ? nil : word
        case .none: return nil
        }
    }

    /// Ranges enforced and blank text replaced with defaults.
    var normalized: Settings {
        var settings = self
        settings.endSilence = endSilence.clamped(to: Self.endSilenceRange)
        settings.noSpeechTimeout = noSpeechTimeout.clamped(to: Self.noSpeechTimeoutRange)
        settings.followUp = followUp.clamped(to: Self.followUpRange)
        settings.bareCallWindow = bareCallWindow.clamped(to: Self.bareCallRange)
        settings.speechSpeed = speechSpeed.clamped(to: Self.speechSpeedRange)
        settings.sentencePause = sentencePause.clamped(to: Self.sentencePauseRange)
        settings.fillerDelay = fillerDelay.clamped(to: Self.fillerDelayRange)
        settings.temperature = temperature.clamped(to: Self.temperatureRange)
        settings.maxTokens = min(max(maxTokens, Self.maxTokensRange.lowerBound), Self.maxTokensRange.upperBound)
        settings.historyMessages = min(max(historyMessages, Self.historyRange.lowerBound), Self.historyRange.upperBound)
        settings.conversationResetMinutes = conversationResetMinutes.clamped(to: Self.conversationResetRange)
        settings.morningStart = min(max(morningStart, 0), 23)
        settings.afternoonStart = min(max(afternoonStart, settings.morningStart + 1), 23)
        settings.eveningStart = min(max(eveningStart, settings.afternoonStart + 1), 24)
        settings.modelID = modelID.trimmingCharacters(in: .whitespacesAndNewlines)
        if settings.modelID.isEmpty { settings.modelID = LocalLLMClient.defaultModel }
        settings.phrases = phrases.normalized
        return settings
    }

    private static let key = "settings.v1"

    /// The app's defaults domain before it was renamed from Jarvis to Emma.
    private static let legacyDomain = "com.diogocosta.jarvis"

    /// Saved settings; else those saved under the app's old name; else defaults that keep
    /// values from the older one-key-per-setting format.
    static func load(from defaults: UserDefaults = .standard) -> Settings {
        if let data = defaults.data(forKey: key), let settings = try? decode(data) {
            return settings.normalized
        }
        if defaults == .standard, let legacy = UserDefaults(suiteName: legacyDomain), legacy.dictionaryRepresentation().keys.contains(key) {
            let settings = load(from: legacy)
            settings.save(to: defaults)
            return settings
        }
        var settings = Settings()
        if defaults.double(forKey: "endSilenceSeconds") > 0 { settings.endSilence = defaults.double(forKey: "endSilenceSeconds") }
        if defaults.double(forKey: "noSpeechTimeoutSeconds") > 0 {
            settings.noSpeechTimeout = defaults.double(forKey: "noSpeechTimeoutSeconds")
        }
        if let speak = defaults.object(forKey: "speakReplies") as? Bool { settings.speakReplies = speak }
        if let model = defaults.string(forKey: "llmModel") { settings.modelID = model }
        return settings.normalized
    }

    func save(to defaults: UserDefaults = .standard) {
        if let data = try? JSONEncoder().encode(self) { defaults.set(data, forKey: Self.key) }
    }
}

extension Settings {
    /// Decodes saved settings on top of the defaults, so fields an older build didn't save start at their
    /// defaults and unknown fields are ignored. No per-field decoding code to keep in sync.
    static func decode(_ data: Data) throws -> Settings {
        let defaults = try JSONSerialization.jsonObject(with: JSONEncoder().encode(Settings())) as? [String: Any] ?? [:]
        let saved = try JSONSerialization.jsonObject(with: data) as? [String: Any] ?? [:]
        let merged = overlay(saved, on: defaults)
        return try JSONDecoder().decode(Settings.self, from: JSONSerialization.data(withJSONObject: merged))
    }

    private static func overlay(_ saved: [String: Any], on base: [String: Any]) -> [String: Any] {
        var result = base
        for (key, value) in saved where base[key] != nil {
            if let nested = value as? [String: Any], let baseNested = base[key] as? [String: Any] {
                result[key] = overlay(nested, on: baseNested)
            } else {
                result[key] = value
            }
        }
        return result
    }
}

extension Double {
    func clamped(to range: ClosedRange<Double>) -> Double {
        Swift.min(Swift.max(self, range.lowerBound), range.upperBound)
    }
}
