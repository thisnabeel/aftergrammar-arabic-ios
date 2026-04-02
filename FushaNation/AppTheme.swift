import SwiftUI

extension Color {
    init(hex: UInt32, alpha: Double = 1) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xff) / 255,
            green: Double((hex >> 8) & 0xff) / 255,
            blue: Double(hex & 0xff) / 255,
            opacity: alpha
        )
    }
}

enum AppTheme {
    /// Main page background (warm peach / salmon)
    static let background = Color(hex: 0xF5E1D7)
    /// Top banner / nav bar (soft pink)
    static let bannerPink = Color(hex: 0xF5CCD4)
    /// Search-field style neutral
    static let searchFieldGray = Color(hex: 0xEFEFEF)
    /// Accent green (map / key actions on web)
    static let forestGreen = Color(hex: 0x004D33)
    /// Active tab / links (vibrant blue)
    static let accentBlue = Color(hex: 0x0000FF)
    /// “Test”-style accent
    static let accentAmber = Color(hex: 0xFFC107)

    static let readerCard = Color.white
    static let readerCardStroke = Color.black.opacity(0.06)

    static let textPrimary = Color(white: 0.12)
    static let textSecondary = Color(white: 0.42)

    /// Genius-style hint highlight
    static let hintHighlight = Color(hex: 0xFFF9C4)
    /// Darker accent used for collapsed hint underline
    static let hintUnderline = hintHighlight.opacity(0.95)
    /// Expanded hint callout background
    static let hintExpandedFill = hintHighlight

    static let listRow = Color.white.opacity(0.55)
}
