#if DEBUG
import AppKit

@MainActor
enum SidebarVisibilityChecks {
    static func run(_ browser: BrowserWindowController) async {
        let state = browser.state, saved = state.snapshot()
        var failures = 0
        func check(_ value: Bool, _ label: String) {
            if !value { failures += 1 }
            print("IKTEST sidebarvisibility \(value ? "PASS" : "FAIL") \(label)")
        }
        func settle() async { try? await Task.sleep(for: .milliseconds(450)) }
        defer { state.apply(saved) }
        state.tabLayout = .vertical; state.sidebarVisible = true
        state.browserPreferences.sidebarCompact = false
        state.useGlass = false
        state.tabs = []; state.folders = []; state.splits = []
        let first = state.newTab(url: InternalPage.notes.url)!
        let second = state.newTab(url: InternalPage.history.url)!
        await settle()
        func visible(_ tab: TabItem) -> Bool {
            LayoutChecks.frames["sidebar-tab-\(tab.id)"].map { $0.height > 30 && $0.width > 50 } == true
        }
        check(visible(first) && visible(second), "initial loose tabs render without an appearance bootstrap")
        state.createFolder(named: "Visible group", with: first.id)
        await settle()
        check(visible(first), "moving a tab into a newly mounted group keeps its row visible")
        if let group = state.spaceFolders.first {
            state.toggleFolder(group.id); await settle()
            LayoutChecks.frames["sidebar-tab-\(first.id)"] = nil
            state.toggleFolder(group.id); await settle()
            check(visible(first), "reopening a group mounts its tabs immediately")
        }
        state.closeTab(second.id); await settle()
        let third = state.newTab(url: InternalPage.bookmarks.url)!
        await settle()
        check(visible(third), "an empty loose-tab list accepts its first new row")
        first.playback.available = true; first.playback.playing = true
        first.playback.hasVideo = true; first.playback.title = "Video fixture"
        await settle()
        check(LayoutChecks.frames["media-pip-button"].map { $0.width >= 20 && $0.height >= 20 } == true,
              "video media exposes a PiP button in the collapsed island")
        check(MediaPlaybackState(["hasVideo":true]).hasVideo, "video capability reaches the native media model")
        print("IKTEST sidebarvisibilitychecks \(failures == 0 ? "PASS" : "FAIL") failures=\(failures)")
    }
}
#endif
