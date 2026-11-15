import AppKit
import SwiftUI

/// The saved logins offered under a sign-in field, on either engine.
struct PasswordSuggestions: Equatable {
    let id = UUID()
    /// The field in window coordinates (bottom-left origin), or a small rect at the pointer.
    var anchor: CGRect
    var logins: [PasswordVault.Login]
    var site: String
    var selected: Int?

    static let width: CGFloat = 300
    static let rowHeight: CGFloat = 46
    static let headerHeight: CGFloat = 30
    static let footerHeight: CGFloat = 38
    static let visibleRows = 5

    var height: CGFloat {
        Self.headerHeight + CGFloat(min(logins.count, Self.visibleRows)) * Self.rowHeight + Self.footerHeight + 14
    }

    /// Under the field, or above it when there's no room below; top-left origin, inside `size`.
    func frame(in size: CGSize) -> CGRect {
        let width = max(Self.width, min(anchor.width, 380))
        let x = min(max(8, anchor.minX), size.width - width - 8)
        let below = size.height - anchor.minY + 6
        let y = below + height <= size.height - 8 ? below : max(8, size.height - anchor.maxY - 6 - height)
        return CGRect(x: x, y: y, width: width, height: height)
    }
}

/// Shows the suggestions in a browser window and waits for a choice. The page keeps the keyboard; arrow
/// keys, Return and Escape are read by a local monitor while the list is open.
@MainActor
final class PasswordSuggestionsPresenter {
    static let shared = PasswordSuggestionsPresenter()
    private var continuation: CheckedContinuation<PasswordVault.Login?, Never>?
    private weak var chrome: ChromeModel?
    private weak var window: NSWindow?
    private var monitor: Any?
    private var observers: [NSObjectProtocol] = []

    var isShowing: Bool { chrome?.passwordSuggestions != nil }

    /// nil when the window can't show it (not a browser window), or when the person dismissed it.
    func present(_ logins: [PasswordVault.Login], site: String, anchor: CGRect, in window: NSWindow) async -> PasswordVault.Login?? {
        guard let controller = window.windowController as? BrowserWindowController else { return nil }
        // A second click in the same field keeps the open list instead of replaying it.
        if let current = chrome?.passwordSuggestions, self.window === window,
           abs(current.anchor.minX - anchor.minX) < 1, abs(current.anchor.minY - anchor.minY) < 1 { return .some(nil) }
        finish(nil)
        chrome = controller.chrome
        self.window = window
        controller.chrome.passwordSuggestions = PasswordSuggestions(anchor: anchor, logins: logins, site: site)
        install()
        return .some(await withCheckedContinuation { continuation = $0 })
    }

    func choose(_ index: Int) {
        guard let logins = chrome?.passwordSuggestions?.logins, logins.indices.contains(index) else { return }
        finish(logins[index])
    }

    func select(_ index: Int?) { chrome?.passwordSuggestions?.selected = index }

    func dismiss() { finish(nil) }

    func manage() {
        let controller = window?.windowController as? BrowserWindowController
        finish(nil)
        controller?.state.settingsCategory = .passwords
        controller?.showSettings()
    }

    private func finish(_ login: PasswordVault.Login?) {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
        observers.forEach(NotificationCenter.default.removeObserver)
        observers = []
        chrome?.passwordSuggestions = nil
        let pending = continuation
        continuation = nil
        pending?.resume(returning: login)
    }

    private func install() {
        monitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .leftMouseDown, .rightMouseDown, .scrollWheel]) { [weak self] event in
            let swallow = MainActor.assumeIsolated { self?.swallows(event) ?? false }
            return swallow ? nil : event
        }
        for name in [NSWindow.didResignKeyNotification, NSWindow.didResizeNotification] {
            observers.append(NotificationCenter.default.addObserver(forName: name, object: window, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.dismiss() }
            })
        }
    }

    /// Whether the list used the event; clicks and other keys close it and still reach the page.
    private func swallows(_ event: NSEvent) -> Bool {
        guard let suggestions = chrome?.passwordSuggestions, let window else { return false }
        if event.type != .keyDown {
            if event.window === window, let size = window.contentView?.bounds.size {
                let point = CGPoint(x: event.locationInWindow.x, y: size.height - event.locationInWindow.y)
                if suggestions.frame(in: size).contains(point) { return false }
            }
            dismiss()
            return false
        }
        let count = suggestions.logins.count
        switch event.keyCode {
        case 125: select(suggestions.selected.map { min($0 + 1, count - 1) } ?? 0); return true
        case 126: select(suggestions.selected.map { max($0 - 1, 0) } ?? count - 1); return true
        case 36, 76:
            guard let index = suggestions.selected else { dismiss(); return false }
            choose(index)
            return true
        case 53: dismiss(); return true
        default: dismiss(); return false
        }
    }
}

