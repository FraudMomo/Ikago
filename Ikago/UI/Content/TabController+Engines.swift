import AppKit
import SwiftUI
import WebKit

/// Per-site engines (`SiteEngines`): a tab reopens a page in the engine its site uses. The page it leaves stays parked
/// (muted, detached) so Back returns to it, and a small badge shows the engine that took over.
struct EngineHandoff {
    /// The page before the last switch, and the one Back left (for Forward).
    var previous: WebTab?
    var next: WebTab?
    /// Recent switches: a redirect loop between sites on different engines must not bounce forever.
    var recent: [Date] = []
    /// What the current page itself reports.
    var pageCanGoBack = false
    var pageCanGoForward = false

    mutating func allowsAnother() -> Bool {
        recent = recent.filter { $0 > Date().addingTimeInterval(-10) }
        return recent.count < 4
    }
}

extension TabController {
    /// The engine a page at `url` should open in for this tab.
    func targetEngine(for url: String) -> BrowserEngine {
        if url.lowercased().hasPrefix("webkit-extension:"), BrowserRuntime.runs(.webkit) { return .webkit }
        guard let state = browserState else { return BrowserRuntime.engine }
        return SiteEngines.engine(for: url, preferences: state.browserPreferences, isPrivate: isPrivate)
    }

    func makePage(_ engine: BrowserEngine, extensionContext: WKWebExtensionContext?) throws -> WebTab {
        if engine == .chromium { return try CEFWebTab(profileID: profileID) }
        return extensionContext?.webViewConfiguration.map(WebKitTab.init(configuration:)) ?? WebKitTab(profileID: profileID)
    }

    // MARK: WebTabDelegate

    func webTab(_ page: WebTab, handsOff url: URL, method: String) -> Bool {
        // Popups keep their engine: window.opener (sign-in windows) only works within one engine. Form posts can't be replayed.
        // Only websites switch: about:blank, data:, blob: and files stay with the page that opened them.
        guard page === self.page, !isPopup, method == "GET" || method == "HEAD", Self.isWebsite(url.absoluteString) else { return false }
        let target = targetEngine(for: url.absoluteString)
        guard target != page.engine, handoff.allowsAnother() else { return false }
        DispatchQueue.main.async { [weak self] in self?.switchEngine(to: target, url: url.absoluteString) }
        return true
    }

    func webTab(_ page: WebTab, usesOtherEngine url: URL) -> Bool {
        Self.isWebsite(url.absoluteString) && targetEngine(for: url.absoluteString) != page.engine
    }

    static func isWebsite(_ url: String) -> Bool {
        ["http", "https"].contains(URL(string: url)?.scheme?.lowercased() ?? "")
    }

    // MARK: Switching

    /// Reopens `url` in `engine`, parking the current page for Back.
    func switchEngine(to engine: BrowserEngine, url: String) {
        guard let current = page, !isClosing, current.engine != engine else { return }
        let fresh: WebTab
        do { fresh = try makePage(engine, extensionContext: nil) } catch { return showError(error.localizedDescription) }
        handoff.recent.append(Date())
        handoff.previous?.tearDown()
        handoff.next?.tearDown()
        handoff.next = nil
        park(current)
        handoff.previous = current
        handoff.pageCanGoBack = false
        handoff.pageCanGoForward = false
        attach(fresh)
        fresh.load(url)
        showEngineBadge(engine)
    }

    /// Back: within the page, else to the page before the last engine switch.
    func goBack() {
        if handoff.pageCanGoBack || handoff.previous == nil { page?.goBack(); return }
        swapParked(back: true)
    }

    func goForward() {
        if handoff.pageCanGoForward || handoff.next == nil { page?.goForward(); return }
        swapParked(back: false)
    }

    private func swapParked(back: Bool) {
        guard let current = page, let target = back ? handoff.previous : handoff.next else { return }
        park(current)
        if back { handoff.previous = nil; handoff.next = current } else { handoff.next = nil; handoff.previous = current }
        attach(target)
        target.setMuted(tab.isMuted)
        // The parked page's own history is unknown until it reports again.
        handoff.pageCanGoBack = false
        handoff.pageCanGoForward = false
        tab.url = target.currentURL
        tab.isLoading = target.isLoading
        refreshHistoryButtons()
        if current.engine != target.engine { showEngineBadge(target.engine) }
    }

    private func park(_ page: WebTab) {
        page.delegate = nil
        page.setMuted(true)
        page.stopCapture()
        page.contentView.removeFromSuperview()
    }

    func refreshHistoryButtons() {
        tab.canGoBack = handoff.pageCanGoBack || handoff.previous != nil
        tab.canGoForward = handoff.pageCanGoForward || handoff.next != nil
    }

    /// Hibernating or closing: parked pages go too.
    func tearDownParked() {
        handoff.previous?.tearDown()
        handoff.next?.tearDown()
        handoff = EngineHandoff()
    }

    // MARK: Badge

    func showEngineBadge(_ engine: BrowserEngine) {
        engineBadge?.removeFromSuperview()
        guard let state = browserState else { return }
        let badge = PassThroughHostingView(rootView: EngineBadge(engine: engine, palette: state.palette))
        badge.sizingOptions = [.intrinsicContentSize]
        let size = badge.fittingSize
        badge.frame = NSRect(x: 12, y: hostView.bounds.height - topInset - size.height - 12, width: size.width, height: size.height)
        badge.autoresizingMask = [.minYMargin, .maxXMargin]
        badge.setAccessibilityLabel("Opened in \(engine.title)")
        hostView.addSubview(badge, positioned: .above, relativeTo: nil)
        engineBadge = badge
        let reduceMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        badge.alphaValue = reduceMotion ? 1 : 0
        if !reduceMotion { NSAnimationContext.runAnimationGroup { $0.duration = 0.15; badge.animator().alphaValue = 1 } }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.6) { [weak self, weak badge] in
            guard let badge else { return }
            let remove: @MainActor () -> Void = { [weak self] in
                badge.removeFromSuperview()
                if self?.engineBadge === badge { self?.engineBadge = nil }
            }
            if reduceMotion { return remove() }
            NSAnimationContext.runAnimationGroup({ $0.duration = 0.4; badge.animator().alphaValue = 0 },
                                                 completionHandler: { MainActor.assumeIsolated { remove() } })
        }
    }
}

/// Shows the badge without taking clicks from the page under it.
private final class PassThroughHostingView<Content: View>: NSHostingView<Content> {
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
}

/// The engine that just took over a tab: its logo and name, briefly, over the page's top-left corner.
private struct EngineBadge: View {
    let engine: BrowserEngine
    let palette: Palette

    var body: some View {
        HStack(spacing: 6) {
            EngineLogo(engine: engine, size: 14)
            Text(engine.title).font(.system(size: 11, weight: .medium)).foregroundStyle(palette.text)
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 5)
        .surface(Capsule(), palette)
        .padding(4)  // room for the surface's shadow
        .allowsHitTesting(false)
    }
}
