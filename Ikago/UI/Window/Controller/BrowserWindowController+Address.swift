import AppKit
import SwiftUI
import WebKit

extension BrowserWindowController {
    /// ⌘L / ⌘T. Integrated style edits in place (the sidebar's address field); a new tab first opens a
    /// blank tab. Floating style shows the command bar.
    func showCommandPalette(newTab: Bool) {
        chrome.showDownloads = false
        // Take the keyboard from the page first: pages that focus their own input (Momentum's
        // new-tab page) would otherwise keep it. The field then takes it (focusAddressField).
        if let window = window as? BrowserWindow { window.clearAddressFocus() }
        else { window?.makeFirstResponder(nil) }
        defer { focusAddressField() }
        guard canUseInlineAddress else {
            palette.prepare(mode: newTab ? .newTab : .currentTab)
            chrome.editingTabID = state.activeTabID
            withAnimation(nil) {
                chrome.inlineAddress = false
                chrome.showPalette = true
            }
            return
        }
        if newTab || state.activeTab == nil {
            withAnimation(nil) { _ = state.newTab(url: "about:blank") }
        }
        palette.prepare(mode: .currentTab)
        chrome.editingTabID = state.activeTabID
        withAnimation(nil) {
            chrome.showPalette = false
            chrome.inlineAddress = true
        }
    }

    /// Gives the keyboard to the address field once SwiftUI has shown it. Also covers the field
    /// already being on screen (editing restarted), where it wouldn't refocus by itself.
    private func focusAddressField() {
        let target = chrome.editingTabID
        let focus: @MainActor (Bool) -> Void = { [weak self] selectAll in
            guard let self, !self.state.isFrozen, self.isEditingAddress, self.chrome.editingTabID == target,
                  let window = self.window, let root = window.contentView else { return }
            var fields: [FocusingTextField] = []
            @MainActor func find(_ view: NSView) {
                if let field = view as? FocusingTextField, !field.isHiddenOrHasHiddenAncestor { fields.append(field) }
                view.subviews.forEach(find)
            }
            find(root)
            guard let field = fields.last else { return }
            if let editor = field.currentEditor(), window.firstResponder === editor { return }
            window.makeFirstResponder(field)
            // Never over letters already typed: the next keystroke would replace them.
            if selectAll && !self.palette.edited { field.currentEditor()?.selectAll(nil) } else { field.placeCaretAfterTyping() }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { focus(true) }
        // Removing an outgoing SwiftUI field can end the shared AppKit field editor.
        // Recheck through the outgoing layout transition without selecting newly typed text.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { focus(false) }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { focus(false) }
    }

    /// The page gets the keyboard back only when nothing is being typed into the chrome.
    var isEditingAddress: Bool { chrome.inlineAddress || chrome.showPalette }

    func dismissCommandPalette() {
        palette.cancelCompletions()
        withAnimation(nil) {
            chrome.showPalette = false
            chrome.inlineAddress = false
        }
        chrome.editingTabID = nil
        let controller = activeController
        DispatchQueue.main.async { [weak self, weak controller] in
            guard let self, !self.isEditingAddress, self.activeController === controller else { return }
            controller?.focus()
        }
    }

    /// ⌘T and + keep the chosen page provider; the address field takes focus when that is turned on.
    func newTab() {
        let previous = state.activeTabID
        switch state.newTabMode {
        case .commandBar:
            showCommandPalette(newTab: true)
            return
        case .homepage:
            guard let url = try? AddressResolver.resolve(state.homepage, engine: state.searchEngine) else {
                showCommandPalette(newTab: true)
                return
            }
            open(url, inNewTab: true)
        case .extensionPage:
            // Chromium keeps extensions per Space and learns them from a hidden service page: when this
            // Space's list isn't loaded yet, load it (catching up the sync too), then open the page.
            if BrowserRuntime.engine == .chromium, !state.isPrivate,
               ChromiumExtensions.shared.profile != state.activeSpace.profileID {
                let profile = state.activeSpace.profileID
                Task { @MainActor [weak self] in
                    await ChromiumExtensions.shared.sync(profile: profile)
                    guard let self, self.state.activeSpace.profileID == profile else { return }
                    if let url = NewTabProviders.page(chosen: self.state.newTabExtensionID) {
                        withAnimation(nil) { _ = self.openTabForExtension(url: url.absoluteString, active: true, pinned: false, useNewTabPosition: true) }
                    } else {
                        self.showCommandPalette(newTab: true)
                    }
                }
                return
            }
            // Private windows have no extensions on Chromium.
            guard !(BrowserRuntime.engine == .chromium && state.isPrivate),
                  let url = NewTabProviders.page(chosen: state.newTabExtensionID) else {
                showCommandPalette(newTab: true)
                return
            }
            withAnimation(nil) { _ = openTabForExtension(url: url.absoluteString, active: true, pinned: false, useNewTabPosition: true) }
        }
        if state.focusAddressBarOnNewTab, state.activeTabID != previous {
            showCommandPalette(newTab: false)
        }
    }

    /// The sidebar edits in place unless the floating command bar is chosen. The icon rail has no address
    /// field, so it uses the floating one.
    private var canUseInlineAddress: Bool {
        guard state.addressStyle == .integrated else { return false }
        // Sidebar + Tabs edits in its address bar above the page.
        if state.showsSidebarTopTabs { return true }
        return state.sidebarVisible && !state.showsSidebarRail && state.chromeLayout.sidebarShowsAddress
    }
}
