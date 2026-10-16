import SwiftUI

extension Color {
    /// Android brand green (#3DDC84), the app's accent color.
    static let androidGreen = Color(red: 0x3D / 255.0, green: 0xDC / 255.0, blue: 0x84 / 255.0)
}

extension LinearGradient {
    /// Folder icon fill: lighter at the top, deeper at the bottom, around the brand green.
    static let androidFolder = LinearGradient(
        colors: [
            Color(red: 0x7C / 255.0, green: 0xEE / 255.0, blue: 0xAD / 255.0),
            Color(red: 0x2B / 255.0, green: 0xBD / 255.0, blue: 0x6E / 255.0),
        ],
        startPoint: .top, endPoint: .bottom)
}
