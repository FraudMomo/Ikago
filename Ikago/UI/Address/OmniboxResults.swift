import SwiftUI

/// Omnibox results under the integrated field: a solid card in the field's light or dark surface (frosted only when
/// Settings ▸ Appearance turns the frosted sidebar on), headed sections and 13 pt rows, the selected row filled with the
/// system accent color.
struct AddressSuggestionPopup: View {
    let model: CommandPaletteModel
    let isDark: Bool

    private var shape: RoundedRectangle { RoundedRectangle(cornerRadius: Radius.card, style: .continuous) }

    var body: some View {
        let ink = AddressAppearance.palette(isDark: isDark)
        VStack(spacing: 0) {
            if let error = model.error {
                Text(error).font(.system(size: 12)).foregroundStyle(.red)
                    .frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 12).padding(.vertical, 6)
            }
            if model.scope != .all { ScopeHeader(model: model, ink: ink) }
            OmniboxResults(model: model, ink: ink, isDark: isDark, rowHeight: OmniboxRow.height)
        }
        .padding(.vertical, 5)
        .background { AddressSurface(shape: shape, isDark: isDark, frosted: model.state.frostedChrome) }
        .environment(\.colorScheme, isDark ? .dark : .light)
        .clipShape(shape)
        .overlay(shape.strokeBorder(ink.separator.opacity(1.4), lineWidth: 0.5))
        .background(CardShadow(shape: shape, color: .black.opacity(isDark ? 0.4 : 0.16), radius: 18, y: 8))
        .transaction { $0.animation = nil; $0.disablesAnimations = true }
        .addressInteractionRegion()
        .recordLayout("address-suggestions")
    }
}

/// The address card's fill: the solid light/dark address surface, or the system material over it with the frosted
/// sidebar on (Reduce Transparency keeps it solid).
struct AddressSurface<S: Shape>: View {
    let shape: S
    let isDark: Bool
    let frosted: Bool

    var body: some View {
        if frosted { shape.fill(.regularMaterial) } else { shape.fill(AddressAppearance.background(isDark: isDark)) }
    }
}

/// In the dropdown, a scope (⌘1–⌘4) shows as a small heading with how to leave it.
private struct ScopeHeader: View {
    let model: CommandPaletteModel
    let ink: Palette

    var body: some View {
        HStack(spacing: 6) {
            ScopeToken(scope: model.scope, ink: ink) { model.scope = .all }
            Spacer(minLength: 0)
            Text("esc to search everything").font(.system(size: 11)).foregroundStyle(ink.tertiary)
        }
        .padding(.horizontal, 10).padding(.top, 3).padding(.bottom, 5)
    }
}

/// A scope as a token: its symbol and name in an accent capsule; clicking it returns to everything.
struct ScopeToken: View {
    let scope: AddressScope
    let ink: Palette
    let clear: () -> Void

    var body: some View {
        Button(action: clear) {
            HStack(spacing: 4) {
                Image(systemName: scope.symbol).font(.system(size: 10, weight: .semibold))
                Text(scope.title).font(.system(size: 12, weight: .semibold))
            }
            .foregroundStyle(Color.accentColor)
            .padding(.horizontal, 8).frame(height: 22)
            .background(Capsule().fill(Color.accentColor.opacity(0.14)))
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .help("Search everything")
        .accessibilityLabel("Searching \(scope.title). Click to search everything.")
    }
}

/// The result rows under their section headings, sized to their content (up to `visibleRows` rows, then scrolling),
/// for every address presentation.
struct OmniboxResults: View {
    let model: CommandPaletteModel
    let ink: Palette
    let isDark: Bool
    let rowHeight: CGFloat
    var visibleRows = OmniboxEngine.maxResults + 1
    static let headerHeight: CGFloat = 24

