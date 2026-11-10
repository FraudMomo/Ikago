import SwiftUI

#if DEBUG
import AppKit

@MainActor
enum LayoutChecks {
    static var frames: [String: CGRect] = [:]
    static var tabEdges = TabScrollEdges()

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
        state.tabLayout = .horizontal
    }

    static func run(_ controller: BrowserWindowController) async {
        var failures = 0
        func check(_ value: Bool, _ title: String) {
            print("IKTEST sizing \(value ? "PASS" : "FAIL") \(title)")
            if !value { failures += 1 }
        }
        seed(controller)
        let state = controller.state
        let minimumLeading: CGFloat = state.topTabStyle == .separate ? 0 : 80
        state.useGlass = false
        state.frameInset = 0
        for floating in [false, true] {
            state.barRounded = floating
            for (width, height) in [(1512.0, 860.0), (700.0, 650.0), (420.0, 650.0)] {
                state.barHeight = width == 1512 ? 28 : 56
                controller.window?.setContentSize(NSSize(width: width, height: height))
                try? await Task.sleep(for: .milliseconds(600))
                controller.window?.contentView?.layoutSubtreeIfNeeded()
                let native = scrollFrames(controller)
                let strip = native.first { $0.height < 70 }
                check(strip.map { $0.minX >= minimumLeading && $0.maxX <= width + 1 && $0.width >= 60 } == true,
                      "tab viewport stays clear of traffic lights and inside \(Int(width)) pt window, floating=\(floating)")
                let active = frames["active-tab"]
                let revealed = strip.flatMap { viewport in active.map { $0.minX >= viewport.minX - 4 && $0.maxX <= viewport.maxX + 4 } } == true
                if !revealed { print("IKTEST sizing bounds active=\(String(describing: active)) viewport=\(String(describing: strip))") }
                check(revealed, "active tab scrolls fully into view after appearance or resize")
                let settings = frames["settings-content"]
                check(settings.map { $0.width <= width + 1 && $0.minX >= -1 && $0.maxX <= width + 1 } == true,
                      "Settings viewport stays inside \(Int(width)) pt window, floating=\(floating)")
                if width >= 760 {
                    check(frames["settings-navigation"].map { $0.minX >= -1 && abs($0.width - 220) < 1 } == true,
                          "wide Settings keeps its navigation column visible")
                }
            }
        }
        state.chromeLayout.topBarLeading = ChromeItem.allCases
        state.chromeLayout.topBarTrailing = []
        try? await Task.sleep(for: .milliseconds(600))
        check(scrollFrames(controller).first { $0.height < 70 }.map { $0.minX >= minimumLeading && $0.maxX <= 421 && $0.width >= 60 } == true,
              "customized toolbar leaves room for tabs using overflow")
        state.chromeLayout.topBarLeading = []
        state.chromeLayout.topBarOuterLeading = ChromeItem.allCases
        state.barRounded = false
        try? await Task.sleep(for: .milliseconds(600))
        check(scrollFrames(controller).first { $0.height < 70 }.map { $0.minX >= minimumLeading && $0.maxX <= 421 && $0.width >= 60 } == true,
              "outside toolbar controls fold into overflow before squeezing the island")
        for category in SettingsCategory.allCases {
            state.settingsCategory = category
            try? await Task.sleep(for: .milliseconds(150))
            check(frames["settings-content"].map { $0.width <= 421 && $0.minX >= -1 && $0.maxX <= 421 } == true,
                  "\(category.title) stays contained in narrow Settings")
        }
        state.chromeLayout = ChromeLayout()
        state.useGlass = true
        controller.window?.setContentSize(NSSize(width: 1100, height: 750))
        try? await Task.sleep(for: .milliseconds(600))
        controller.showCommandPalette(newTab: false)
        try? await Task.sleep(for: .milliseconds(300))
        check(scrollFrames(controller).first { $0.height < 70 }.map { $0.minX >= minimumLeading && $0.maxX <= 1101 } == true,
              "glass surfaces and inline address editing keep the same bounded viewport")
        print("IKTEST sizingchecks \(failures == 0 ? "PASS" : "FAIL") failures=\(failures)")
    }

    private static func scrollFrames(_ controller: BrowserWindowController) -> [CGRect] {
        var frames: [CGRect] = []
        func inspect(_ view: NSView) {
            if let scroll = view as? NSScrollView, !scroll.isHiddenOrHasHiddenAncestor {
                frames.append(scroll.convert(scroll.bounds, to: controller.window?.contentView))
            }
            view.subviews.forEach(inspect)
        }
        if let root = controller.window?.contentView { inspect(root) }
        return frames
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
