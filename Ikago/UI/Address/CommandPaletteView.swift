import SwiftUI

/// The command bar (⌘L / ⌘T), after macOS's Spotlight: a capsule with a large field that opens into a card of results.
/// Solid in the address surface's light or dark grey (frosted only with the frosted sidebar on). The highlighted
/// result's icon sits at the field's end and what Return will do follows the text ("— Open", "— Switch to Tab").
/// Results: the top hits without a heading, then headed sections with "Show More". Scopes (⌘1–⌘4) show as a token in
/// the field; with nothing typed the scopes are listed under it. Keyboard selection updates immediately.
struct CommandPaletteView: View {
    @Bindable var model: CommandPaletteModel
    let colors: Palette
    weak var commands: BrowserCommands?
    static let fieldHeight: CGFloat = 52
    static let fontSize: CGFloat = 22

    var body: some View {
        let ink = AddressAppearance.palette(isDark: colors.isDark)
        let items = model.suggestions
        let selected = items.indices.contains(model.selection) ? items[model.selection] : nil
        let open = !items.isEmpty || model.error != nil || model.scope != .all || model.query.isEmpty
        let shape = RoundedRectangle(cornerRadius: Radius.bar, style: .continuous)
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                if model.scope == .all {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 20, weight: .regular))
                        .foregroundStyle(ink.secondary)
                        .frame(width: 24)
                } else {
                    ScopeToken(scope: model.scope, ink: ink) { model.scope = .all }
                }
                AddressTextField(text: $model.query, selectsAllOnFocus: !model.edited, fontSize: Self.fontSize,
                                 placeholder: model.scope == .all ? "Search or enter address" : "Search \(model.scope.title)",
                                 onSubmit: { model.commit() },
                                 onMove: { model.moveSelection($0) },
                                 onCancel: { model.cancel() }, onComplete: { model.focusNext(forward: true) },
                                 completion: model.inlineCompletion, temporary: model.temporaryText,
                                 onEdit: { model.userEdited($0) }, onBacktab: { model.focusNext(forward: false) },
                                 onRemove: { model.removeSelected() },
                                 onDeleteEmpty: { model.deleteOnEmpty() },
                                 onCommandDigit: { model.toggleScope($0) })
                    .frame(height: 30)
                    .overlay(alignment: .leading) { ReturnHint(model: model, selected: selected, ink: ink) }
                if model.mode == .currentTab, let tab = model.state.activeTab, tab.isLoading {
                    PageLoadButton(tab: tab, colors: ink, commands: commands)
                }
                if let selected { SelectedResultIcon(item: selected, ink: ink) }
            }
            .padding(.leading, 18).padding(.trailing, 14)
            .frame(height: Self.fieldHeight)
            .overlay(alignment: .bottom) {
                if model.mode == .currentTab { PageLoadProgress(tab: model.state.activeTab, colors: ink).padding(.horizontal, 22) }
            }
            if open {
                Rectangle().fill(ink.separator).frame(height: 0.5)
                if model.query.isEmpty && model.scope == .all { ScopeList(model: model, ink: ink) }
                if let error = model.error {
                    Text(error).font(.system(size: 12.5)).foregroundStyle(.red)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 20).padding(.vertical, 10)
                }
                if !items.isEmpty {
                    OmniboxResults(model: model, ink: ink, isDark: colors.isDark, rowHeight: 36, visibleRows: 10)
                        .padding(.horizontal, 6).padding(.vertical, 6)
                } else if model.scope != .all {
                    Text("No \(model.scope.title.lowercased()) match").font(.system(size: 13)).foregroundStyle(ink.tertiary)
                        .frame(maxWidth: .infinity).frame(height: 52)
                }
            }
        }
        .frame(maxWidth: 680)
        .background { AddressSurface(shape: shape, isDark: colors.isDark, frosted: model.state.frostedChrome) }
        .clipShape(shape)
        .overlay(shape.strokeBorder(ink.text.opacity(colors.isDark ? 0.14 : 0.1), lineWidth: 0.5).allowsHitTesting(false))
        .background(CardShadow(shape: shape, color: .black.opacity(colors.isDark ? 0.5 : 0.2), radius: 36, y: 16))
        .environment(\.colorScheme, colors.isDark ? .dark : .light)
        .padding(.horizontal, 16)
        .addressInteractionRegion()
        .transaction { $0.animation = nil; $0.disablesAnimations = true }
    }
}

/// What Return will do, after the text in the field, like Spotlight's "— Open".
private struct ReturnHint: View {
    let model: CommandPaletteModel
    let selected: CommandPaletteModel.Suggestion?
    let ink: Palette

    var body: some View {
        if let selected, model.switchFocused || !model.query.isEmpty {
            let shown = model.temporaryText ?? model.query + model.inlineCompletion
            let width = (shown as NSString).size(withAttributes: [.font: NSFont.systemFont(ofSize: CommandPaletteView.fontSize)]).width
            GeometryReader { geometry in
                if width + 120 < geometry.size.width {
                    Text("— \(verb(selected))")
                        .font(.system(size: 15, weight: .regular))
                        .foregroundStyle(ink.secondary)
                        .offset(x: width + 12)
                        .frame(maxHeight: .infinity)
                }
            }
            .allowsHitTesting(false)
        }
    }

    private func verb(_ item: CommandPaletteModel.Suggestion) -> String {
        if item.action != nil { return "Run" }
        if model.switchFocused || item.source == .openTab { return "Switch to Tab" }
        if item.isSearch { return "Search" }
        return "Open"
    }
}

/// With nothing typed: the scopes, each with its shortcut, as Golden Gate's Spotlight lists its modes.
private struct ScopeList: View {
    let model: CommandPaletteModel
    let ink: Palette

    var body: some View {
        HStack(spacing: 6) {
            ForEach(AddressScope.allCases.dropFirst()) { scope in
                Button { model.scope = scope } label: {
                    HStack(spacing: 6) {
                        Image(systemName: scope.symbol).font(.system(size: 11, weight: .medium))
                        Text(scope.title).font(.system(size: 12.5, weight: .medium))
                        Text(scope.shortcut).font(.system(size: 11)).foregroundStyle(ink.tertiary)
                    }
                    .foregroundStyle(ink.secondary)
                    .padding(.horizontal, 10).frame(height: 28)
                    .background(Capsule().fill(ink.text.opacity(0.06)))
                    .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .help("Search \(scope.title) (\(scope.shortcut))")
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 14).padding(.top, 10).padding(.bottom, 4)
    }
}

/// The highlighted result's icon at the end of the field, as Spotlight shows the app it will open.
private struct SelectedResultIcon: View {
    let item: CommandPaletteModel.Suggestion
    let ink: Palette

    var body: some View {
        Group {
            if item.isSearch || item.action != nil {
                Image(systemName: item.symbol).font(.system(size: 17, weight: .regular)).foregroundStyle(ink.secondary)
            } else {
                FaviconView(pageURL: item.url, size: 24)
            }
        }
        .frame(width: 30, height: 30)
        .accessibilityHidden(true)
    }
}

/// Results for integrated address editing in the sidebar.
struct SuggestionList: View {
    let model: CommandPaletteModel
    let colors: Palette

    var body: some View { AddressSuggestionPopup(model: model, isDark: colors.isDark) }
}

/// Small × inside a search field that empties it.
struct ClearButton: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: "xmark.circle.fill").font(.system(size: 14)).foregroundStyle(.tertiary)
        }
        .buttonStyle(.plain)
        .help("Clear")
        .transition(.opacity.combined(with: .scale(scale: 0.6)))
    }
}
