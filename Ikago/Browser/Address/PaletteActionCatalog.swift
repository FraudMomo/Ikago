import Foundation

extension PaletteAction {
    /// The browser's commands, grouped as in the menus. Keywords are the other words people type for them.
    static let builtIn: [PaletteAction] = tabs + windows + splits + appearance + pages + places

    private static let tabs: [PaletteAction] = [
        .init("newTab", "New Tab", "plus.square.on.square", "⌘T", "open", "newTab:"),
        .init("closeTab", "Close Tab", "xmark.square", "⌘W", "close remove tab", "closeCurrentTab:"),
        .init("reopen", "Reopen Closed Tab", "arrow.uturn.backward", "⇧⌘T", "undo restore closed", "reopenClosedTab:"),
        .init("duplicate", "Duplicate Tab", "plus.square.on.square.fill", "", "duplicate copy clone tab", "duplicateTab:"),
        .init("closeOthers", "Close Other Tabs", "xmark.square.fill", "", "close other tabs clean", "closeOtherTabs:"),
        .init("unload", "Unload Tab", "moon.zzz", "", "sleep hibernate unload memory free", "unloadActiveTab:"),
        .init("nextTab", "Next Tab", "arrow.right.square", "⌃⇥", "switch next tab", "nextTab:"),
        .init("previousTab", "Previous Tab", "arrow.left.square", "⌃⇧⇥", "switch previous tab", "previousTab:"),
        .init("pin", "Pin or Unpin Tab", "pin", "", "pin unpin", "togglePinTab:"),
        .init("mute", "Mute or Unmute Tab", "speaker.slash", "", "sound audio mute", "toggleMuteTab:"),
        .init("group", "New Group with This Tab", "folder.badge.plus", "", "group folder organize", "newGroupWithActiveTab:"),
    ]

    private static let windows: [PaletteAction] = [
        .init("newWindow", "New Window", "macwindow.badge.plus", "⌘N", "window open another", "newWindow:"),
        .init("moveToWindow", "Move Tab to New Window", "macwindow.on.rectangle", "", "window detach tear off separate", "moveTabToNewWindow:"),
        .init("privateWindow", "New Private Window", "eye.slash", "⌥⌘N", "incognito private window", "newPrivateWindow:"),
        .init("fullScreen", "Enter or Exit Full Screen", "arrow.up.left.and.arrow.down.right", "⌃⌘F", "full screen fullscreen", "toggleFullScreen:"),
        .init("newSpace", "New Space", "square.stack", "", "space profile workspace", "newSpaceAction:"),
        .init("nextSpace", "Next Space", "arrow.right.square", "", "space switch", "nextSpace:"),
        .init("previousSpace", "Previous Space", "arrow.left.square", "", "space switch", "previousSpace:"),
    ]

    private static let splits: [PaletteAction] = [
        .init("split", "Split View", "rectangle.split.2x1", "", "side by side split two", "splitView:"),
        .init("unsplit", "Close Split View", "rectangle", "", "unsplit separate exit split", "unsplitView:"),
        .init("rotateSplit", "Rotate Split View", "rectangle.split.1x2", "", "split rotate orientation vertical horizontal", "toggleSplitOrientation:"),
        .init("splitColumns", "Split Side by Side", "rectangle.split.3x1", "", "split columns layout", "setSplitLayoutNamed:", argument: "columns"),
        .init("splitRows", "Split Stacked", "rectangle.split.1x2", "", "split rows layout stacked", "setSplitLayoutNamed:", argument: "rows"),
        .init("splitGrid", "Split in a Grid", "rectangle.split.2x2", "", "split grid layout four", "setSplitLayoutNamed:", argument: "grid"),
        .init("separate", "Take Tab Out of Split View", "rectangle.portrait.and.arrow.right", "", "split separate remove detach", "separateActiveTab:"),
    ]

