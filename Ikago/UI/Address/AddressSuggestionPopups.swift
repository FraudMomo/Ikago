import SwiftUI

struct AddressAnchorKey: PreferenceKey {
    static let defaultValue: Anchor<CGRect>? = nil
    static func reduce(value: inout Anchor<CGRect>?, nextValue: () -> Anchor<CGRect>?) { value = nextValue() ?? value }
}

/// Follows the address field's actual width and position, including under a crowded toolbar.
struct AddressSuggestionsOverlay: View {
    /// The address field, in this overlay's coordinates.
    let anchor: CGRect?
    let state: BrowserState
    let chrome: ChromeModel
    let palette: CommandPaletteModel

    var body: some View {
        GeometryReader { geometry in
            if let rect = anchor, chrome.isEditingAddress(of: state.activeTabID), !palette.suggestions.isEmpty || palette.error != nil {
                let width = min(max(420, rect.width + 40), max(0, geometry.size.width - 24))
                let x = min(max(12, rect.midX - width / 2), max(12, geometry.size.width - width - 12))
                TopAddressSuggestionPopup(model: palette, isDark: state.topBarPalette.isDark)
                    .frame(width: width)
                    .offset(x: x, y: rect.maxY + 6)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            }
        }
    }
}

/// Omnibox results under the field, built like a macOS menu: system material, 13 pt rows, and the
/// selected row filled with the system accent color. Sidebar and top layouts share it.
struct TopAddressSuggestionPopup: View {
    let model: CommandPaletteModel
    let isDark: Bool

    private var shape: RoundedRectangle { RoundedRectangle(cornerRadius: 12, style: .continuous) }

    var body: some View {
        let ink = AddressAppearance.palette(isDark: isDark)
        VStack(spacing: 0) {
            if let error = model.error {
                Text(error).font(.system(size: 12)).foregroundStyle(.red)
                    .frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 12).padding(.vertical, 6)
            }
            OmniboxResults(model: model, ink: ink, isDark: isDark, rowHeight: OmniboxRow.height)
        }
        .padding(.vertical, 5)
        .background(.regularMaterial, in: shape)  // honors Reduce Transparency
        .environment(\.colorScheme, isDark ? .dark : .light)
        .clipShape(shape)
        .overlay(shape.strokeBorder(Color(nsColor: .separatorColor), lineWidth: 0.5))
        .background(CardShadow(shape: shape, color: .black.opacity(isDark ? 0.4 : 0.2), radius: 16, y: 8))
        .transaction { $0.animation = nil; $0.disablesAnimations = true }
        .addressInteractionRegion()
        .recordLayout("address-suggestions")
    }
}

/// The result rows, sized to their content, for every address presentation.
struct OmniboxResults: View {
    let model: CommandPaletteModel
    let ink: Palette
    let isDark: Bool
    let rowHeight: CGFloat

    var body: some View {
        SuggestionScroller(model: model, rowHeight: rowHeight) { index, item, hovering in
            OmniboxRow(model: model, item: item, index: index, hovering: hovering, ink: ink, isDark: isDark, rowHeight: rowHeight)
                .padding(.horizontal, 5)
        }
        .frame(height: rowHeight * CGFloat(min(OmniboxEngine.maxResults, model.suggestions.count)))
    }
}

/// Scrolls with the keyboard selection. Hover only highlights (Chrome never moves the selection
/// or the field's text on hover); click opens.
struct SuggestionScroller<Row: View>: View {
    let model: CommandPaletteModel
    let rowHeight: CGFloat
    @ViewBuilder let row: (Int, CommandPaletteModel.Suggestion, Bool) -> Row
    @State private var hovered: CommandPaletteModel.Suggestion.ID?

    var body: some View {
        let items = model.suggestions
        ScrollViewReader { proxy in
            ScrollView {
                VStack(spacing: 0) {
                    ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                        row(index, item, hovered == item.id).id(item.id).contentShape(Rectangle())
                            .onTapGesture { model.activate(item) }
                            .onHover { inside in hovered = inside ? item.id : (hovered == item.id ? nil : hovered) }
                    }
                }
            }
            .scrollIndicators(.never)
            .onChange(of: model.selection) { _, index in
                if items.indices.contains(index) { proxy.scrollTo(items[index].id) }
            }
        }
    }
}

