import SwiftUI

/// The colors the interface can be tinted with: Finder's tag colors, with Android's green as the default.
enum AccentChoice: String, CaseIterable, Identifiable {
    case red, orange, yellow, green, blue, purple, gray

    var id: String { rawValue }
    var name: String { rawValue.capitalized }

    /// "RRGGBB". Green is Android's brand green (#3DDC84).
    private var hex: UInt32 {
        switch self {
        case .red: 0xFF453A
        case .orange: 0xFF9F0A
        case .yellow: 0xFFD60A
        case .green: 0x3DDC84
        case .blue: 0x0A84FF
        case .purple: 0xBF5AF2
        case .gray: 0x98989D
        }
    }

    /// "#RRGGBB", as sent to Dirian for Android.
    var hexString: String { String(format: "#%06X", hex) }

    private var components: (red: Double, green: Double, blue: Double) {
        (Double((hex >> 16) & 0xFF) / 255, Double((hex >> 8) & 0xFF) / 255, Double(hex & 0xFF) / 255)
    }

    var color: Color {
        let c = components
        return Color(red: c.red, green: c.green, blue: c.blue)
    }

    /// Folder icon fill: lighter at the top, deeper at the bottom, around the accent.
    var folderGradient: LinearGradient {
        if self == .green {
            return LinearGradient(
                colors: [Color(red: 0x7C / 255.0, green: 0xEE / 255.0, blue: 0xAD / 255.0),
                         Color(red: 0x2B / 255.0, green: 0xBD / 255.0, blue: 0x6E / 255.0)],
                startPoint: .top, endPoint: .bottom)
        }
        let c = components
        return LinearGradient(
            colors: [Color(red: c.red + (1 - c.red) * 0.4, green: c.green + (1 - c.green) * 0.4, blue: c.blue + (1 - c.blue) * 0.4),
                     Color(red: c.red * 0.82, green: c.green * 0.82, blue: c.blue * 0.82)],
            startPoint: .top, endPoint: .bottom)
    }
}

private struct AccentKey: EnvironmentKey {
    static let defaultValue = AccentChoice.green
}

extension EnvironmentValues {
    /// The accent chosen in Settings; views read it instead of a fixed color so they recolor live.
    var accent: AccentChoice {
        get { self[AccentKey.self] }
        set { self[AccentKey.self] = newValue }
    }
}
