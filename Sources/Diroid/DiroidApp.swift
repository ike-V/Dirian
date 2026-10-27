import SwiftUI

@main
struct DiroidApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var prefs = AppPrefs()

    var body: some Scene {
        WindowGroup {
            FileBrowserView()
                .environmentObject(prefs)
                .environment(\.accent, prefs.accent)
                .onAppear { UpdateChecker.shared.checkAtLaunch() }
        }
        Settings {
            SettingsView()
                .environmentObject(prefs)
                .environment(\.accent, prefs.accent)
        }
    }
}
