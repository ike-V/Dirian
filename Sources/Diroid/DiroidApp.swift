import SwiftUI

@main
struct DiroidApp: App {
    @StateObject private var prefs = AppPrefs()

    var body: some Scene {
        WindowGroup {
            FileBrowserView()
                .environmentObject(prefs)
                .environment(\.accent, prefs.accent)
                .onAppear { UpdateChecker.shared.checkAtLaunch() }
        }
        .commands {
            CommandGroup(after: .appInfo) {
                Button("Check for Updates…") { UpdateChecker.shared.checkNow() }
            }
        }
        Settings {
            SettingsView()
                .environmentObject(prefs)
                .environment(\.accent, prefs.accent)
        }
    }
}
