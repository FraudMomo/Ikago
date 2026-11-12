import Foundation

extension BrowserState {
    var sidebarOnRight: Bool {
        get { browserPreferences.sidebarOnRight == true }
        set { browserPreferences.sidebarOnRight = newValue }
    }
    var sidebarLightsFollow: Bool {
        get { browserPreferences.sidebarLightsFollow ?? true }
        set { browserPreferences.sidebarLightsFollow = newValue }
    }
    var barAtBottom: Bool {
        get { browserPreferences.barAtBottom == true }
        set { browserPreferences.barAtBottom = newValue }
    }
}

extension BrowserState {
    /// Seed both layouts on enable; later customization, including removal, survives relaunch.
    func preparePageAssistantToolbar() {
        if !chromeLayout.contains(.assistant, inTopBar: true) { chromeLayout.place(.assistant, in: .topBarTrailing) }
        if !chromeLayout.contains(.assistant, inTopBar: false) { chromeLayout.place(.assistant, in: .sidebarTop) }
        browserPreferences.assistantToolbarInitialized = true
    }

    /// Optional features keep their saved placement while hidden from the live toolbar.
    func visibleChromeItems(_ items: [ChromeItem]) -> [ChromeItem] {
        items.filter { $0 != .assistant || browserPreferences.pageIntelligence == true }
    }
}
