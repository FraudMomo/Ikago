import SwiftUI

struct EssentialsSettingsSection: View {
    @Bindable var state: BrowserState

    var body: some View {
        if state.tabLayout == .vertical {
            PageSection(title: "Sidebar Essentials") {
                PageRow(title: "Show pinned-tab grid", subtitle: "Pinned tabs as a grid at the top of the sidebar") {
                    Toggle("Show pinned-tab grid", isOn: Binding(get: { state.showsPinnedGrid },
                        set: { state.browserPreferences.showPinnedGrid = $0 })).labelsHidden().toggleStyle(.switch)
                }
            }
        } else {
            PageSection(title: "Pinned Essentials") {
                PageRow(title: "Show pinned tabs", subtitle: "Keep essentials in the tab strip.") {
                    Toggle("Show pinned tabs", isOn: Binding(
                        get: { state.showsTopBarEssentials && state.showsTopBarPins },
                        set: { state.showsTopBarEssentials = $0; state.showsTopBarPins = $0 }
                    ).animation(.ikago)).labelsHidden().toggleStyle(.switch)
                }
            }
        }
        PageSection(title: "Bookmarks Bar", footer: "Toggle with ⇧⌘B.") {
            PageRow(title: "Show bookmarks bar", subtitle: "A row below the toolbar, or a drawer in the sidebar") {
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
