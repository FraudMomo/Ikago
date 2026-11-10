import SwiftUI

extension EnvironmentValues {
    /// False when the user turned glass off in Settings ▸ Appearance.
    @Entry var usesGlass = true
    /// The palette of the page a section sits on, so its cards can use `.surface`.
    @Entry var pagePalette: Palette? = nil
    /// Inside a private window: favicons stay in memory.
    @Entry var privateBrowsing = false
    /// Inside a `GlassControlGroup`: the capsule is the glass, so a control adds none of its own.
    @Entry var inGlassGroup = false
}

extension View {
    /// Liquid Glass for every button below this view that doesn't choose its own style.
    /// One style that decides inside: an `if` here would rebuild everything below it when the setting
    /// changes, and placed this high in the tree it overflows the stack when a page inserts a button.
    func glassButtons(_ enabled: Bool) -> some View {
        environment(\.usesGlass, enabled).buttonStyle(IkagoButtonStyle())
    }

    /// The main action in a group: tinted Liquid Glass.
    func glassProminentButton() -> some View { buttonStyle(IkagoProminentButtonStyle()) }

    /// A control's own Liquid Glass, which brightens under the pointer and flexes when pressed.
    /// `active: false` shows nothing, without changing the view's identity.
    func glassControl<S: Shape>(_ shape: S, _ colors: Palette, active: Bool = true, reacts: Bool = true) -> some View {
        modifier(GlassControl(shape: shape, colors: colors, active: active, reacts: reacts))
    }
}

struct IkagoButtonStyle: PrimitiveButtonStyle {
    func makeBody(configuration: Configuration) -> some View { StyledButton(configuration: configuration, prominent: false) }
}

struct IkagoProminentButtonStyle: PrimitiveButtonStyle {
    func makeBody(configuration: Configuration) -> some View { StyledButton(configuration: configuration, prominent: true) }
}

private struct StyledButton: View {
    let configuration: PrimitiveButtonStyleConfiguration
    let prominent: Bool
    @Environment(\.usesGlass) private var usesGlass

    var body: some View {
        switch (usesGlass, prominent) {
        case (true, false): Button(configuration).buttonStyle(.glass)
        case (true, true): Button(configuration).buttonStyle(.glassProminent)
        case (false, false): Button(configuration).buttonStyle(.bordered)
        case (false, true): Button(configuration).buttonStyle(.borderedProminent)
        }
    }
}

private struct GlassControl<S: Shape>: ViewModifier {
    let shape: S
    let colors: Palette
    let active: Bool
    let reacts: Bool
    @Environment(\.inGlassGroup) private var inGroup

    func body(content: Content) -> some View {
        content.glassEffect(active && colors.glass && !inGroup ? .regular.interactive(reacts) : .identity, in: shape)
    }
}

/// Controls that belong together, on one capsule of Liquid Glass that reacts to the pointer, like
/// macOS's own toolbars. Separate pieces of glass in a container melt together with visible necks.
struct GlassControlGroup<Content: View>: View {
    let colors: Palette
    var height: CGFloat? = nil
    @ViewBuilder let content: Content

    var body: some View {
        content
            .padding(.horizontal, 4)
            .frame(height: height)
            .environment(\.inGlassGroup, true)
            .glassEffect(colors.glass ? .regular.interactive() : .identity, in: Capsule())
    }
}
