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
}

extension BrowserState {
    /// Seed the sidebar's toolbar on enable; later customization, including removal, survives relaunch.
    func preparePageAssistantToolbar() {
        if !chromeLayout.contains(.assistant) { chromeLayout.place(.assistant, in: .sidebarTop) }
        browserPreferences.assistantToolbarInitialized = true
    }

    /// Optional features keep their saved placement while hidden from the live toolbar.
    func visibleChromeItems(_ items: [ChromeItem]) -> [ChromeItem] {
        items.filter { $0 != .assistant || browserPreferences.pageIntelligence == true }
    }
}
