import CoreText
import SwiftUI
import UIKit

/// Abomsaab (same as sujood.co): bundle font + registration, PostScript name for `Font.custom` / `UIFont`.
enum ArabicTypography {
    private static var cachedPostScriptName: String?

    static var postScriptName: String {
        if let name = cachedPostScriptName { return name }
        let resolved = resolveAndRegisterFont()
        cachedPostScriptName = resolved
        return resolved
    }

    /// Call early so `UIFont(name:)` works before first attributed string build.
    static func ensureRegistered() {
        _ = postScriptName
    }

    private static func resolveAndRegisterFont() -> String {
        let fontURL = Bundle.main.url(forResource: "abomsaab_regular", withExtension: "ttf", subdirectory: "Fonts")
            ?? Bundle.main.url(forResource: "abomsaab_regular", withExtension: "ttf")
        guard let url = fontURL,
              let data = try? Data(contentsOf: url),
              let descriptors = CTFontManagerCreateFontDescriptorsFromData(data as CFData) as? [CTFontDescriptor],
              let first = descriptors.first,
              let psName = CTFontDescriptorCopyAttribute(first, kCTFontNameAttribute) as? String else {
            return fallbackFontName()
        }

        var error: Unmanaged<CFError>?
        CTFontManagerRegisterFontsForURL(url as CFURL, .process, &error)
        return psName.isEmpty ? fallbackFontName() : psName
    }

    private static func fallbackFontName() -> String {
        for name in ["Abomsaab-Regular", "Abomsaab Regular", "Abomsaab", "abomsaab_regular"] where UIFont(name: name, size: 17) != nil {
            return name
        }
        return "Abomsaab-Regular"
    }

    static func uiFont(size: CGFloat) -> UIFont {
        UIFont(name: postScriptName, size: size) ?? .systemFont(ofSize: size)
    }

    static func swiftUIFont(size: CGFloat) -> Font {
        .custom(postScriptName, size: size, relativeTo: .body)
    }
}
