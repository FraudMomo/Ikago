import AppKit

@MainActor
enum CEFPageGrabChecks {
    static func run(_ shell: BrowserWindowController) throws {
        guard let window = shell.window else { throw CEFError.noResult }
        let content = shell.content.view
        let grab = PageWindowGrab(content: content, state: shell.state)
        defer { grab.stop() }
        func event(y: CGFloat, modifiers: NSEvent.ModifierFlags = [], clicks: Int = 1) throws -> NSEvent {
            let point = CGPoint(x: content.bounds.midX, y: content.isFlipped ? y : content.bounds.height - y)
            guard let event = NSEvent.mouseEvent(with: .leftMouseDown, location: content.convert(point, to: nil),
                modifierFlags: modifiers, timestamp: ProcessInfo.processInfo.systemUptime,
                windowNumber: window.windowNumber, context: nil, eventNumber: 0, clickCount: clicks, pressure: 1) else { throw CEFError.noResult }
            return event
        }
        guard try grab.starts(event(y: 2)),
              try !grab.starts(event(y: 30)),
              try !grab.starts(event(y: 2, modifiers: .command)),
              try !grab.starts(event(y: 2, clicks: 2)) else {
            throw CEFError.script("CEF page-edge grab eligibility or click exclusion failed.")
        }
        print("CEF_PAGE_GRAB_OK actual-hit-test top-edge modified-double-interior-exclusions")
    }
}
