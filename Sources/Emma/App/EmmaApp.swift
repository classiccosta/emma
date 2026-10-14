import SwiftUI

@main
struct EmmaApp: App {
    @StateObject private var engine = AssistantEngine()

    var body: some Scene {
        MenuBarExtra {
            PanelView().environmentObject(engine)
        } label: {
            Image(systemName: engine.phase.menuBarSymbol)
        }
        .menuBarExtraStyle(.window)

        SwiftUI.Settings {
            SettingsWindow().environmentObject(engine)
        }
    }
}