    var body: some View {
        let sections = model.sections
        let rows = model.suggestions.count
        let headers = sections.filter { !$0.title.isEmpty }.count
        let height = CGFloat(rows) * rowHeight + CGFloat(headers) * (Self.headerHeight + 6)
        let cap = CGFloat(visibleRows) * rowHeight + 3 * (Self.headerHeight + 6)
        SuggestionScroller(model: model, sections: sections, rowHeight: rowHeight, ink: ink) { index, item, hovering in
            OmniboxRow(model: model, item: item, index: index, hovering: hovering, ink: ink, isDark: isDark, rowHeight: rowHeight)
                .padding(.horizontal, 5)
        }
        .frame(height: min(height, cap))
    }
}

/// Scrolls with the keyboard selection. Hover only highlights (Chrome never moves the selection
/// or the field's text on hover); click opens.
struct SuggestionScroller<Row: View>: View {
    let model: CommandPaletteModel
    let sections: [AddressSection]
    let rowHeight: CGFloat
    let ink: Palette
    @ViewBuilder let row: (Int, CommandPaletteModel.Suggestion, Bool) -> Row
    @State private var hovered: CommandPaletteModel.Suggestion.ID?

    var body: some View {
        let items = model.suggestions
        ScrollViewReader { proxy in
            ScrollView {
                VStack(spacing: 0) {
                    ForEach(sections, id: \.title) { section in
                        // The top hits carry no heading, as in Spotlight; the others have one over a hairline, and
                        // "Show More" opens the matching scope.
                        if !section.title.isEmpty {
                            VStack(spacing: 4) {
                                HStack {
                                    Text(section.title).font(.system(size: 12, weight: .semibold)).foregroundStyle(ink.secondary)
                                        .accessibilityAddTraits(.isHeader)
                                    Spacer(minLength: 0)
                                    if let scope = section.more {
                                        Button { model.scope = scope } label: {
                                            HStack(spacing: 3) {
                                                Text("Show More")
                                                Image(systemName: "arrow.up.right.square.fill").font(.system(size: 10))
                                            }
                                            .font(.system(size: 11.5, weight: .medium)).foregroundStyle(ink.secondary)
                                        }
                                        .buttonStyle(.plain)
                                    }
                                }
                                Rectangle().fill(ink.separator).frame(height: 0.5)
                            }
                            .padding(.horizontal, 17).padding(.top, 8)
                            .frame(height: OmniboxResults.headerHeight + 6, alignment: .bottom)
                        }
                        ForEach(section.range.filter { items.indices.contains($0) }, id: \.self) { index in
                            let item = items[index]
                            row(index, item, hovered == item.id).id(item.id).contentShape(Rectangle())
                                .onTapGesture { model.activate(item) }
                                .onHover { inside in hovered = inside ? item.id : (hovered == item.id ? nil : hovered) }
                        }
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

/// One omnibox row, laid out like a Spotlight result: the site's icon (or the kind's symbol), the title with what was
/// typed emphasised and the address after it in grey, then on the right what the row is: an action's shortcut,
/// "Switch to Tab", or the remove control. The selected row sits on a neutral rounded fill, as in Spotlight; text keeps
/// its colors.
struct OmniboxRow: View {
    static let height: CGFloat = 30

    let model: CommandPaletteModel
    let item: CommandPaletteModel.Suggestion
    let index: Int
    let hovering: Bool
    let ink: Palette
    let isDark: Bool
    var rowHeight = OmniboxRow.height

    private var selected: Bool { index == model.selection }
    private var primary: Color { ink.text }
    private var secondary: Color { ink.secondary }
    private var fontSize: CGFloat { rowHeight >= 34 ? 14 : 13 }

    var body: some View {
        HStack(spacing: rowHeight >= 34 ? 11 : 9) {
            icon
            label.lineLimit(1).truncationMode(.tail)
            Spacer(minLength: 4)
            if let action = item.action, !action.detail.isEmpty {
                Text(action.detail).font(.system(size: 12)).foregroundStyle(ink.tertiary).lineLimit(1)
            } else if let action = item.action, !action.shortcut.isEmpty {
                Text(action.shortcut).font(.system(size: 11.5, weight: .medium).monospaced())
                    .foregroundStyle(secondary)
                    .padding(.horizontal, 6).frame(height: 18)
                    .background(RoundedRectangle(cornerRadius: Radius.inner - 2, style: .continuous)
                        .fill(ink.text.opacity(selected ? 0.1 : 0.06)))
            } else if item.source == .bookmark && !(hovering || selected) {
                Image(systemName: "star.fill").font(.system(size: 9)).foregroundStyle(secondary)
            }
            if let id = item.tabID, id != model.state.activeTabID {
                SwitchTabButton(focused: selected && model.switchFocused, ink: ink, inverted: false) { model.switchToTab(item) }
            }
            if item.removableURL != nil && (hovering || selected) {
                Button { model.remove(item) } label: {
                    Image(systemName: "xmark").font(.system(size: 10, weight: .semibold)).frame(width: 20, height: 20).contentShape(Circle())
                }
                .buttonStyle(.plain).foregroundStyle(secondary)
                .help("Remove suggestion (⇧⌦)").accessibilityLabel("Remove suggestion")
            }
        }
        .padding(.leading, rowHeight >= 34 ? 10 : 7).padding(.trailing, 8)
        .frame(height: rowHeight)
        .background(background)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    @ViewBuilder private var background: some View {
        let shape = RoundedRectangle(cornerRadius: Radius.control, style: .continuous)
        shape.fill(ink.text.opacity(selected ? (isDark ? 0.14 : 0.09) : hovering ? (isDark ? 0.07 : 0.045) : 0))
    }

    /// The site's icon or the kind's symbol, bare, as Spotlight shows app icons.
    private var icon: some View {
        let size: CGFloat = rowHeight >= 34 ? 18 : 16
        return Group {
            if item.isSearch || item.action != nil {
                Image(systemName: item.symbol).font(.system(size: size * 0.78, weight: .regular)).foregroundStyle(secondary)
            } else {
                FaviconView(pageURL: item.url, size: size)
            }
        }
        .frame(width: size + 2, height: size + 2)
    }

    private var label: Text {
        let typed = model.query
        if item.action != nil {
            return Text(OmniboxHighlight.matched(item.title, terms: typed.lowercased().split(whereSeparator: { $0.isWhitespace }).map(String.init)))
                .font(.system(size: fontSize)).foregroundStyle(primary)
        }
        if item.isSearch {
            var text = Text(OmniboxHighlight.search(item.title, typed: typed)).font(.system(size: fontSize)).foregroundStyle(primary)
            if !item.subtitle.isEmpty {
                let subtitle = Text(" — " + item.subtitle).font(.system(size: fontSize)).foregroundStyle(secondary)
                text = Text("\(text)\(subtitle)")
            }
            return text
        }
        let terms = typed.lowercased().split(whereSeparator: { $0.isWhitespace }).map(String.init)
        var text = Text(OmniboxHighlight.matched(item.title, terms: terms)).font(.system(size: fontSize)).foregroundStyle(primary)
        if item.subtitle != item.title, !item.subtitle.isEmpty {
            let dash = Text(" — ").font(.system(size: fontSize)).foregroundStyle(secondary)
            let subtitle = Text(OmniboxHighlight.matched(item.subtitle, terms: terms)).font(.system(size: fontSize))
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
            HStack(spacing: 4) {
                Text("Switch to Tab").font(.system(size: 11.5, weight: .medium))
                Image(systemName: "arrow.right").font(.system(size: 9, weight: .bold))
            }
            .padding(.horizontal, 8).frame(height: 20)
            .background(Capsule().fill(ink.text.opacity(0.08)))
            .overlay { if focused { Capsule().stroke(Color.accentColor, lineWidth: 2) } }
            .contentShape(Capsule())
        }
        .buttonStyle(.plain).foregroundStyle(inverted ? Color.white : ink.text)
        .accessibilityLabel("Switch to this tab")
    }
}
