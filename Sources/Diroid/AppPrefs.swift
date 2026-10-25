import SwiftUI

/// Settings shared by the browser window and the Settings window, saved in UserDefaults.
@MainActor
final class AppPrefs: ObservableObject {
    private enum Key {
        static let accent = "accentColor"
        static let appIcon = "appIcon"
        static let hiddenShortcuts = "hiddenSidebarShortcuts"
        static let hiddenFolders = "hiddenSidebarFolders"
        static let knownFolders = "knownSidebarFolders"
    }

    static let checkForUpdatesKey = "checkForUpdates"

    /// The sidebar shortcuts that can be hidden.
    static let shortcuts: [(name: String, symbol: String)] =
        FileCategory.allCases.map { ($0.rawValue, $0.symbol) } + [("Downloads", "arrow.down.circle")]

    static var savedAppIcon: AppIconChoice {
        UserDefaults.standard.string(forKey: Key.appIcon).flatMap(AppIconChoice.init(rawValue:)) ?? .standard
    }

    private let defaults = UserDefaults.standard

    /// The saved accent color, for windows that don't share the prefs object.
    static var savedAccent: AccentChoice {
        UserDefaults.standard.string(forKey: Key.accent).flatMap(AccentChoice.init(rawValue:)) ?? .green
    }

    @Published var accent: AccentChoice {
        didSet { defaults.set(accent.rawValue, forKey: Key.accent) }
    }
    @Published var appIcon: AppIconChoice {
        didSet {
            defaults.set(appIcon.rawValue, forKey: Key.appIcon)
            appIcon.apply()
        }
    }
    @Published var checkForUpdates: Bool {
        didSet { defaults.set(checkForUpdates, forKey: Self.checkForUpdatesKey) }
    }
    @Published var hiddenShortcuts: Set<String> {
        didSet { defaults.set(hiddenShortcuts.sorted(), forKey: Key.hiddenShortcuts) }
    }
    /// Top-level device folders hidden from the sidebar, by name; they stay reachable by browsing.
    @Published var hiddenFolders: Set<String> {
        didSet { defaults.set(hiddenFolders.sorted(), forKey: Key.hiddenFolders) }
    }
    /// Every top-level device folder name seen so far, so Settings can list them without a device.
    @Published private(set) var knownFolders: [String]

    init() {
        accent = Self.savedAccent
        appIcon = Self.savedAppIcon
        checkForUpdates = defaults.object(forKey: Self.checkForUpdatesKey) as? Bool ?? true
        hiddenShortcuts = Set(defaults.stringArray(forKey: Key.hiddenShortcuts) ?? [])
        hiddenFolders = Set(defaults.stringArray(forKey: Key.hiddenFolders) ?? [])
        knownFolders = defaults.stringArray(forKey: Key.knownFolders) ?? []
    }

    func noteFolders(_ names: [String]) {
        let merged = Set(knownFolders).union(names)
        guard merged.count != knownFolders.count else { return }
        knownFolders = merged.sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
        defaults.set(knownFolders, forKey: Key.knownFolders)
    }
}
