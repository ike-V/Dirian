import AppKit

/// The icon Dirian shows in the Dock while it runs. Finder and Launchpad keep the bundle's icon.
enum AppIconChoice: String, CaseIterable, Identifiable {
    case standard, classic

    var id: String { rawValue }
    var name: String { self == .standard ? "Outline" : "Classic" }

    /// The icon's artwork for light or dark mode: the bundle's own icon, or an image in Resources.
    func image(dark: Bool) -> NSImage? {
        switch self {
        case .standard: NSWorkspace.shared.icon(forFile: Bundle.main.bundlePath)
        case .classic: Bundle.main.url(forResource: dark ? "DirianClassicDark" : "DirianClassic", withExtension: "png").flatMap { NSImage(contentsOf: $0) }
        }
    }

    /// Shows this icon in the Dock and keeps it matching the system's light or dark mode; the standard icon restores the bundle's.
    @MainActor func apply() {
        appearanceObserver = nil
        guard self != .standard else {
            NSApp.applicationIconImage = nil
            return
        }
        let update = { @MainActor in NSApp.applicationIconImage = self.image(dark: NSApp.effectiveAppearance.isDark) }
        update()
        appearanceObserver = NSApp.observe(\.effectiveAppearance) { _, _ in Task { @MainActor in update() } }
    }
}

@MainActor private var appearanceObserver: NSKeyValueObservation?

extension NSAppearance {
    var isDark: Bool { bestMatch(from: [.darkAqua, .aqua]) == .darkAqua }
}
