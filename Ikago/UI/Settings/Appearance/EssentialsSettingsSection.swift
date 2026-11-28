import SwiftUI

struct EssentialsSettingsSection: View {
    @Bindable var state: BrowserState

    var body: some View {
        // Top Tabs has no full sidebar: its settings aren't shown there.
        let full = !state.usesTabsLayout
        Group {
            PageSection(title: "Sidebar Essentials") {
                // One switch in every layout: off, the sidebar has no essentials and pinned tabs stay ordinary pinned tabs.
                PageRow(title: "Show essentials",
                        subtitle: full ? "Pinned tabs as a grid at the top of the sidebar. Off, they stay pinned as rows in the list"
                                       : "Pinned tabs as tiles in the icon sidebar. Off, they stay pinned at the start of the tab row",
                        figure: AnyView(PinnedTabsFigure(shown: state.showsPinnedGrid, tabsLayout: !full, colors: state.palette))) {
                    Toggle("Show essentials", isOn: Binding(get: { state.showsPinnedGrid },
                        set: { on in withAnimation(.ikago) { state.browserPreferences.showPinnedGrid = on } }))
                        .labelsHidden().toggleStyle(.switch)
                }
                if state.showsPinnedGrid && full {
                    PageDivider()
                    PageRow(title: "Grid columns", subtitle: "Pinned tabs in rows of three or four") {
                        SettingsSegmented(selection: Binding(
                            get: { state.essentialsColumns },
                            set: { columns in withAnimation(.ikago) { state.browserPreferences.pinnedGridColumns = columns == 3 ? nil : columns } }
                        ), options: [(3, "3"), (4, "4")])
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
