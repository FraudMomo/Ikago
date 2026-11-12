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
