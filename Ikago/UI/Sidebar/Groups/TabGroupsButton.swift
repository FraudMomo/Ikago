import SwiftUI

/// The Tab Groups control (Customize): the Space's hidden groups to show again, then the others to go to. It shows
/// wherever it is placed; while groups are hidden and it isn't placed, the sidebar's bottom bar and the icon rail's foot
/// show it anyway, so a hidden group is never out of reach. The tab row has its own copy (`HiddenGroupsButton`).
struct TabGroupsButton: View {
    let state: BrowserState
    let colors: Palette
    var size: CGFloat = 28

    var body: some View {
        let hidden = state.closedFolders
        Menu {
            TabGroupsMenu(state: state)
        } label: {
            Image(systemName: ChromeItem.tabGroups.symbol)
                .font(.system(size: 12.5, weight: .medium))
                .foregroundStyle(colors.glass ? colors.text.opacity(0.85) : colors.secondary)
                .frame(width: size, height: size)
                .overlay(alignment: .topTrailing) {
                    if !hidden.isEmpty {
                        Text("\(hidden.count)").font(.system(size: 8.5, weight: .bold).monospacedDigit())
                            .foregroundStyle(colors.secondary)
                            .padding(.horizontal, 3).frame(minWidth: 12, minHeight: 12)
                            .background(Capsule().fill(colors.text.opacity(0.1)))
                            .offset(x: 2, y: -1)
                    }
                }
                .contentShape(Circle()).glassControl(Circle(), colors)
        }
        .menuStyle(.button).buttonStyle(.plain).menuIndicator(.hidden).fixedSize()
        .help(hidden.isEmpty ? "Tab Groups" : "Tab Groups · \(hidden.count) hidden")
        .accessibilityLabel(hidden.isEmpty ? "Tab Groups" : "Tab Groups, \(hidden.count) hidden")
    }
}

/// The menu itself: hidden groups (each to show again, or all of them), then the shown groups (choosing one goes to its
/// first tab).
struct TabGroupsMenu: View {
    let state: BrowserState

    var body: some View {
        let hidden = state.closedFolders
        let shown = state.listedFolders
        if !hidden.isEmpty {
            Section("Hidden Groups") {
                ForEach(hidden) { folder in
                    let count = state.tabs(inSubtree: folder).count
                    Button("\(folder.name.isEmpty ? "Group" : folder.name) (\(count) \(count == 1 ? "tab" : "tabs"))") {
                        withAnimation(.ikagoQuick) { state.reopenFolder(folder.id) }
                    }
                }
                if hidden.count > 1 {
                    Button("Show All") { withAnimation(.ikagoQuick) { for folder in hidden { state.reopenFolder(folder.id, selecting: false) } } }
                }
            }
        }
        if !shown.isEmpty {
            Section("Groups") {
                ForEach(shown) { folder in
                    Button(folder.name.isEmpty ? "Group" : folder.name) {
                        guard let first = state.tabs(inSubtree: folder).first else { return }
                        withAnimation(.ikago) { state.select(first.id) }
                    }
                    .disabled(state.tabs(inSubtree: folder).isEmpty)
                }
            }
        }
        if hidden.isEmpty && shown.isEmpty {
            Text("No Groups in This Space")
        }
    }
}
