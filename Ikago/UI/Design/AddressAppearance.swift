import AppKit
import SwiftUI

/// Integrated address entry uses an opaque browser surface, independently of floating glass.
enum AddressAppearance {
    static func background(isDark: Bool) -> Color { Color(nsColor: nsBackground(isDark: isDark)) }
    static func nsBackground(isDark: Bool) -> NSColor { NSColor(hex: isDark ? 0x292A2D : 0xFFFFFF) }
    static func palette(isDark: Bool) -> Palette {
        Palette(Palette(colors: .standard, isDark: isDark, glass: false),
                over: nsBackground(isDark: isDark), panelIsSurface: true)
    }
}
