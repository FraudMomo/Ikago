import SwiftUI

struct EssentialsSettingsSection: View {
    @Bindable var state: BrowserState

    var body: some View {
        // Sidebar + Tabs has no full sidebar: its settings aren't shown there.
        let full = !state.usesTabsLayout
        Group {
            if full {
            PageSection(title: "Sidebar") {
                PageRow(title: "Space header and shortcuts", subtitle: "The Space's name and rows for the places you choose") {
                    Toggle("Space header and shortcuts", isOn: Binding(get: { state.browserPreferences.sidebarShortcuts == true },
                        set: { on in withAnimation(.ikago) { state.browserPreferences.sidebarShortcuts = on ? true : nil } }))
                        .labelsHidden().toggleStyle(.switch)
                }
                if state.browserPreferences.sidebarShortcuts == true {
                    PageDivider()
                    PageRow(title: "Space name", subtitle: "The Space and its menu above the shortcuts") {
                        Toggle("Space name", isOn: Binding(get: { state.browserPreferences.sidebarSpaceName != false },
                            set: { on in withAnimation(.ikago) { state.browserPreferences.sidebarSpaceName = on ? nil : false } }))
                            .labelsHidden().toggleStyle(.switch)
                    }
                    PageDivider()
                    PageRow(title: "Shortcuts", subtitle: "Rows shown under the Space name") {
                        ShortcutChoices(state: state)
                    }
                    if state.showsPinnedGrid {
                        PageDivider()
                        PageRow(title: "Pinned-tab grid", subtitle: "Where the grid sits next to the shortcuts") {
                            SettingsMenu(selection: Binding(
                                get: { state.browserPreferences.pinnedGridAboveShortcuts == true },
                                set: { above in withAnimation(.ikago) { state.browserPreferences.pinnedGridAboveShortcuts = above ? true : nil } }
                            ), options: [(false, "Below shortcuts"), (true, "Above shortcuts")])
                        }
                        }
                }
                PageDivider()
                PageRow(title: "Keep pinned tabs and groups in view", subtitle: "Pinned tabs and groups stay in place; only the tabs below them scroll") {
                    Toggle("Keep pinned tabs and groups in view", isOn: Binding(get: { state.browserPreferences.pinnedRowsStayInView == true },
                        set: { on in withAnimation(.ikago) { state.browserPreferences.pinnedRowsStayInView = on ? true : nil } }))
                        .labelsHidden().toggleStyle(.switch)
                }
            }
            }
            PageSection(title: full ? "Sidebar Essentials" : "Pinned Tabs") {
                PageRow(title: full ? "Show pinned-tab grid" : "Pinned tabs in the icon sidebar",
                        subtitle: full ? "Pinned tabs as a grid at the top of the sidebar; off, as rows in the list"
                                       : "Tiles in the icon sidebar; off, icon tabs at the start of the tab row",
                        figure: AnyView(PinnedTabsFigure(shown: state.showsPinnedGrid, tabsLayout: !full, colors: state.palette))) {
                    Toggle("Show pinned-tab grid", isOn: Binding(get: { state.showsPinnedGrid },
                        set: { on in withAnimation(.ikago) { state.browserPreferences.showPinnedGrid = on } }))
                        .labelsHidden().toggleStyle(.switch)
                }
                if state.showsPinnedGrid && full {
                    PageDivider()
                    PageRow(title: "Grid columns", subtitle: "Maximum columns for pinned tabs") {
                        SettingsMenu(selection: Binding(
                            get: { state.browserPreferences.pinnedGridColumns ?? 3 },
                            set: { state.browserPreferences.pinnedGridColumns = $0 }
                        ), options: (2...8).map { count in (count, "\(count)") })
                    }
                }
            }
        }
        PageSection(title: "Bookmarks Bar", footer: "Toggle with ⇧⌘B.") {
            PageRow(title: "Show bookmarks", subtitle: state.usesTabsLayout ? "A bar under the address bar" : "A drawer at the bottom of the sidebar") {
                Toggle("Show bookmarks bar", isOn: $state.showsBookmarksBar.animation(.ikago)).labelsHidden().toggleStyle(.switch)
            }
        }
    }
}

struct BookmarkOpeningSection: View {
    let state: BrowserState

    var body: some View {
        PageSection(title: "Opening Bookmarks") {
            PageRow(title: "Switch to an open tab", subtitle: "When off, bookmarks always open a new tab.") {
                Toggle("Switch to an open tab", isOn: Binding(get: { state.browserPreferences.reuseBookmarkTabs ?? true },
                    set: { state.browserPreferences.reuseBookmarkTabs = $0 })).labelsHidden().toggleStyle(.switch)
            }
            if state.browserPreferences.reuseBookmarkTabs ?? true {
                PageDivider()
                PageRow(title: "Match open tabs", subtitle: "Only tabs in the current Space.") {
                    SettingsMenu(selection: Binding(get: { state.browserPreferences.bookmarkMatchDomain ?? false },
                        set: { state.browserPreferences.bookmarkMatchDomain = $0 }), options: [(false, "Same page URL"), (true, "Same domain")])
                }
            }
        }
    }
}

/// The shortcut rows as toggles, one small chip each.
private struct ShortcutChoices: View {
    @Bindable var state: BrowserState

    var body: some View {
        let shown = Set(state.browserPreferences.shortcutItems)
        HStack(spacing: 6) {
            ForEach(SidebarShortcut.allCases) { item in
                let on = shown.contains(item)
                Button {
                    withAnimation(.ikago) { state.browserPreferences.setShortcut(item, shown: !on) }
                } label: {
                    Image(systemName: item.symbol).font(.system(size: 12))
                        .frame(width: 28, height: 26)
                        .foregroundStyle(on ? state.palette.text : state.palette.tertiary)
                        .background(RoundedRectangle(cornerRadius: Radius.control, style: .continuous)
                            .fill(on ? state.palette.selected : .clear))
                        .overlay(RoundedRectangle(cornerRadius: Radius.control, style: .continuous)
                            .strokeBorder(state.palette.separator, lineWidth: on ? 0 : 1))
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help(item == .assistant ? "\(item.title) (shown while page intelligence is on)" : item.title)
                .accessibilityLabel(item.title)
                .accessibilityAddTraits(on ? .isSelected : [])
            }
        }
    }
}
