import SwiftUI

@main
struct DiroidApp: App {
    @StateObject private var prefs = AppPrefs()

    var body: some Scene {
        WindowGroup {
            FileBrowserView()
                .environmentObject(prefs)
                .environment(\.accent, prefs.accent)
        }
        Settings {
            SettingsView()
                .environmentObject(prefs)
                .environment(\.accent, prefs.accent)
        }
    }
}
