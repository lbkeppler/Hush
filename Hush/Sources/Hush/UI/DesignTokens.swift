import SwiftUI
#if canImport(AppKit)
import AppKit
#endif

extension Color {
    /// Creates a `Color` from a packed RGB hex value, e.g. `0xE4C39A`.
    init(hex: UInt) {
        let r = Double((hex & 0xFF0000) >> 16) / 255
        let g = Double((hex & 0x00FF00) >> 8) / 255
        let b = Double(hex & 0x0000FF) / 255
        self.init(red: r, green: g, blue: b)
    }
}

/// Design tokens for the Hush app: theme-aware colors and font helpers.
enum DT {
    // MARK: - Dark palette

    private static let darkInk = Color(hex: 0x12151A)
    private static let darkSurface = Color(hex: 0x191D24)
    private static let darkHairline = Color(hex: 0x232A34)
    private static let darkText = Color(hex: 0xE8ECF1)
    private static let darkMuted = Color(hex: 0x8B95A1)
    private static let darkAccent = Color(hex: 0xE4C39A)

    // MARK: - Light palette

    private static let lightBase = Color(hex: 0xECEFF3)
    private static let lightSurface = Color(hex: 0xFFFFFF)
    private static let lightHairline = Color(hex: 0xDDE3EA)
    private static let lightText = Color(hex: 0x1B2027)
    private static let lightMuted = Color(hex: 0x6B7480)
    private static let lightAccent = Color(hex: 0xB8895A)

    // MARK: - Theme-aware accessors

    static func ink(_ scheme: ColorScheme) -> Color {
        scheme == .dark ? darkInk : lightBase
    }

    static func surface(_ scheme: ColorScheme) -> Color {
        scheme == .dark ? darkSurface : lightSurface
    }

    static func hairline(_ scheme: ColorScheme) -> Color {
        scheme == .dark ? darkHairline : lightHairline
    }

    static func text(_ scheme: ColorScheme) -> Color {
        scheme == .dark ? darkText : lightText
    }

    static func muted(_ scheme: ColorScheme) -> Color {
        scheme == .dark ? darkMuted : lightMuted
    }

    static func accent(_ scheme: ColorScheme) -> Color {
        scheme == .dark ? darkAccent : lightAccent
    }

    // MARK: - Fonts

    static func display(_ size: CGFloat) -> Font {
        #if canImport(AppKit)
        if NSFont(name: "Space Grotesk", size: size) != nil {
            return .custom("Space Grotesk", size: size)
        }
        #endif
        return .system(size: size, weight: .medium, design: .default)
    }

    static func body(_ size: CGFloat) -> Font {
        .system(size: size)
    }
}
