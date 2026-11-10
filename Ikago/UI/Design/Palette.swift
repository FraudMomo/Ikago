import AppKit
import SwiftUI

/// Colors for the window chrome, derived from the active Space's color and light/dark mode.
/// Text, highlights and surfaces are neutral (white or ink at an opacity) so any Space color
/// works; the accent is macOS's own accent color.
/// Equatable so SwiftUI can skip re-rendering a row whose inputs (palette included) didn't change: the palette
/// is rebuilt on every parent render, and an opaque value made every row look changed.
struct Palette: Equatable {
    let isDark: Bool
    /// Liquid Glass on floating surfaces, or flat panels (Settings ▸ Appearance).
    let glass: Bool
    let tint: Color
    let nsTint: NSColor
    let text: Color
    let secondary: Color
    let tertiary: Color
    let hover: Color
    let selected: Color
    let separator: Color
    /// Flat stand-in for glass when glass is off.
    let panel: Color
    let accent: Color
    let nsAccent: NSColor
    /// Behind web pages before they paint.
    let pageBackground: Color

    init(colors: SpaceColors, isDark: Bool, glass: Bool = true) {
        self.isDark = isDark
        self.glass = glass
        nsTint = NSColor(hex: isDark ? colors.dark : colors.light)
        tint = Color(nsColor: nsTint)
        let rgb = nsTint.usingColorSpace(.sRGB) ?? nsTint
        let darkSurface = 0.2126 * rgb.redComponent + 0.7152 * rgb.greenComponent + 0.0722 * rgb.blueComponent < 0.5
        let ink = darkSurface ? Color.white : Color.black
        text = ink.opacity(isDark ? 0.92 : 0.86)
        secondary = ink.opacity(isDark ? 0.55 : 0.5)
        tertiary = ink.opacity(isDark ? 0.3 : 0.26)
        hover = ink.opacity(isDark ? 0.06 : 0.045)
        selected = darkSurface ? Color.white.opacity(0.16) : Color.white.opacity(0.65)
        separator = ink.opacity(isDark ? 0.09 : 0.07)
        panel = Color(nsColor: nsTint.blended(withFraction: 0.06, of: darkSurface ? .black : .white) ?? nsTint)
        nsAccent = .controlAccentColor
        accent = Color(nsColor: .controlAccentColor)
        pageBackground = isDark ? Color(hex: 0x1C1C1E) : .white
    }
}

extension Palette {
    /// The same palette drawn over a page-colored bar: ink flips to whatever reads on `bar`.
    init(_ base: Palette, over bar: NSColor, panelIsSurface: Bool = false) {
        let c = bar.usingColorSpace(.sRGB) ?? bar
        let luminance = 0.2126 * c.redComponent + 0.7152 * c.greenComponent + 0.0722 * c.blueComponent
        let dark = luminance < 0.5
        let ink = dark ? Color.white : Color.black
        isDark = dark
        glass = base.glass
        nsTint = c
        tint = Color(nsColor: c)
        text = ink.opacity(dark ? 0.92 : 0.86)
        secondary = ink.opacity(dark ? 0.6 : 0.55)
        tertiary = ink.opacity(dark ? 0.32 : 0.28)
        hover = ink.opacity(dark ? 0.1 : 0.07)
        selected = dark ? Color.white.opacity(0.16) : Color.white.opacity(0.55)
        separator = ink.opacity(dark ? 0.12 : 0.1)
        panel = Color(nsColor: panelIsSurface ? c : c.blended(withFraction: 0.12, of: dark ? .white : .black) ?? c)
        accent = base.accent
        nsAccent = base.nsAccent
        pageBackground = base.pageBackground
    }
}

extension View {
    /// A floating surface: Liquid Glass, or a flat panel when glass is turned off.
    @ViewBuilder
    func surface<S: Shape>(_ shape: S, _ colors: Palette, translucentSidebar: Bool = false, tintOpacity: Double = 0.65) -> some View {
        if translucentSidebar {
            modifier(SidebarMaterialSurface(shape: shape, colors: colors))
        } else if colors.glass {
            glassEffect(.regular.tint(colors.tint.opacity(tintOpacity)), in: shape)
        } else {
            background(shape.fill(colors.panel))
                .overlay(shape.stroke(colors.separator, lineWidth: 0.5))
        }
    }
}

extension Color {
    init(hex: UInt32) {
        self.init(.sRGB, red: Double((hex >> 16) & 0xff) / 255, green: Double((hex >> 8) & 0xff) / 255,
                  blue: Double(hex & 0xff) / 255)
    }

    /// 0xRRGGBB for storing a color picked in a ColorPicker.
    var hexValue: UInt32 {
        let ns = NSColor(self).usingColorSpace(.sRGB) ?? .gray
        return UInt32(ns.redComponent * 255) << 16 | UInt32(ns.greenComponent * 255) << 8 | UInt32(ns.blueComponent * 255)
    }
}

extension NSColor {
    convenience init(hex: UInt32) {
        self.init(srgbRed: CGFloat((hex >> 16) & 0xff) / 255, green: CGFloat((hex >> 8) & 0xff) / 255,
                  blue: CGFloat(hex & 0xff) / 255, alpha: 1)
    }
}

/// Shared motion: one spring for everything that moves, so the app feels consistent.
extension Animation {
    static let ikago = Animation.spring(duration: 0.2, bounce: 0)
    static let ikagoQuick = Animation.spring(duration: 0.12, bounce: 0)
    /// A sidebar group opening or closing: long enough to follow the rows below as they move.
    static let groupDisclosure = Animation.smooth(duration: groupDisclosureDuration)
    /// The sidebar list scrolls along with a closing group on this same spring (`ListScrollView.follow`).
    static let groupDisclosureDuration = 0.26
}
