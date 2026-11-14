import SwiftUI

/// The address field that replaces the active tab while editing (Integrated style).
struct InlineAddressField: View {
    @Bindable var model: CommandPaletteModel
    var fontSize: CGFloat = 12
    var alignment: NSTextAlignment = .center
    weak var commands: BrowserCommands?

    var body: some View {
        HStack(spacing: 6) {
            // Spotlight's lead: a magnifier, or the highlighted result's own icon.
            leadingIcon.frame(width: 16)
            AddressTextField(text: $model.query, selectsAllOnFocus: !model.edited, fontSize: fontSize, weight: .regular, alignment: alignment,
                             onSubmit: { model.commit() },
                             onMove: { delta in model.moveSelection(delta) },
                             onCancel: { model.cancel() }, onComplete: { model.focusNext(forward: true) },
                             completion: model.inlineCompletion, temporary: model.temporaryText,
                             onEdit: { model.userEdited($0) }, onBacktab: { model.focusNext(forward: false) },
                             onRemove: { model.removeSelected() },
                             onDeleteEmpty: { model.deleteOnEmpty() },
                             onCommandDigit: { model.toggleScope($0) })
            if !model.query.isEmpty { ClearButton { model.query = "" }.scaleEffect(0.85) }
            if model.mode == .currentTab, let tab = model.state.activeTab, tab.isLoading {
                PageLoadButton(tab: tab, colors: model.state.palette, commands: commands)
            }
        }
        .focusEffectDisabled()
        .addressInteractionRegion()
    }

    @ViewBuilder private var leadingIcon: some View {
        let items = model.suggestions
        if model.scope != .all {
            Image(systemName: model.scope.symbol).font(.system(size: 11, weight: .semibold)).foregroundStyle(Color.accentColor)
        } else if items.indices.contains(model.selection), !items[model.selection].isSearch {
            let item = items[model.selection]
            if item.action != nil {
                Image(systemName: item.symbol).font(.system(size: 11, weight: .medium)).foregroundStyle(.secondary)
            } else {
                FaviconView(pageURL: item.url, size: 14)
            }
        } else {
            Image(systemName: "magnifyingglass").font(.system(size: 11.5, weight: .medium)).foregroundStyle(.secondary)
        }
    }
}
