import SwiftUI

/// The Space's name with a menu to switch Spaces, as a header under the traffic lights
/// (Settings ▸ Sidebar & Toolbar ▸ Space header and shortcuts).
struct SidebarSpaceHeader: View {
    let state: BrowserState
    weak var commands: BrowserCommands?
    @State private var hovering = false

    var body: some View {
        let colors = state.palette
        let space = state.activeSpace
        Menu {
            ForEach(state.spaces) { other in
                Button { withAnimation(.ikago) { state.switchSpace(other.id) } } label: {
                    Label(other.name, systemImage: other.id == space.id ? "checkmark" : other.symbol)
                }
            }
            Divider()
            Button("New Space…") { commands?.newSpace() }
            Button("Rename Space…") { commands?.renameSpace(space.id) }
        } label: {
            HStack(spacing: 10) {
                Image(systemName: space.symbol).font(.system(size: 13, weight: .medium))
                    .foregroundStyle(colors.text)
                    .frame(width: 28, height: 28)
                    .background(RoundedRectangle(cornerRadius: Radius.row, style: .continuous).fill(colors.selected))
                    .overlay(RoundedRectangle(cornerRadius: Radius.row, style: .continuous).strokeBorder(colors.separator, lineWidth: 0.5))
                Text(space.name).font(.system(size: 14, weight: .semibold)).foregroundStyle(colors.text).lineLimit(1)
                Spacer(minLength: 4)
                Image(systemName: "chevron.down").font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(hovering ? colors.secondary : colors.tertiary)
            }
            .padding(.leading, 4).padding(.trailing, 10)
            .frame(height: 40)
            .background(RoundedRectangle(cornerRadius: Radius.row, style: .continuous).fill(hovering ? colors.hover : .clear))
            .contentShape(Rectangle())
        }
        .menuStyle(.button).buttonStyle(.plain).menuIndicator(.hidden)
        .sidebarHover($hovering)
        .animation(.ikagoQuick, value: hovering)
        .accessibilityLabel("Space: \(space.name)")
    }
}

/// Quiet rows for places beside the tabs: the assistant (when on), bookmarks and history. A row is selected while
/// what it opens is on screen.
struct SidebarShortcuts: View {
    let state: BrowserState
    let chrome: ChromeModel
    weak var commands: BrowserCommands?

    var body: some View {
        let colors = state.palette
        let page = state.activeTab.flatMap { InternalPage(url: $0.url) }
        VStack(spacing: 1) {
            if state.browserPreferences.pageIntelligence == true {
                SidebarShortcutRow(title: "Assistant", symbol: "sparkles", selected: chrome.showPageAssistant, colors: colors) {
                    commands?.togglePageAssistant()
                }
            }
            SidebarShortcutRow(title: "Bookmarks", symbol: "bookmark", selected: page == .bookmarks, colors: colors) {
                commands?.openPage(.bookmarks)
            }
            SidebarShortcutRow(title: "History", symbol: "clock", selected: page == .history, colors: colors) {
                commands?.openPage(.history)
            }
        }
    }
}

struct SidebarShortcutRow: View {
    let title: String
    let symbol: String
    let selected: Bool
    let colors: Palette
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 9) {
                Image(systemName: symbol).font(.system(size: 13, weight: .regular))
                    .symbolRenderingMode(.monochrome)
                    .foregroundStyle(selected ? colors.text : colors.secondary)
                    .frame(width: 16)
                Text(title).font(.system(size: 13, weight: selected ? .medium : .regular))
                    .foregroundStyle(colors.text)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 10).frame(height: 32)
            .background(RoundedRectangle(cornerRadius: Radius.row, style: .continuous)
                .fill(selected ? colors.selected : hovering ? colors.hover : .clear))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .sidebarHover($hovering)
        .animation(.ikagoQuick, value: hovering)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}
