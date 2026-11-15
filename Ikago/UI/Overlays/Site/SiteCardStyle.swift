import AppKit
import SwiftUI

/// The site card's building blocks: grouped sections, native pop-up menus, and controls that answer a press.

/// Whether the card is see-through (Liquid Glass or the frosted window); sections then lift with a light wash
/// instead of a grey fill, as Control Center's modules do.
private struct SiteCardTranslucentKey: EnvironmentKey { static let defaultValue = false }
extension EnvironmentValues {
    var siteCardTranslucent: Bool {
        get { self[SiteCardTranslucentKey.self] }
        set { self[SiteCardTranslucentKey.self] = newValue }
    }
}

extension View {
    /// The card's grouped section.
    func siteCard(_ colors: Palette) -> some View { modifier(SiteCardSection(colors: colors)) }
}

private struct SiteCardSection: ViewModifier {
    let colors: Palette
    @Environment(\.siteCardTranslucent) private var translucent

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: Radius.card, style: .continuous)
        let fill: Color = colors.isDark ? .white.opacity(translucent ? 0.08 : 0.05)
            : translucent ? .white.opacity(0.55) : .black.opacity(0.035)
        return content
            .background(shape.fill(fill))
            .overlay(shape.strokeBorder(colors.isDark ? Color.white.opacity(0.06) : Color.black.opacity(translucent ? 0.04 : 0.05),
                                        lineWidth: 0.5).allowsHitTesting(false))
            .clipShape(shape)
    }
}

struct SiteCardDivider: View {
    var body: some View { Rectangle().fill(Color.primary.opacity(0.1)).frame(height: 0.5).padding(.leading, 46) }
}

/// Presses shrink a little and spring back; hover and press fills fade.
struct SiteCardPressStyle: ButtonStyle {
    /// Rows press in less than small controls.
    var scale: CGFloat = 0.94
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? scale : 1)
            .opacity(configuration.isPressed ? 0.75 : 1)
            .animation(.spring(duration: 0.22, bounce: 0.35), value: configuration.isPressed)
    }
}

/// The pill behind the card's controls: white in light mode, a lifted grey in dark mode, like a pop-up button.
struct SiteControlPill<S: InsettableShape>: View {
    let shape: S
    var hovering = false
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let dark = scheme == .dark
        let fill: Color = dark ? Color.white.opacity(hovering ? 0.17 : 0.11) : Color.white.opacity(hovering ? 1 : 0.92)
        let rim: Color = dark ? Color.white.opacity(0.08) : Color.black.opacity(0.1)
        let shade: Color = Color.black.opacity(dark ? 0.25 : 0.07)
        return shape.fill(fill)
            .overlay(shape.strokeBorder(rim, lineWidth: 0.5))
            .shadow(color: shade, radius: 0.8, y: 0.6)
    }
}

/// A round symbol button with a hover fill that answers a press.
struct SiteIconButton: View {
    let symbol: String
    var size: CGFloat = 22
    var help = ""
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol).font(.system(size: size * 0.42, weight: .bold))
                .frame(width: size, height: size)
                .background(Circle().fill(Color.primary.opacity(hovering ? 0.1 : 0)))
                .contentShape(Circle())
        }
        .buttonStyle(SiteCardPressStyle())
        .onHover { hovering = $0 }
        .animation(.ikagoQuick, value: hovering)
        .help(help)
    }
}

/// One choice of a `CompactMenu`.
struct MenuChoice {
    let title: String
    var isOn = false
    var separatorBefore = false
    /// An SF Symbol shown beside the title.
    var symbol: String? = nil
    /// An icon shown beside the title (a site's favicon), instead of a symbol.
    var image: NSImage? = nil
    let action: () -> Void
}

/// A pop-up button: the value in a white pill with up-down arrows, opening a real macOS menu (with a checkmark on the
/// current choice) under it. SwiftUI's `Menu` drops a custom label's background on macOS, so this pops an `NSMenu`.
struct CompactMenu: View {
    let value: String
    let choices: [MenuChoice]
    /// The current value's icon, before its title.
    var image: NSImage? = nil
    @State private var anchor = MenuAnchorBox()
    @State private var hovering = false
    @Environment(\.isEnabled) private var enabled

    var body: some View {
        Button { anchor.popUp(choices) } label: {
            HStack(spacing: 5) {
                if let image { Image(nsImage: image).resizable().interpolation(.high).frame(width: 14, height: 14) }
                Text(value).font(.system(size: 12, weight: .medium)).lineLimit(1)
                    .contentTransition(.opacity)
                Image(systemName: "chevron.up.chevron.down").font(.system(size: 8, weight: .bold)).foregroundStyle(.secondary)
            }
            .padding(.leading, 9).padding(.trailing, 7).frame(height: 22)
            .background(SiteControlPill(shape: RoundedRectangle(cornerRadius: Radius.inner, style: .continuous), hovering: hovering))
            .contentShape(Rectangle())
            .background(MenuAnchorView(box: anchor))
        }
        .buttonStyle(SiteCardPressStyle())
        .fixedSize()
        .opacity(enabled ? 1 : 0.45)
        .onHover { hovering = $0 && enabled }
        .animation(.ikagoQuick, value: hovering)
        .animation(.ikagoQuick, value: value)
    }
}

/// Holds the view a `CompactMenu` opens its menu from.
@MainActor
final class MenuAnchorBox {
    weak var view: NSView?

    func popUp(_ choices: [MenuChoice]) {
        guard let view else { return }
        let menu = NSMenu()
        menu.autoenablesItems = false
        for choice in choices {
            if choice.separatorBefore { menu.addItem(.separator()) }
            let item = ActionMenuItem(title: choice.title, handler: choice.action)
            item.state = choice.isOn ? .on : .off
            if let symbol = choice.symbol { item.image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil) }
            if let image = choice.image?.copy() as? NSImage { image.size = NSSize(width: 16, height: 16); item.image = image }
            menu.addItem(item)
        }
        // The current choice sits over the button, as a pop-up button's menu opens.
        let current = menu.items.first { $0.state == .on }
        let top = view.isFlipped ? 0 : view.bounds.height, below = view.isFlipped ? view.bounds.height + 4 : -4
        menu.popUp(positioning: current, at: NSPoint(x: current == nil ? 0 : -12, y: current == nil ? below : top), in: view)
    }
}

struct MenuAnchorView: FillingViewRepresentable {
    let box: MenuAnchorBox
    func makeNSView(context: Context) -> NSView { AnchorView() }
    func updateNSView(_ view: NSView, context: Context) { box.view = view }

    private final class AnchorView: NSView {
        override func hitTest(_ point: NSPoint) -> NSView? { nil }
    }
}

/// A menu item that runs a closure.
final class ActionMenuItem: NSMenuItem {
    private let handler: () -> Void
    init(title: String, handler: @escaping () -> Void) {
        self.handler = handler
        super.init(title: title, action: #selector(run), keyEquivalent: "")
        target = self
    }
    @available(*, unavailable) required init(coder: NSCoder) { fatalError() }
    @objc private func run() { handler() }
}
