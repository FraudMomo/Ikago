import SwiftUI

/// Settings' own controls, so every page uses the same few: a pop-up menu pill (`SettingsMenu`), a segmented pill
/// (`SettingsSegmented`), buttons (`SettingsButtonStyle`), and one soft accent (`SettingsColors.accent`) for switches,
/// sliders and the default button, instead of stock pop-up buttons and blue text.

extension SettingsColors {
    /// A soft iris, light and dark: switches, sliders, checkmarks, selection rings and the default button.
    static func accent(_ colors: Palette) -> Color { colors.isDark ? Color(hex: 0x8B8DF5) : Color(hex: 0x5B5BD6) }
}

extension Color {
    /// `SettingsColors.accent` for views without the palette: follows the light or dark appearance it's drawn in.
    static let settingsAccent = Color(nsColor: NSColor(name: "settingsAccent") { appearance in
        appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? NSColor(hex: 0x8B8DF5) : NSColor(hex: 0x5B5BD6)
    })
}

/// A choice from a list, shown as a white pill with up-down arrows that opens a real macOS menu (`CompactMenu`).
struct SettingsMenu<Value: Hashable>: View {
    @Binding var selection: Value
    let options: [(Value, String)]
    /// Icons beside the choices (search engines' favicons), where they help spot one.
    var icons: [Value: NSImage] = [:]

    var body: some View {
        CompactMenu(value: options.first { $0.0 == selection }?.1 ?? "", choices: options.map { value, title in
            MenuChoice(title: title, isOn: value == selection, image: icons[value]) { withAnimation(.ikagoQuick) { selection = value } }
        }, image: icons[selection])
    }
}

/// The search engines' own icons, from their sites through the favicon cache (kept on disk after the first time).
@MainActor @Observable
final class SearchEngineIcons {
    static let shared = SearchEngineIcons()
    private(set) var icons: [SearchEngine: NSImage] = [:]
    private var loading = false

    func load() async {
        guard !loading, icons.count < SearchEngine.allCases.count else { return }
        loading = true
        defer { loading = false }
        // One after another: six small icons, and the cache coalesces repeats.
        for engine in SearchEngine.allCases where icons[engine] == nil {
            guard let host = URL(string: engine.searchURL("ikago"))?.host, let url = URL(string: "https://\(host)/favicon.ico") else { continue }
            if let image = await FaviconCache.shared.image(for: url) { icons[engine] = image }
        }
    }
}

/// Two to four choices side by side: the chosen one rides a lifted pill that slides between them.
struct SettingsSegmented<Value: Hashable>: View {
    @Binding var selection: Value
    let options: [(Value, String)]
    @Namespace private var namespace
    @Environment(\.colorScheme) private var scheme
    @Environment(\.isEnabled) private var enabled
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let dark = scheme == .dark
        HStack(spacing: 2) {
            ForEach(options.indices, id: \.self) { index in
                let (value, title) = options[index]
                let selected = value == selection
                Button {
                    withAnimation(reduceMotion ? nil : .spring(duration: 0.28, bounce: 0.15)) { selection = value }
                } label: {
                    Text(title).font(.system(size: 12, weight: selected ? .semibold : .medium)).lineLimit(1)
                        .foregroundStyle(selected ? Color.primary : Color.secondary)
                        .padding(.horizontal, 11).frame(height: 22)
                        .background {
                            if selected {
                                RoundedRectangle(cornerRadius: 6, style: .continuous)
                                    .fill(dark ? Color.white.opacity(0.16) : .white)
                                    .shadow(color: .black.opacity(dark ? 0.3 : 0.1), radius: 1, y: 0.5)
                                    .matchedGeometryEffect(id: "selection", in: namespace)
                            }
                        }
                        .contentShape(Rectangle())
                }
                .buttonStyle(SiteCardPressStyle(scale: 0.96))
                .accessibilityAddTraits(selected ? .isSelected : [])
            }
        }
        .padding(2)
        .background(RoundedRectangle(cornerRadius: Radius.control, style: .continuous).fill(Color.primary.opacity(dark ? 0.08 : 0.06)))
        .fixedSize()
        .opacity(enabled ? 1 : 0.45)
    }
}

