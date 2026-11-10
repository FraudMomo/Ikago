import Foundation

enum NewTabPosition: String, CaseIterable, Identifiable {
    case top, bottom
    var id: String { rawValue }
    var title: String { self == .top ? "Newest on top" : "Newest on bottom" }
}

enum LinkTabPosition: String, CaseIterable, Identifiable {
    case beforeCurrent, afterCurrent, newTabPosition
    var id: String { rawValue }
    var title: String {
        switch self {
        case .beforeCurrent: "Before current tab"
        case .afterCurrent: "After current tab"
        case .newTabPosition: "Same as new tabs"
        }
    }
}

extension BrowserState {
    var newTabPosition: NewTabPosition {
        get { browserPreferences.newTabPosition.flatMap(NewTabPosition.init(rawValue:)) ?? .bottom }
        set { browserPreferences.newTabPosition = newValue.rawValue }
    }
    var effectiveNewTabPosition: NewTabPosition { tabLayout.usesTopTabs ? .bottom : newTabPosition }
    var effectiveLinkTabPosition: LinkTabPosition { tabLayout.usesTopTabs ? .afterCurrent : linkTabPosition }

    var linkTabPosition: LinkTabPosition {
        get { browserPreferences.linkTabPosition.flatMap(LinkTabPosition.init(rawValue:)) ?? .afterCurrent }
        set { browserPreferences.linkTabPosition = newValue.rawValue }
    }

    /// One insertion policy for links, Cmd-click, middle-click and WebKit popup adoption.
    /// Keep the opener's Space/profile even when it is no longer the foreground Space.
    @discardableResult
    func newTabFromLink(url: String, opener: TabItem, select: Bool) -> TabItem? {
        switch effectiveLinkTabPosition {
        case .newTabPosition:
            return newTab(url: url, select: select, in: opener.spaceID)
        case .beforeCurrent, .afterCurrent:
            if opener.pinned {
                // Unpinned links cannot enter the pinned grid; place them at the start of loose tabs.
                let first = tabs.first { $0.spaceID == opener.spaceID && !$0.pinned && $0.folderID == nil }
                return newTab(url: url, select: select, before: first?.id, in: opener.spaceID)
            }
            let result = newTab(url: url, select: select,
                                after: effectiveLinkTabPosition == .afterCurrent ? opener.id : nil,
                                before: effectiveLinkTabPosition == .beforeCurrent ? opener.id : nil,
                                in: opener.spaceID, folderID: opener.folderID)
            if select, let folder = opener.folderID, let index = folders.firstIndex(where: { $0.id == folder }) {
                folders[index].isOpen = true
            }
            return result
        }
    }
}