/// The list itself: one row per login, the site above, a way to the password settings below.
struct PasswordSuggestionsView: View {
    let suggestions: PasswordSuggestions
    let colors: Palette
    private var presenter: PasswordSuggestionsPresenter { .shared }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 6) {
                Image(systemName: "key.fill").font(.system(size: 10, weight: .semibold))
                Text(suggestions.site).font(.system(size: 11, weight: .semibold)).lineLimit(1)
                Spacer(minLength: 8)
                Image(systemName: "touchid").font(.system(size: 12)).foregroundStyle(colors.tertiary)
                    .help("Each fill asks for Touch ID or your Mac password")
            }
            .foregroundStyle(colors.secondary)
            .padding(.horizontal, 10)
            .frame(height: PasswordSuggestions.headerHeight)
            ScrollView {
                VStack(spacing: 0) {
                    ForEach(Array(suggestions.logins.enumerated()), id: \.element.id) { index, login in
                        row(login, index: index)
                    }
                }
            }
            .scrollDisabled(suggestions.logins.count <= PasswordSuggestions.visibleRows)
            .scrollIndicators(.automatic)
            Rectangle().fill(colors.separator).frame(height: 0.5).padding(.horizontal, 8).padding(.vertical, 4)
            Button { presenter.manage() } label: {
                HStack(spacing: 8) {
                    Image(systemName: "gearshape").font(.system(size: 12)).frame(width: 30)
                    Text("Manage Passwords…").font(.system(size: 12))
                    Spacer()
                }
                .foregroundStyle(colors.secondary)
                .padding(.horizontal, 8)
                .frame(height: PasswordSuggestions.footerHeight - 8)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .padding(6)
        .modalSurface(colors, radius: Radius.card)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Saved passwords for \(suggestions.site)")
    }

    private func row(_ login: PasswordVault.Login, index: Int) -> some View {
        let selected = suggestions.selected == index
        let name = login.username.isEmpty ? "No username" : login.username
        return Button { presenter.choose(index) } label: {
            HStack(spacing: 10) {
                Text(String(name.prefix(1)).uppercased())
                    .font(.system(size: 13, weight: .semibold)).foregroundStyle(.white)
                    .frame(width: 30, height: 30)
                    .background(Circle().fill(LinearGradient(colors: [colors.accent.opacity(0.85), colors.accent],
                                                             startPoint: .top, endPoint: .bottom)))
                VStack(alignment: .leading, spacing: 1) {
                    Text(name).font(.system(size: 13, weight: .medium)).foregroundStyle(colors.text).lineLimit(1)
                    // A second line only when it says more than the header: a saved title or another subdomain.
                    if let detail = login.title?.isEmpty == false ? login.title : login.site != suggestions.site ? login.site : nil {
                        Text(detail).font(.system(size: 11)).foregroundStyle(colors.secondary).lineLimit(1)
                    }
                }
                Spacer(minLength: 8)
                Image(systemName: "return").font(.system(size: 10, weight: .semibold)).foregroundStyle(colors.tertiary)
                    .opacity(selected ? 1 : 0)
            }
            .padding(.horizontal, 8)
            .frame(height: PasswordSuggestions.rowHeight)
            .background(RoundedRectangle(cornerRadius: Radius.control, style: .continuous).fill(selected ? colors.hover : .clear))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { inside in if inside { presenter.select(index) } }
        .accessibilityLabel("Fill \(name)")
    }
}
