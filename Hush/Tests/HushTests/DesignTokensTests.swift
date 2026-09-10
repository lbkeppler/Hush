import SwiftUI
import Testing
@testable import Hush

@Suite("Design Tokens")
struct DesignTokensTests {
    /// Extracts sRGB components from a `Color` via `NSColor`.
    private func rgb(_ color: Color) -> (Double, Double, Double) {
        let nsColor = NSColor(color).usingColorSpace(.deviceRGB) ?? NSColor(color)
        return (Double(nsColor.redComponent), Double(nsColor.greenComponent), Double(nsColor.blueComponent))
    }

    @Test("hex initializer produces expected RGB components")
    func hexInitializer() {
        let (r, g, b) = rgb(Color(hex: 0xE4C39A))
        #expect(abs(r - 0.894) < 0.01)
        #expect(abs(g - 0.765) < 0.01)
        #expect(abs(b - 0.604) < 0.01)
    }

    @Test("accent color differs between dark and light schemes")
    func accentDiffersByScheme() {
        #expect(DT.accent(.dark) != DT.accent(.light))
    }
}
