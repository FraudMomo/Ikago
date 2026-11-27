import SwiftUI

#if DEBUG
import AppKit

@MainActor
enum LayoutChecks {
    static var frames: [String: CGRect] = [:]

    static func seed(_ controller: BrowserWindowController) {
        let state = controller.state
        for group in 0..<3 {
            let folder = state.createFolder(named: group == 0 ? "Imported Group" : "Research and Development \(group)")
            state.setFolderTag(folder.id, to: [.red, .blue, .purple][group])
            for index in 0..<6 {
                state.tabs.append(TabItem(url: "https://layout.invalid/\(group)/\(index)",
                    title: "A long imported tab title for window sizing \(group) · \(index)", spaceID: state.activeSpaceID, folderID: folder.id))
            }
        }
        for index in 0..<6 {
            state.tabs.append(TabItem(url: "https://layout.invalid/loose/\(index)", title: "A separate imported tab \(index)", spaceID: state.activeSpaceID))
        }
        controller.openPage(.settings)
        state.settingsCategory = .imports
        state.browserPreferences.sidebarTopTabs = true
    }

    static func run(_ controller: BrowserWindowController) async {
        var failures = 0
        func check(_ value: Bool, _ title: String) {
            print("IKTEST sizing \(value ? "PASS" : "FAIL") \(title)")
            if !value { failures += 1 }
        }
        seed(controller)
        let state = controller.state
        state.useGlass = false
        state.frameInset = 2
        for sidebar in [true, false] {
            state.sidebarVisible = sidebar
            for (width, height) in [(1512.0, 860.0), (700.0, 650.0), (480.0, 650.0)] {
                controller.window?.setContentSize(NSSize(width: width, height: height))
                try? await Task.sleep(for: .milliseconds(600))
                controller.window?.contentView?.layoutSubtreeIfNeeded()
                let strip = frames["sidebar-top-tabs"]
                // Without a docked sidebar the row starts after the traffic lights (which end 79 pt into the window).
                check(strip.map { $0.minX >= (sidebar ? 0 : 79) && $0.maxX <= width + 1 && $0.width >= 60 } == true,
                      "tab row stays clear of the traffic lights and inside \(Int(width)) pt, sidebar=\(sidebar)")
                let active = frames["active-tab"]
                let revealed = strip.flatMap { viewport in active.map { $0.minX >= viewport.minX - 4 && $0.maxX <= viewport.maxX + 4 } } == true
                if !revealed { print("IKTEST sizing bounds active=\(String(describing: active)) viewport=\(String(describing: strip))") }
                check(revealed, "active tab scrolls fully into view after appearance or resize")
                check(lightsCentered(controller, on: state.sidebarRowCenter), "traffic lights centre on the sidebar's top row")
                let settings = frames["settings-content"]
                check(settings.map { $0.width <= width + 1 && $0.minX >= -1 && $0.maxX <= width + 1 } == true,
                      "Settings viewport stays inside \(Int(width)) pt window, sidebar=\(sidebar)")
            }
        }
        state.sidebarVisible = true
        state.browserPreferences.sidebarTopTabs = nil
        controller.window?.setContentSize(NSSize(width: 1100, height: 750))
        try? await Task.sleep(for: .milliseconds(600))
        check(lightsCentered(controller, on: state.sidebarRowCenter), "traffic lights keep their centre without the tab row")
        state.chromeLayout.sidebarTop = ChromeItem.allCases
        try? await Task.sleep(for: .milliseconds(600))
        let capacity = SidebarView.topRowCapacity(state: state)
        check(capacity < ChromeItem.allCases.count && capacity >= 1, "a crowded sidebar top row moves controls to a second row")
        for category in SettingsCategory.allCases {
            state.settingsCategory = category
            try? await Task.sleep(for: .milliseconds(150))
            check(frames["settings-content"].map { $0.minX >= -1 && $0.maxX <= 1101 } == true,
                  "\(category.title) stays contained in Settings")
        }
        state.chromeLayout = ChromeLayout()
        print("IKTEST sizingchecks \(failures == 0 ? "PASS" : "FAIL") failures=\(failures)")
    }

    /// The native buttons' vertical centre, from the window's top, matches `center`.
    private static func lightsCentered(_ controller: BrowserWindowController, on center: CGFloat) -> Bool {
        guard let window = controller.window, let root = window.contentView else { return false }
        return [NSWindow.ButtonType.closeButton, .miniaturizeButton, .zoomButton].allSatisfy { kind in
            guard let button = window.standardWindowButton(kind), !button.isHidden else { return true }
            let bounds = root.convert(button.bounds, from: button)
            let top = root.isFlipped ? bounds.midY : root.bounds.maxY - bounds.midY
            return abs(top - center) <= 1
        }
    }


    static func dump(_ controller: BrowserWindowController) {
        for key in frames.keys.sorted() {
            let r = frames[key]!
            print("IKTEST layout \(key) x=\(r.minX) y=\(r.minY) w=\(r.width) h=\(r.height)")
        }
        func inspect(_ view: NSView) {
            if let scroll = view as? NSScrollView, !scroll.isHiddenOrHasHiddenAncestor {
                let frame = scroll.convert(scroll.bounds, to: controller.window?.contentView)
                print("IKTEST native-scroll x=\(frame.minX) y=\(frame.minY) w=\(frame.width) h=\(frame.height)")
            }
            view.subviews.forEach(inspect)
        }
        if let root = controller.window?.contentView { inspect(root) }
    }
}
#endif
