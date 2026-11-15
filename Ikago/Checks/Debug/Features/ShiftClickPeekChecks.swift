#if DEBUG
import AppKit
import WebKit

/// Shift-click on a link in a page that routes its own links (as Instagram does): Ikago peeks the clicked link, and the
/// page's own click handler never runs.
@MainActor
enum ShiftClickPeekChecks {
    static func run(_ c: BrowserWindowController, base: String) async {
        guard WebProfiles.isTestMode else { return }
        var failures = 0
        func check(_ value: Bool, _ title: String) {
            if !value { failures += 1 }
            print("IKTEST shiftpeek \(value ? "PASS" : "FAIL") \(title)")
        }
        c.open(base + "/?shift-peek", inNewTab: true)
        for _ in 0..<150 {
            if c.state.activeTab?.isLoading == false, c.activeController?.page != nil { break }
            try? await Task.sleep(for: .milliseconds(20))
        }
        _ = try? await c.activeController?.page?.evaluate("""
            document.body.innerHTML = `<a id="post" href="/p/post" style="display:block;padding:40px;margin:20px">
              <span>A post</span> <a id="profile" href="/profile" style="display:inline-block;padding:20px">the profile</a></a>`;
            window.__routed = '';
            document.addEventListener('click', e => { const a = e.target.closest('a'); if (a) { e.preventDefault(); window.__routed = a.getAttribute('href'); history.pushState({}, '', a.href); } });
            true
            """)
        try? await Task.sleep(for: .milliseconds(200))
        guard let web = c.activeController?.page?.contentView.firstDescendant(of: WKWebView.self) ?? (c.activeController?.page?.contentView as? WKWebView),
              let window = web.window else { check(false, "the page is a WebKit view"); return }
        let rect = (try? await c.activeController?.page?.evaluate(
            "(() => { const r = document.getElementById('profile').getBoundingClientRect(); return [r.x + r.width / 2, r.y + r.height / 2] })()")) as? [Double] ?? [0, 0]
        let point = web.convert(NSPoint(x: rect[0], y: web.isFlipped ? rect[1] : web.bounds.height - rect[1]), to: nil)
        for type in [NSEvent.EventType.leftMouseDown, .leftMouseUp] {
            guard let event = NSEvent.mouseEvent(with: type, location: point, modifierFlags: .shift, timestamp: ProcessInfo.processInfo.systemUptime,
                                                 windowNumber: window.windowNumber, context: nil, eventNumber: 0, clickCount: 1, pressure: 1) else { continue }
            if type == .leftMouseDown { web.mouseDown(with: event) } else { web.mouseUp(with: event) }
            try? await Task.sleep(for: .milliseconds(60))
        }
        for _ in 0..<60 where c.peekTab == nil { try? await Task.sleep(for: .milliseconds(50)) }
        check(c.peekTab?.url.hasSuffix("/profile") == true, "Shift-click peeks the clicked link (\(c.peekTab?.url ?? "no peek"))")
        let routed = (try? await c.activeController?.page?.evaluate("window.__routed")) as? String ?? "?"
        check(routed.isEmpty, "the page's own router never saw the click (\(routed))")
        check(c.activeController?.page?.currentURL.contains("shift-peek") == true, "the page itself stays put")
        c.closePeek()
        print("IKTEST shiftpeekchecks \(failures == 0 ? "PASS" : "FAIL") failures=\(failures)")
    }
}
#endif
