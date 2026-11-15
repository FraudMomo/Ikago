import AppKit
import Observation

/// Handoff, both ways, through Apple's public `NSUserActivity` (Settings ▸ General ▸ Other Devices, off until turned on).
/// Out: the page in the key browser window is offered to nearby devices on the same Apple Account, where Safari opens it.
/// In: a page continued from another device opens here in a new tab (macOS hands web pages to the default browser).
/// Private windows, Ikago's own pages and anything but http(s) are never offered.
@MainActor
final class HandoffAdvertiser {
    static let shared = HandoffAdvertiser()
    private var activity: NSUserActivity?
    private weak var state: BrowserState?
    private var observer: NSObjectProtocol?

    static var isEnabled: Bool { BrowserSecurity.shared.preferences.handoff == true }

    func start() {
        guard observer == nil else { return }
        observer = NotificationCenter.default.addObserver(forName: NSWindow.didBecomeKeyNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let controller = NSApp.keyWindow?.windowController as? BrowserWindowController else { return }
                self?.track(controller.state)
            }
        }
        if let front = BrowserWindows.frontmost { track(front.state) }
    }

    private func track(_ state: BrowserState) {
        self.state = state
        update()
    }

    /// Re-reads the key window's page whenever it, its title or the setting changes.
    private func update() {
        guard let state else { return stop() }
        let page = withObservationTracking {
            (url: state.activeTab?.url, title: state.activeTab?.title, enabled: state.browserPreferences.handoff == true)
        } onChange: { [weak self] in
            DispatchQueue.main.async { MainActor.assumeIsolated { self?.update() } }
        }
        guard page.enabled, !state.isPrivate, let raw = page.url, let url = URL(string: raw),
              ["http", "https"].contains(url.scheme?.lowercased() ?? "") else { return stop() }
        if activity?.webpageURL == url {
            activity?.title = page.title
            return
        }
        stop()
        let activity = NSUserActivity(activityType: NSUserActivityTypeBrowsingWeb)
        activity.webpageURL = url
        activity.title = page.title
        activity.isEligibleForHandoff = true
        activity.isEligibleForSearch = false
        activity.isEligibleForPublicIndexing = false
        activity.becomeCurrent()
        self.activity = activity
    }

    private func stop() {
        activity?.invalidate()
        activity = nil
    }

    /// The http(s) page a continued activity carries, if any.
    static func webURL(of activity: NSUserActivity) -> String? {
        guard activity.activityType == NSUserActivityTypeBrowsingWeb, let url = activity.webpageURL,
              ["http", "https"].contains(url.scheme?.lowercased() ?? "") else { return nil }
        return url.absoluteString
    }
}
