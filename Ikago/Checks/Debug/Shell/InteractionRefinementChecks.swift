#if DEBUG
import AppKit
import WebKit

@MainActor
enum InteractionRefinementChecks {
    static func run(_ browser: BrowserWindowController, base: String) async {
        let state = browser.state, saved = state.snapshot()
        var failures = 0
        func check(_ value: Bool, _ label: String) {
            if !value { failures += 1 }
            print("IKTEST refinement \(value ? "PASS" : "FAIL") \(label)")
        }
        func settle() async { try? await Task.sleep(for: .milliseconds(450)) }
        defer {
            browser.closePeek(); browser.chrome.textPrompt?.finish(nil)
            browser.chrome.showNotes = false; browser.chrome.showPageAssistant = false
            state.apply(saved)
        }
        browser.dismissCommandPalette()
        let count = state.tabs.count
        browser.openPage(.notes)
        check(browser.chrome.showNotes && state.tabs.count == count, "Notes opens as an overlay without creating a tab")
        browser.chrome.showNotes = false
        state.createFolder(named: "Rename fixture", with: nil)
        if let folder = state.spaceFolders.last {
            browser.renameFolder(folder.id); await settle()
            check(browser.chrome.textPrompt?.placeholder == "Rename fixture", "integrated rename preserves the current name as its placeholder")
            browser.chrome.textPrompt?.text = "Renamed"
            browser.chrome.textPrompt?.confirm(); await settle()
            check(state.spaceFolders.last?.name == "Renamed", "integrated rename commits through its continuation")
        }
        let active = state.activeTabID
        browser.peekLink(base)
        await settle()
        check(browser.chrome.previewTabID != nil && browser.peekContent != nil && state.activeTabID == active,
              "link peek presents live content without navigating the underlying tab")
        check(browser.peekController?.isActive == true, "a peeked page is protected as visible")
        browser.closePeek()
        check(browser.peekContent == nil, "closing peek releases its transient controller")
        let lazy = TabItem(url: "https://unopened.invalid", spaceID: state.activeSpaceID)
        check(lazy.isUnloaded, "never-started pages share unloaded presentation with hibernated pages")
        print("IKTEST refinementchecks \(failures == 0 ? "PASS" : "FAIL") failures=\(failures)")
    }
}
#endif
