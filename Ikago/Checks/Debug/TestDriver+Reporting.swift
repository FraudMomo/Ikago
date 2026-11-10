#if DEBUG
import AppKit
import SwiftUI
import WebKit

/// What the test driver prints and saves: window snapshots and the `dump` state line.
extension TestDriver {
    /// Renders a SwiftUI view in an off-screen window to a PNG (no Screen Recording permission needed).
    static func render(_ view: some View, size: NSSize, to path: String) async {
        let host = NSHostingView(rootView: view.frame(width: size.width, height: size.height))
        host.frame = NSRect(origin: .zero, size: size)
        let window = NSWindow(contentRect: host.frame, styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = host
        window.setFrameOrigin(NSPoint(x: -4000, y: -4000))
        window.orderBack(nil)
        try? await Task.sleep(for: .milliseconds(1500))
        host.layoutSubtreeIfNeeded()
        if let image = host.bitmapImageRepForCachingDisplay(in: host.bounds) {
            host.cacheDisplay(in: host.bounds, to: image)
            try? image.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: path))
            print("IKTEST rendered \(path)")
        }
        window.orderOut(nil)
    }

    /// Renders the window's own view tree (no Screen Recording permission needed).
    static func snapshot(_ window: NSWindow?, to path: String) {
        guard let view = window?.contentView?.superview ?? window?.contentView,
              let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { return }
        view.cacheDisplay(in: view.bounds, to: rep)
        try? rep.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: path))
        print("IKTEST snapshot \(path)")
    }

    static func dump(_ c: BrowserWindowController) {
        let s = c.state
        let tabs: [[String: Any]] = s.tabs.map { t in
            let ctl = c.content.controller(for: t.id)
            return ["id": String(t.id.suffix(4)), "url": t.url, "title": String(t.title.prefix(30)), "pinned": t.pinned,
                    "space": s.spaces.firstIndex { $0.id == t.spaceID }.map { $0 + 1 } ?? 0,
                    "folder": t.folderID.flatMap { id in s.folders.first { $0.id == id }?.name } ?? "",
                    "audio": t.isPlayingAudio,
                    "hibernating": t.isHibernating, "loading": t.isLoading, "error": t.loadError ?? "", "started": ctl?.isStarted ?? false,
                    "shown": ctl.map { !$0.hostView.isHiddenOrHasHiddenAncestor && $0.hostView.window != nil } ?? false,
                    "width": Int(ctl?.hostView.frame.width ?? 0), "muted": ctl?.page?.isMuted ?? false,
                    "zoom": ctl?.page.map { Double(Int($0.zoomLevel * 10)) / 10 } ?? 0]
        }
        var windows = NSApp.windows.filter(\.isVisible).map { "\(type(of: $0))" }
        if c.window?.attachedSheet != nil { windows.append("sheet") }
        let info: [String: Any] = [
            "active": s.activeTabID.map { String($0.suffix(4)) } ?? "nil",
            "visible": s.visibleTabIDs.map { String($0.suffix(4)) },
            "splits": s.splits.map { $0.map { String($0.suffix(4)) } }, "splitLayout": s.splitLayout.rawValue, "closed": s.closed.count,
            "history": s.history.count, "layout": s.tabLayout.rawValue, "dark": s.isDark, "sidebarVisible": s.sidebarVisible,
            "spaces": s.spaces.map { "\($0.name)\($0.isolated ? "*" : "")" }, "activeSpace": s.activeSpace.name,
            "folders": s.folders.map { "\($0.name):\($0.isOpen ? "open" : "closed")" },
            "sidebar": s.sidebarOrder.map { String($0.id.suffix(4)) },
            "pages": s.tabs.filter { c.content.controller(for: $0.id)?.isStarted == true }.count,
            "tabOverview": c.chrome.showTabOverview, "settingsCategory": s.settingsCategory.rawValue, "paletteShown": c.chrome.showPalette, "peeking": c.chrome.peeking, "errorShown": c.activeController?.hostView.subviews.count ?? 0 > 1,
            "downloads": DownloadCenter.shared.items.map { "\($0.fileURL?.lastPathComponent ?? "?"):\($0.finished)" },
            "find": "\(c.find.activeMatch)/\(c.find.matchCount)",
            "windows": windows, "tabs": tabs,
        ]
        if let data = try? JSONSerialization.data(withJSONObject: info, options: [.sortedKeys]),
           let line = String(data: data, encoding: .utf8) {
            print("IKTEST \(line)")
        }
        fflush(stdout)
    }
}

extension NSView {
    func firstSubview<T: NSView>(of type: T.Type) -> T? {
        if let match = self as? T { return match }
        for child in subviews { if let match = child.firstSubview(of: type) { return match } }
        return nil
    }
}
#endif
