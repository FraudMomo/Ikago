import SwiftUI

struct EssentialsSettingsSection: View {
    @Bindable var state: BrowserState

    var body: some View {
        Group {
            PageSection(title: "Sidebar") {
                PageRow(title: "Space header and shortcuts", subtitle: "The Space's name, Assistant, Bookmarks and History") {
                    Toggle("Space header and shortcuts", isOn: Binding(get: { state.browserPreferences.sidebarShortcuts == true },
                        set: { on in withAnimation(.ikago) { state.browserPreferences.sidebarShortcuts = on ? true : nil } }))
                        .labelsHidden().toggleStyle(.switch)
                }
                PageDivider()
                PageRow(title: "Keep pinned tabs and groups in view", subtitle: "Pinned tabs and groups stay in place; only the tabs below them scroll") {
                    Toggle("Keep pinned tabs and groups in view", isOn: Binding(get: { state.browserPreferences.pinnedRowsStayInView == true },
                        set: { on in withAnimation(.ikago) { state.browserPreferences.pinnedRowsStayInView = on ? true : nil } }))
                        .labelsHidden().toggleStyle(.switch)
                }
            }
            PageSection(title: "Sidebar Essentials") {
                PageRow(title: "Show pinned-tab grid", subtitle: "Pinned tabs as a grid at the top of the sidebar") {
                    Toggle("Show pinned-tab grid", isOn: Binding(get: { state.showsPinnedGrid },
                        set: { state.browserPreferences.showPinnedGrid = $0 })).labelsHidden().toggleStyle(.switch)
                }
                if state.showsPinnedGrid {
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
            PageRow(title: "Show bookmarks", subtitle: "A drawer at the bottom of the sidebar") {
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