/// One omnibox row: favicon or search icon, emphasised matches, then the Switch-to-tab and remove
/// controls. A selected row is accent-filled with white text, like a highlighted menu item.
struct OmniboxRow: View {
    static let height: CGFloat = 26

    let model: CommandPaletteModel
    let item: CommandPaletteModel.Suggestion
    let index: Int
    let hovering: Bool
    let ink: Palette
    let isDark: Bool
    var rowHeight = OmniboxRow.height

    private var selected: Bool { index == model.selection }
    private var primary: Color { selected ? .white : ink.text }
    private var secondary: Color { selected ? .white.opacity(0.8) : ink.secondary }

    var body: some View {
        HStack(spacing: 8) {
            icon.frame(width: 18)
            label.lineLimit(1).truncationMode(.tail)
            Spacer(minLength: 4)
            if let id = item.tabID, id != model.state.activeTabID {
                SwitchTabButton(focused: selected && model.switchFocused, ink: ink, inverted: selected) { model.switchToTab(item) }
            }
            if item.removableURL != nil && (hovering || selected) {
                Button { model.remove(item) } label: {
                    Image(systemName: "xmark").font(.system(size: 10, weight: .semibold)).frame(width: 20, height: 20).contentShape(Circle())
                }
                .buttonStyle(.plain).foregroundStyle(secondary)
                .help("Remove suggestion (⇧⌦)").accessibilityLabel("Remove suggestion")
            }
        }
        .padding(.leading, 7).padding(.trailing, 5)
        .frame(height: rowHeight)
        .background(background)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    @ViewBuilder private var background: some View {
        let shape = RoundedRectangle(cornerRadius: 6, style: .continuous)
        if selected { shape.fill(Color(nsColor: .selectedContentBackgroundColor)) }
        else { shape.fill(ink.text.opacity(hovering ? (isDark ? 0.1 : 0.06) : 0)) }
    }

    @ViewBuilder private var icon: some View {
        if item.isSearch {
            Image(systemName: item.symbol).font(.system(size: 13)).foregroundStyle(secondary)
        } else {
            FaviconView(pageURL: item.url, size: 16)
        }
    }

    private var label: Text {
        let typed = model.query
        if item.isSearch {
            var text = Text(OmniboxHighlight.search(item.title, typed: typed)).font(.system(size: 13)).foregroundStyle(primary)
            if !item.subtitle.isEmpty {
                let subtitle = Text(" — " + item.subtitle).font(.system(size: 13)).foregroundStyle(secondary)
                text = Text("\(text)\(subtitle)")
            }
            return text
        }
        let terms = typed.lowercased().split(whereSeparator: { $0.isWhitespace }).map(String.init)
        var text = Text(OmniboxHighlight.matched(item.title, terms: terms)).font(.system(size: 13)).foregroundStyle(primary)
        if item.subtitle != item.title, !item.subtitle.isEmpty {
            let dash = Text(" — ").font(.system(size: 13)).foregroundStyle(secondary)
            let subtitle = Text(OmniboxHighlight.matched(item.subtitle, terms: terms)).font(.system(size: 13))
                .foregroundStyle(secondary)
            text = Text("\(text)\(dash)\(subtitle)")
        }
        return text
    }
}

/// The "Switch to this tab" pill; Tab moves the keyboard onto it.
private struct SwitchTabButton: View {
    let focused: Bool
    let ink: Palette
    let inverted: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 5) {
                Image(systemName: "arrow.up.right.square").font(.system(size: 11))
                Text("Switch to this tab").font(.system(size: 12))
            }
            .padding(.horizontal, 8).frame(height: 20)
            .background(Capsule().strokeBorder(inverted ? Color.white.opacity(0.7) : ink.separator.opacity(2), lineWidth: 1))
            .overlay { if focused { Capsule().stroke(Color.accentColor, lineWidth: 2) } }
            .contentShape(Capsule())
        }
        .buttonStyle(.plain).foregroundStyle(inverted ? Color.white : ink.text)
        .accessibilityLabel("Switch to this tab")
    }
}
