extension AssistantEngine {
    /// What Emma is doing, shown by the orb, the label and the menu bar icon (see `Phase+Display.swift`).
    enum Phase: Equatable {
        case loading(String)
        case idle
        case listening
        case transcribing
        case thinking
        case speaking
        case failed(String)
    }
}
