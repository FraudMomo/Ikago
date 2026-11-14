import AppKit

/// Several tabs picked together (`TabClick`, `ChromeModel.selectedTabIDs`): what their menu does with them all.
extension BrowserWindowController {
    func tabSelection(including id: String) -> [String] { TabClick.group(including: id, state: state, chrome: chrome) }

    func moveTabsToNewWindow(_ ids: [String]) {
        chrome.selectedTabIDs = []
        BrowserWindows.moveToNewWindow(ids, from: self)
    }

    func closeTabs(_ ids: [String]) {
        chrome.selectedTabIDs = []
        for id in ids { closeTab(id) }
    }

    func moveTabs(_ ids: [String], toFolder folderID: String?) {
        chrome.selectedTabIDs = []
        for id in ids { state.moveToFolder(id, folderID: folderID) }
    }

    /// A new group holding the tabs, named by the person.
    func newFolder(withTabs ids: [String]) {
        Task {
            guard let name = await TextPrompt.ask("New Group", value: "", in: window) else { return }
            let folder = state.createFolder(named: name, with: ids.first)
            for id in ids.dropFirst() { state.moveToFolder(id, folderID: folder.id) }
            chrome.selectedTabIDs = []
        }
    }
}
