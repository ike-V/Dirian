import AppKit

/// Asks GitHub for the latest Dirian release and tells the user when it's newer than this one.
@MainActor
final class UpdateChecker {
    static let shared = UpdateChecker()

    private static let upgradeCommand = "brew upgrade --cask dirian"
    private static let latestReleaseURL = URL(string: "https://api.github.com/repos/ike-V/Dirian/releases/latest")!
    private static let lastCheckKey = "lastUpdateCheck"
    private static let announcedKey = "announcedUpdateVersion"

    private let defaults = UserDefaults.standard
    private var launchCheckDone = false

    private var currentVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0"
    }

    /// At launch: one quiet check a day, and each new version is announced once.
    func checkAtLaunch() {
        guard !launchCheckDone, defaults.object(forKey: AppPrefs.checkForUpdatesKey) as? Bool ?? true else { return }
        launchCheckDone = true
        if let last = defaults.object(forKey: Self.lastCheckKey) as? Date, Date().timeIntervalSince(last) < 86_400 {
            return
        }
        Task { await check(manual: false) }
    }

    /// From the menu: always shows a result.
    func checkNow() {
        Task { await check(manual: true) }
    }

    private func check(manual: Bool) async {
        do {
            let latest = try await Self.fetchLatest()
            defaults.set(Date(), forKey: Self.lastCheckKey)
            if Self.isNewer(latest.version, than: currentVersion) {
                guard manual || defaults.string(forKey: Self.announcedKey) != latest.version else { return }
                defaults.set(latest.version, forKey: Self.announcedKey)
                showAvailable(version: latest.version, url: latest.url)
            } else if manual {
                show("Dirian is up to date", "You have the latest version, \(currentVersion).")
            }
        } catch {
            if manual {
                show("Couldn't check for updates", "Dirian couldn't reach GitHub. Check your internet connection and try again.")
            }
        }
    }

    private struct Release: Decodable {
        let tagName: String
        let htmlUrl: URL
    }

    private static func fetchLatest() async throws -> (version: String, url: URL) {
        var request = URLRequest(url: latestReleaseURL, timeoutInterval: 10)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        let (data, response) = try await URLSession.shared.data(for: request)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw URLError(.badServerResponse) }
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        let release = try decoder.decode(Release.self, from: data)
        return (release.tagName.trimmingCharacters(in: CharacterSet(charactersIn: "vV")), release.htmlUrl)
    }

    /// Compares dotted version numbers part by part ("0.10.0" is newer than "0.9.2").
    static func isNewer(_ a: String, than b: String) -> Bool {
        let x = a.split(separator: ".").map { Int($0) ?? 0 }
        let y = b.split(separator: ".").map { Int($0) ?? 0 }
        for i in 0..<max(x.count, y.count) {
            let p = i < x.count ? x[i] : 0, q = i < y.count ? y[i] : 0
            if p != q { return p > q }
        }
        return false
    }

    private func showAvailable(version: String, url: URL) {
        let alert = NSAlert()
        alert.messageText = "Dirian \(version) is available"
        alert.informativeText = "You have \(currentVersion). If you installed with Homebrew, run this in Terminal:\n\n\(Self.upgradeCommand)\n\nOtherwise, download it from the release page."
        alert.addButton(withTitle: "View Release")
        alert.addButton(withTitle: "Copy Command")
        alert.addButton(withTitle: "Later")
        NSApp.activate(ignoringOtherApps: true)
        switch alert.runModal() {
        case .alertFirstButtonReturn:
            NSWorkspace.shared.open(url)
        case .alertSecondButtonReturn:
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(Self.upgradeCommand, forType: .string)
        default:
            break
        }
    }

    private func show(_ title: String, _ detail: String) {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = detail
        NSApp.activate(ignoringOtherApps: true)
        alert.runModal()
    }
}
