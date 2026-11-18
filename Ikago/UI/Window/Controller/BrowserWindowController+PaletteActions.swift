import AppKit
import SwiftUI

/// What the address field's actions run (`PaletteAction`): window commands that have no menu item of their own, and
/// those that take an argument (`PaletteActionSender.argument`): a mode, a layout, a Settings page or setting.
extension BrowserWindowController {
    private func argument(_ sender: Any?) -> String? { (sender as? PaletteActionSender)?.argument }

    // MARK: Settings

    /// A Settings page by its `SettingsCategory` raw value.
    @objc func openSettingsCategory(_ sender: Any?) {
        if let raw = argument(sender), let category = SettingsCategory(rawValue: raw) { state.settingsCategory = category }
        showSettings()
    }

    /// One setting (`SettingsSearchEntry.id`): its page, scrolled to its section, which is outlined for a moment.
    @objc func openSetting(_ sender: Any?) {
        guard let id = argument(sender), let entry = SettingsSearch.index.first(where: { $0.id == id }) else { return showSettings() }
        state.settingsCategory = entry.category
        state.pendingSettingsSection = entry.section
        showSettings()
    }

    /// Clear Browsing Data, as the History page and Settings open it: a period and what to remove.
    @objc func clearBrowsingHistory(_ sender: Any?) { showClearData() }

    func showClearData() {
        dismissCommandPalette()
        chrome.showClearData = true
    }

    // MARK: Appearance

    @objc func setColorModeNamed(_ sender: Any?) {
        guard let mode = argument(sender).flatMap(ColorMode.init(rawValue:)) else { return }
        withAnimation(.ikago) { state.colorMode = mode }
    }

    @objc func setLayoutNamed(_ sender: Any?) {
        LayoutSwitch.set(tabs: argument(sender) == "tabs", state: state)
    }

    /// full | icons | hidden. Top Tabs has no full sidebar, so there it shows the icons.
    @objc func setSidebarStyleNamed(_ sender: Any?) {
        chrome.peeking = false
        let style = argument(sender)
        withAnimation(.ikago) {
            state.sidebarVisible = style != "hidden"
            if style == "icons" { state.browserPreferences.sidebarCompact = true }
            if style == "full" { state.browserPreferences.sidebarCompact = nil }
        }
    }

    @objc func toggleSidebarSide(_ sender: Any?) {
        withAnimation(.ikago) { state.browserPreferences.sidebarOnRight = state.sidebarOnRight ? nil : true }
    }

    @objc func toggleLiquidGlass(_ sender: Any?) { withAnimation(.ikago) { state.useGlass.toggle() } }

    @objc func toggleFrostedSidebar(_ sender: Any?) {
        withAnimation(.ikago) { state.browserPreferences.translucentSidebar = state.browserPreferences.translucentSidebar == true ? false : true }
    }

    // MARK: Tabs and split view

    /// The same page in a new tab right after this one.
    @objc func duplicateTab(_ sender: Any?) {
        guard let tab = state.activeTab else { return }
        state.newTab(url: tab.url, after: tab.pinned ? nil : tab.id, in: tab.spaceID, folderID: tab.folderID)
    }

    /// Closes this Space's other unpinned tabs; the active tab and its split partners stay.
    @objc func closeOtherTabs(_ sender: Any?) {
        guard let active = state.activeTabID else { return }
        let keep = Set(state.splitGroup(of: active) ?? [active])
        for tab in state.spaceTabs where !tab.pinned && !keep.contains(tab.id) { closeTab(tab.id) }
    }

    @objc func unloadActiveTab(_ sender: Any?) { if let id = state.activeTabID { unloadTab(id) } }

    @objc func newGroupWithActiveTab(_ sender: Any?) { newFolder(with: state.activeTabID) }

    @objc func setSplitLayoutNamed(_ sender: Any?) {
        guard let layout = argument(sender).flatMap(SplitLayout.init(rawValue:)) else { return }
        if let id = state.activeTabID, state.splitGroup(of: id) == nil { state.splitActive() }
        state.splitLayout = layout
    }

    @objc func separateActiveTab(_ sender: Any?) { if let id = state.activeTabID { state.separate(id) } }
}
