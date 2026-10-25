import Foundation

/// What to tell the user to do next so Dirian can reach adb: install Homebrew, install adb, or start its server.
enum AdbSetup {
    struct Step {
        let title: String
        let detail: String
        let command: String
    }

    private static let studioAdb = NSHomeDirectory() + "/Library/Android/sdk/platform-tools/adb"
    private static let adbPaths = ["/opt/homebrew/bin/adb", "/usr/local/bin/adb", studioAdb]
    private static let brewPaths = ["/opt/homebrew/bin/brew", "/usr/local/bin/brew"]

    /// Homebrew's own installer; it asks for a password, so nothing else is pasted with it.
    static let homebrewInstall = "/bin/bash -c \"$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)\""

    static func step(adbPath: String?, brewInstalled: Bool) -> Step {
        if let adbPath {
            // Android Studio's adb isn't on the shell's PATH, so name it in full.
            let command = adbPath == studioAdb ? "~/Library/Android/sdk/platform-tools/adb start-server" : "adb start-server"
            return Step(title: "The adb server isn't running",
                        detail: "adb is installed but its server isn't running. Run this in Terminal.", command: command)
        }
        if brewInstalled {
            return Step(title: "Dirian needs adb",
                        detail: "Dirian reads your phone through adb, the Android Debug Bridge. Install it with Homebrew by running this in Terminal.",
                        command: "brew install --cask android-platform-tools")
        }
        return Step(title: "Install Homebrew first",
                    detail: "Dirian reads your phone through adb, the Android Debug Bridge, which installs with Homebrew. Run this in Terminal and follow its prompts. The next step shows up afterwards.",
                    command: homebrewInstall)
    }

    /// The next step for this Mac as it is now.
    static var current: Step {
        step(adbPath: adbPaths.first { FileManager.default.isExecutableFile(atPath: $0) },
             brewInstalled: brewPaths.contains { FileManager.default.isExecutableFile(atPath: $0) })
    }
}
