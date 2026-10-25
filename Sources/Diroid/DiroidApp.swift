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
        .commands {
            CommandGroup(after: .appInfo) {
                Button("Check for Updates…") { UpdateChecker.shared.checkNow() }
                Button("Setup Guide…") { SetupGuideWindow.show() }
            }
        }
        Settings {
            SettingsView()
                .environmentObject(prefs)
                .environment(\.accent, prefs.accent)
        }
    }
}
