import SwiftUI

struct EssentialsSettingsSection: View {
    @Bindable var state: BrowserState

    var body: some View {
        if state.tabLayout == .vertical {
            PageSection(title: "Sidebar Essentials", footer: "Pinned tabs belong to this Space. Hidden pins remain in the tab list.") {
                PageRow(title: "Show pinned-tab grid", subtitle: "Live tabs kept in this Space.") {
                    Toggle("Show pinned-tab grid", isOn: Binding(get: { state.showsPinnedGrid },
                        set: { state.browserPreferences.showPinnedGrid = $0 })).labelsHidden().toggleStyle(.switch)
                }
            }
        } else {
            PageSection(title: "Pinned Essentials", footer: "Hidden pins remain accessible in the tab sidebar. Sidebar grid settings are independent.") {
                PageRow(title: "Show pinned tabs", subtitle: "Keep essentials in the tab strip.") {
                    Toggle("Show pinned tabs", isOn: Binding(
                        get: { state.showsTopBarEssentials && state.showsTopBarPins },
                        set: { state.showsTopBarEssentials = $0; state.showsTopBarPins = $0 }
                    ).animation(.ikago)).labelsHidden().toggleStyle(.switch)
                }
            }
        }
        PageSection(title: "Bookmarks Bar", footer: "Folders and bookmarks are shared across Spaces. Organize them in Bookmarks. Toggle this surface with ⇧⌘B.") {
            PageRow(title: "Show bookmarks bar", subtitle: "A separate row in Top Bar mode, or a collapsible drawer at the bottom of the sidebar.") {
                Toggle("Show bookmarks bar", isOn: $state.showsBookmarksBar.animation(.ikago)).labelsHidden().toggleStyle(.switch)
            }
        }
    }
}

struct BookmarkOpeningSection: View {
    let state: BrowserState

    var body: some View {
        PageSection(title: "Opening Bookmarks", footer: "New addresses preserve pinned tabs. Closing a pin unloads it and keeps it in Essentials.") {
            PageRow(title: "Switch to an open tab", subtitle: "When off, bookmarks always open a new tab.") {
                Toggle("Switch to an open tab", isOn: Binding(get: { state.browserPreferences.reuseBookmarkTabs ?? true },
                    set: { state.browserPreferences.reuseBookmarkTabs = $0 })).labelsHidden().toggleStyle(.switch)
            }
            if state.browserPreferences.reuseBookmarkTabs ?? true {
                PageDivider()
                PageRow(title: "Match open tabs", subtitle: "Only tabs in the current Space.") {
                    Picker("Match open tabs", selection: Binding(get: { state.browserPreferences.bookmarkMatchDomain ?? false },
                        set: { state.browserPreferences.bookmarkMatchDomain = $0 })) {
                        Text("Same page URL").tag(false)
                        Text("Same domain").tag(true)
                    }.labelsHidden()
                }
            }
        }
    }
}