    private static let appearance: [PaletteAction] = [
        .init("light", "Light Mode", "sun.max", "", "light appearance theme bright day", "setColorModeNamed:", argument: "light"),
        .init("dark", "Dark Mode", "moon", "", "dark appearance theme night", "setColorModeNamed:", argument: "dark"),
        .init("system", "Match System Appearance", "circle.lefthalf.filled", "", "system auto appearance theme light dark", "setColorModeNamed:", argument: "system"),
        .init("layoutSidebar", "Sidebar Layout", "sidebar.left", "", "layout sidebar vertical tabs", "setLayoutNamed:", argument: "sidebar"),
        .init("layoutTabs", "Top Tabs Layout", "menubar.rectangle", "", "layout top tabs horizontal", "setLayoutNamed:", argument: "tabs"),
        .init("sidebarFull", "Full Sidebar", "sidebar.left", "", "sidebar show full expand", "setSidebarStyleNamed:", argument: "full"),
        .init("sidebarIcons", "Icon Sidebar", "sidebar.squares.left", "⌃⌘S", "sidebar compact icons rail", "setSidebarStyleNamed:", argument: "icons"),
        .init("sidebarHide", "Hide Sidebar", "rectangle", "⇧⌘S", "sidebar hide collapse", "setSidebarStyleNamed:", argument: "hidden"),
        .init("sidebarSide", "Move Sidebar to the Other Side", "arrow.left.arrow.right", "", "sidebar left right side", "toggleSidebarSide:"),
        .init("glass", "Turn Liquid Glass On or Off", "drop", "", "glass liquid transparency flat", "toggleLiquidGlass:"),
        .init("frosted", "Turn Frosted Sidebar On or Off", "square.on.square.dashed", "", "frosted blur translucent transparent sidebar", "toggleFrostedSidebar:"),
        .init("bookmarksBar", "Show or Hide Bookmarks", "book", "⇧⌘B", "bookmarks bar drawer", "toggleBookmarksBar:"),
    ]

    private static let pages: [PaletteAction] = [
        .init("reload", "Reload Page", "arrow.clockwise", "⌘R", "refresh reload", "reloadPage:"),
        .init("hardReload", "Reload Without Cache", "arrow.clockwise.circle", "⇧⌘R", "hard refresh cache", "hardReloadPage:"),
        .init("copyLink", "Copy Link", "link", "⇧⌘C", "copy url address share", "copyPageAddress:"),
        .init("bookmark", "Bookmark This Page", "star", "⌘D", "save favorite", "bookmarkPage:"),
        .init("find", "Find in Page", "text.magnifyingglass", "⌘F", "search find", "findInPage:"),
        .init("zoomIn", "Zoom In", "plus.magnifyingglass", "⌘+", "zoom bigger larger text", "zoomInPage:"),
        .init("zoomOut", "Zoom Out", "minus.magnifyingglass", "⌘−", "zoom smaller text", "zoomOutPage:"),
        .init("zoomReset", "Actual Size", "1.magnifyingglass", "⌘0", "zoom reset actual", "resetPageZoom:"),
        .init("print", "Print Page", "printer", "⌘P", "print pdf", "printCurrentPage:"),
        .init("reader", "Show Reader", "doc.plaintext", "⌥⌘R", "reader mode article simplify distraction free read", "toggleReader:"),
        .init("translate", "Translate Page", "translate", "", "translate language foreign english spanish on device", "translatePage:"),
        .init("webApp", "Add to Applications…", "plus.app", "", "web app install dock launchpad application site", "installWebApp:"),
        .init("savePage", "Save Page…", "arrow.down.doc", "⌘S", "save page archive pdf long screenshot image png jpeg html text mhtml webarchive download file", "savePageAs:"),
        .init("devtools", "Developer Tools", "hammer", "⌥⌘I", "inspect developer console devtools", "toggleDevTools:"),
        .init("assistant", "Ask About This Page", "sparkles", "", "assistant ai summarize page intelligence", "askThisPage:"),
        .init("perfStats", "Show or Hide Performance Stats", "speedometer", "", "fps cpu memory stats overlay", "togglePerformanceStats:"),
    ]

    private static let places: [PaletteAction] = [
        .init("history", "Show History", "clock", "⌘Y", "view open history visited browsing pages", "showHistory:"),
        .init("clearHistory", "Clear Browsing Data…", "trash", "⇧⌘⌫", "delete remove erase clear wipe history browsing cookies cache searches", "clearBrowsingHistory:"),
        .init("clearData", "Clear Website Data…", "xmark.bin", "", "delete remove erase clear cookies cache website data sign out", "openSettingsCategory:", argument: "security"),
        .init("downloads", "Downloads", "arrow.down.circle", "⌥⌘L", "downloads files", "showDownloads:"),
        .init("bookmarks", "Bookmarks", "book", "", "bookmarks saved", "showBookmarks:"),
        .init("notes", "Notes", "note.text", "", "notes write", "showNotes:"),
        .init("performance", "Performance", "gauge.with.dots.needle.33percent", "", "memory cpu performance task manager", "showPerformance:"),
        .init("settings", "Settings", "gearshape", "⌘,", "preferences settings options", "showIkagoSettings:"),
    ]
}
