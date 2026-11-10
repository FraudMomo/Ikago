import AppKit
import SwiftUI

/// Native frosted sidebar material, independently selectable from Liquid Glass.
struct SidebarMaterialSurface<S: Shape>: ViewModifier {
    let shape: S
    let colors: Palette
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    func body(content: Content) -> some View {
        content.background {
            if reduceTransparency {
                shape.fill(colors.panel)
            } else {
                SidebarVisualEffect(tint: colors.nsTint)
                    .overlay(shape.fill(colors.tint.opacity(0.22)))
                    .clipShape(shape)
                    .allowsHitTesting(false)
            }
        }
        .overlay(shape.stroke(colors.separator, lineWidth: 0.5).allowsHitTesting(false))
    }
}

struct SidebarVisualEffect: FillingViewRepresentable {
    let tint: NSColor
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = .sidebar
        view.blendingMode = .behindWindow
        view.state = .followsWindowActiveState
        return view
    }
    func updateNSView(_ view: NSVisualEffectView, context: Context) {
        let rgb = tint.usingColorSpace(.sRGB) ?? tint
        let dark = 0.2126 * rgb.redComponent + 0.7152 * rgb.greenComponent + 0.0722 * rgb.blueComponent < 0.5
        view.appearance = NSAppearance(named: dark ? .vibrantDark : .vibrantLight)
    }
}
