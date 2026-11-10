import SwiftUI

/// The command bar (⌘L / ⌘T): a Liquid Glass card over the page with a large input and
/// suggestions; keyboard selection updates immediately.
struct CommandPaletteView: View {
    @Bindable var model: CommandPaletteModel
    let colors: Palette
    weak var commands: BrowserCommands?

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 17, weight: .medium))
                    .foregroundStyle(colors.secondary)
                AddressTextField(text: $model.query, fontSize: 20,
                                 onSubmit: { model.commit() },
                                 onMove: { model.moveSelection($0) },
                                 onCancel: { model.cancel() }, onComplete: { model.focusNext(forward: true) },
                                 completion: model.inlineCompletion, temporary: model.temporaryText,
                                 onEdit: { model.userEdited($0) }, onBacktab: { model.focusNext(forward: false) },
                                 onRemove: { model.removeSelected() })
                    .frame(height: 26)
                if !model.query.isEmpty {
                    ClearButton { model.query = "" }
                }
                if model.mode == .currentTab, let tab = model.state.activeTab, tab.isLoading {
                    PageLoadButton(tab: tab, colors: colors, commands: commands)
                }
            }
            .padding(.horizontal, 20)
            .frame(height: 60)
            .overlay(alignment: .bottom) {
                if model.mode == .currentTab { PageLoadProgress(tab: model.state.activeTab, colors: colors).padding(.horizontal, 20) }
            }

            if let error = model.error {
                Text(error).font(.callout).foregroundStyle(.red)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 20).padding(.bottom, 10)
            }

            if !model.suggestions.isEmpty {
                Rectangle().fill(colors.separator).frame(height: 0.5).padding(.horizontal, 14)
                OmniboxResults(model: model, ink: colors, isDark: colors.isDark, rowHeight: 32).padding(.vertical, 8).padding(.horizontal, -5)
            }
        }
        .frame(maxWidth: 640)
        .padding(.horizontal, 16)
        .surface(.rect(cornerRadius: 22), colors)
        .background(CardShadow(shape: RoundedRectangle(cornerRadius: 22), color: .black.opacity(0.14), radius: 24, y: 10))
        .addressInteractionRegion()
        .transaction { $0.animation = nil; $0.disablesAnimations = true }
    }
}

/// Results for integrated address editing in the sidebar: the same menu as the top layouts.
struct SuggestionList: View {
    let model: CommandPaletteModel
    let colors: Palette

    var body: some View { TopAddressSuggestionPopup(model: model, isDark: colors.isDark) }
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