/// Settings' buttons: a white pill with a hairline (or the accent for the default action), hover and press feedback.
/// Never blue text on nothing.
struct SettingsButtonStyle: ButtonStyle {
    var prominent = false
    func makeBody(configuration: Configuration) -> some View { SettingsButton(configuration: configuration, prominent: prominent) }
}

private struct SettingsButton: View {
    let configuration: ButtonStyleConfiguration
    let prominent: Bool
    @State private var hovering = false
    @Environment(\.isEnabled) private var enabled
    @Environment(\.colorScheme) private var scheme
    @Environment(\.pagePalette) private var palette

    var body: some View {
        let dark = scheme == .dark
        let shape = RoundedRectangle(cornerRadius: 7, style: .continuous)
        let accent = palette.map(SettingsColors.accent) ?? .accentColor
        configuration.label
            .font(.system(size: 12, weight: .medium)).lineLimit(1)
            .foregroundStyle(prominent ? Color.white : Color.primary)
            .padding(.horizontal, 11).frame(minHeight: 24)
            .background {
                if prominent {
                    shape.fill(accent).brightness(hovering ? 0.05 : 0)
                } else {
                    shape.fill(dark ? Color.white.opacity(hovering ? 0.16 : 0.1) : Color.white)
                    shape.strokeBorder(dark ? Color.white.opacity(0.08) : Color.black.opacity(hovering ? 0.16 : 0.11), lineWidth: 0.5)
                }
            }
            .shadow(color: .black.opacity(prominent || !dark ? 0.08 : 0), radius: 0.8, y: 0.5)
            .overlay(shape.fill(Color.black.opacity(configuration.isPressed ? 0.1 : 0)))
            .contentShape(shape)
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .opacity(enabled ? 1 : 0.45)
            .onHover { hovering = $0 && enabled }
            .animation(.ikagoQuick, value: hovering)
            .animation(.spring(duration: 0.2, bounce: 0.3), value: configuration.isPressed)
    }
}

/// Narrow windows: the current category as a pill (its symbol, title and a chevron) that opens every category in a
/// native menu, grouped as the navigation column groups them.
struct SettingsCategoryMenu: View {
    @Bindable var state: BrowserState
    @State private var anchor = MenuAnchorBox()
    @State private var hovering = false

    var body: some View {
        let current = state.settingsCategory
        Button { anchor.popUp(choices) } label: {
            HStack(spacing: 8) {
                Image(systemName: current.symbol).font(.system(size: 13)).frame(width: 18)
                Text(current.title).font(.system(size: 13, weight: .semibold))
                Image(systemName: "chevron.down").font(.system(size: 9, weight: .bold)).foregroundStyle(.secondary)
            }
            .padding(.horizontal, 12).frame(height: 32)
            .background(SiteControlPill(shape: RoundedRectangle(cornerRadius: Radius.control, style: .continuous), hovering: hovering))
            .contentShape(Rectangle())
            .background(MenuAnchorView(box: anchor))
        }
        .buttonStyle(SiteCardPressStyle(scale: 0.97))
        .onHover { hovering = $0 }
        .animation(.ikagoQuick, value: hovering)
        .animation(.ikagoQuick, value: current)
    }

    private var choices: [MenuChoice] {
        SettingsCategory.navigationGroups.enumerated().flatMap { group, categories in
            categories.enumerated().map { index, category in
                MenuChoice(title: category.title, isOn: category == state.settingsCategory, separatorBefore: group > 0 && index == 0,
                           symbol: category.symbol) { state.settingsCategory = category }
            }
        }
    }
}
