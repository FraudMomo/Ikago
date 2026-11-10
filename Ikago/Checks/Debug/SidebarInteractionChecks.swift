#if DEBUG
import AppKit

@MainActor
enum SidebarInteractionChecks {
    static func run(_ browser: BrowserWindowController) async {
        let state = browser.state, original = state.snapshot(), size = browser.window?.contentView?.bounds.size
        var failures = 0
        func check(_ value: Bool, _ title: String) {
            print("IKTEST sidebarinteraction \(value ? "PASS" : "FAIL") \(title)")
            if !value { failures += 1 }
        }
        defer {
            browser.dismissCommandPalette(); state.apply(original)
            if let size { browser.window?.setContentSize(size) }
        }
        guard let window = browser.window, let root = window.contentView else { return }
        window.makeKeyAndOrderFront(nil)
        state.sidebarVisible = true; state.useGlass = false
        state.browserPreferences.searchEngineAutocomplete = false
        _ = state.newTab(url: InternalPage.history.url)
        try? await Task.sleep(for: .milliseconds(700))
        let probe = AddressClickProbe(frame: NSRect(x: 0, y: 0, width: 12, height: 12))
        root.addSubview(probe)
        defer { probe.removeFromSuperview() }
        func click(at location: NSPoint) {
            let local = root.convert(location, from: nil)
            probe.setFrameOrigin(NSPoint(x: local.x - 6, y: local.y - 6))
            for type in [NSEvent.EventType.leftMouseDown, .leftMouseUp] {
                if let event = NSEvent.mouseEvent(with: type, location: location, modifierFlags: [],
                    timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: window.windowNumber,
                    context: nil, eventNumber: 1, clickCount: 1, pressure: 1) { window.sendEvent(event) }
            }
        }
        func regions(in view: NSView) -> [AddressRegionView] {
            (view as? AddressRegionView).map { [$0] } ?? view.subviews.flatMap { regions(in: $0) }
        }
        for layout in TabLayout.allCases {
            state.tabLayout = layout
            for style in layout == .vertical ? AddressStyle.allCases : [.integrated] {
                state.addressStyle = style
                browser.showCommandPalette(newTab: false)
                browser.palette.userEdited("sidebar interaction")
                try? await Task.sleep(for: .milliseconds(500))
                let surfaces = regions(in: root).filter { !$0.visibleRect.isEmpty && !$0.isHiddenOrHasHiddenAncestor }
                check(!surfaces.isEmpty, "\(layout)/\(style) field and popup expose interaction regions")
                for surface in surfaces {
                    click(at: surface.convert(NSPoint(x: surface.bounds.midX, y: surface.bounds.midY), to: nil))
                    check(browser.isEditingAddress && browser.palette.query == "sidebar interaction",
                          "\(layout)/\(style) clicks inside address surfaces preserve editing and query")
                }
                let outside = root.convert(NSPoint(x: 20, y: root.isFlipped ? root.bounds.height - 60 : 60), to: nil)
                let delivered = probe.clicks
                // A point inside the sidebar, outside its address and suggestions.
                click(at: outside)
                check(!browser.isEditingAddress, "\(layout)/\(style) click outside dismisses the popup")
                check(probe.clicks == delivered + 1, "the dismissal click is still delivered to its original control")
                try? await Task.sleep(for: .milliseconds(200))
            }
        }
        state.tabLayout = .vertical
        for visible in [true, false] {
            state.sidebarVisible = visible
            for margin in [2.0, 8.0, 24.0] {
                state.frameInset = margin
                for width in [1100.0, 600.0] {
                    window.setContentSize(NSSize(width: width, height: 750))
                    try? await Task.sleep(for: .milliseconds(300))
                    guard let frame = LayoutChecks.frames["sidebar-page-drag-margin"] else {
                        check(false, "margin drag region is mounted"); continue
                    }
                    let top = NSPoint(x: frame.midX, y: frame.midY)
                    let point = NSPoint(x: top.x, y: root.isFlipped ? top.y : root.bounds.height - top.y)
                    let hit = root.hitTest(root.convert(point, to: root.superview))
                    check(hit is WindowDragArea.DragView, "\(Int(margin)) pt top margin routes native window dragging at \(Int(width)) pt, sidebar=\(visible)")
                    check(abs(frame.height - margin) < 0.5, "window drag region stays inside the configured margin")
                }
            }
        }
        print("IKTEST sidebarinteractionchecks \(failures == 0 ? "PASS" : "FAIL") failures=\(failures)")
    }
}

@MainActor
private final class AddressClickProbe: NSView {
    var clicks = 0
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override func mouseDown(with event: NSEvent) { clicks += 1 }
    override func mouseUp(with event: NSEvent) {}
}
#endif
