import AppKit
import SwiftUI

/// The saved logins offered under a sign-in field, on either engine.
///
/// Logins with the same username on several sites of one domain (`accounts.example.com`, `example.com`) show as one row,
/// the best match for this page first (`PasswordVault.matches` ranks them); its chevron shows the others, so none is ever
/// out of reach. What the field already holds narrows the list to the usernames that contain it, and the search field
/// (with more than a few logins) searches usernames, sites and titles.
struct PasswordSuggestions: Equatable {
    let id = UUID()
    /// The field in window coordinates (bottom-left origin), or a small rect at the pointer.
    var anchor: CGRect
    var logins: [PasswordVault.Login]
    var site: String
    /// A strong password offered above the logins (a new-password field); it is row 0 when present.
    var generated: String?
    var selected: Int?
    /// What the sign-in field holds (its username), and what the person typed into the search field.
    var typed = ""
    var query = ""
    /// Usernames whose other sites are shown.
    var expanded: Set<String> = []

    enum Row: Equatable, Identifiable {
        case generated(String)
        /// The best login for a username, and how many more sites share that username.
        case login(PasswordVault.Login, others: Int)
        /// Another site's login for an expanded username.
        case member(PasswordVault.Login)

        var id: String {
            switch self {
            case .generated: "generated"
            case .login(let login, _): "login-" + login.id.uuidString
            case .member(let login): "member-" + login.id.uuidString
            }
        }

        var login: PasswordVault.Login? {
            switch self {
            case .generated: nil
            case .login(let login, _), .member(let login): login
            }
        }
    }

    static func key(_ username: String) -> String { username.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }

    /// Logins grouped by username, in the vault's ranked order.
    private var groups: [[PasswordVault.Login]] {
        var order: [String] = [], byKey: [String: [PasswordVault.Login]] = [:]
        for login in logins {
            let key = Self.key(login.username)
            if byKey[key] == nil { order.append(key) }
            byKey[key, default: []].append(login)
        }
        return order.compactMap { byKey[$0] }
    }

    private func matches(_ login: PasswordVault.Login, _ text: String, sites: Bool) -> Bool {
        let text = Self.key(text)
        guard !text.isEmpty else { return true }
        if login.username.lowercased().contains(text) { return true }
        return sites && (login.site.contains(text) || login.title?.lowercased().contains(text) == true)
    }

    /// The groups the field's text and the search keep. The field's text narrows the list only when some username
    /// contains it (a page may prefill an address the person never saved here).
    private var shownGroups: [[PasswordVault.Login]] {
        var kept = groups
        if !query.isEmpty { kept = kept.filter { $0.contains { matches($0, query, sites: true) } } }
        let typedMatches = kept.filter { $0.contains { matches($0, typed, sites: false) } }
        if !typedMatches.isEmpty { kept = typedMatches }
        return kept
    }

    /// Whether the field's text matches none of the saved usernames.
    var typedMatchesNothing: Bool { !Self.key(typed).isEmpty && !logins.contains { matches($0, typed, sites: false) } }

    var rowList: [Row] {
        var rows: [Row] = generated.map { [.generated($0)] } ?? []
        for group in shownGroups {
            guard let first = group.first else { continue }
            rows.append(.login(first, others: group.count - 1))
            if expanded.contains(Self.key(first.username)) { rows += group.dropFirst().map { .member($0) } }
        }
        return rows
    }

    var rows: Int { rowList.count }
    /// A search field once there are more usernames than fit at a glance.
    var searches: Bool { groups.count > 3 }

    static let width: CGFloat = 300
    static let rowHeight: CGFloat = 44
    static let memberHeight: CGFloat = 34
    static let headerHeight: CGFloat = 32
    static let searchHeight: CGFloat = 34
    static let footerHeight: CGFloat = 36
    static let visibleRows = 5

    var height: CGFloat {
        let list = rowList.prefix(Self.visibleRows).reduce(CGFloat(0)) { total, row in
            if case .member = row { return total + Self.memberHeight }
            return total + Self.rowHeight
        }
        let empty: CGFloat = rowList.isEmpty ? Self.rowHeight : 0
        return Self.headerHeight + (searches ? Self.searchHeight : 0) + list + empty + Self.footerHeight + 14
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

/// What the person picked from the suggestions.
enum PasswordPick: Equatable {
    case login(PasswordVault.Login)
    case generated
}

/// Shows the suggestions in a browser window and waits for a choice. The page keeps the keyboard: arrow keys, Return and
/// Escape are read by a local monitor while the list is open, and typing in the field narrows the list (`typed`, read
/// back from the page). A click on the key or field that closed the list doesn't open it again.
@MainActor
final class PasswordSuggestionsPresenter {
    static let shared = PasswordSuggestionsPresenter()
    private var continuation: CheckedContinuation<PasswordPick?, Never>?
    private weak var chrome: ChromeModel?
    private weak var window: NSWindow?
    private weak var pageResponder: NSResponder?
    private var monitor: Any?
    private var observers: [NSObjectProtocol] = []
    /// Reads what the sign-in field's username holds now, after the person types; nil when they type in a password field.
    private var readTyped: (@MainActor () async -> String?)?
    private var refresh: Task<Void, Never>?
    /// The list a click outside closed, so the same click on the key or field toggles it shut instead of reopening it.
    private var closedByClick: (window: ObjectIdentifier, anchor: CGRect, at: Date)?

    var isShowing: Bool { chrome?.passwordSuggestions != nil }

    /// nil when the window can't show it (not a browser window), or when the person dismissed it. `typed` is what the
    /// field holds now; `readTyped` reads it again as they type.
    func present(_ logins: [PasswordVault.Login], site: String, anchor: CGRect, in window: NSWindow, generated: String? = nil,
                 typed: String = "", readTyped: (@MainActor () async -> String?)? = nil) async -> PasswordPick?? {
        guard let controller = window.windowController as? BrowserWindowController else { return nil }
        // A second click in the same field keeps the open list instead of replaying it.
        if let current = chrome?.passwordSuggestions, self.window === window, Self.same(current.anchor, anchor) { return .some(nil) }
        // The click that just closed it (on the key or in the field) toggles it shut.
        if let closed = closedByClick, closed.window == ObjectIdentifier(window), Self.same(closed.anchor, anchor),
           Date().timeIntervalSince(closed.at) < 0.8 {
            closedByClick = nil
            return .some(nil)
        }
        finish(nil)
        chrome = controller.chrome
        self.window = window
        pageResponder = window.firstResponder
        self.readTyped = readTyped
        var suggestions = PasswordSuggestions(anchor: anchor, logins: logins, site: site, generated: generated, typed: typed)
        if !suggestions.rowList.isEmpty { suggestions.selected = 0 }
        controller.chrome.passwordSuggestions = suggestions
        install()
        return .some(await withCheckedContinuation { continuation = $0 })
    }

    private static func same(_ a: CGRect, _ b: CGRect) -> Bool { abs(a.minX - b.minX) < 1 && abs(a.minY - b.minY) < 1 }

    func choose(_ index: Int) {
        guard let suggestions = chrome?.passwordSuggestions else { return }
        let rows = suggestions.rowList
        guard rows.indices.contains(index) else { return }
        switch rows[index] {
        case .generated: finish(.generated)
        case .login(let login, _), .member(let login): finish(.login(login))
        }
    }

    func select(_ index: Int?) { chrome?.passwordSuggestions?.selected = index }

    /// Shows or hides the other sites that share a row's username.
    func toggle(_ username: String) {
        guard var suggestions = chrome?.passwordSuggestions else { return }
        let key = PasswordSuggestions.key(username)
        if suggestions.expanded.contains(key) { suggestions.expanded.remove(key) } else { suggestions.expanded.insert(key) }
        let selectedID = suggestions.selected.flatMap { suggestions.rowList.indices.contains($0) ? suggestions.rowList[$0].id : nil }
        suggestions.selected = suggestions.rowList.firstIndex { $0.id == selectedID }
        chrome?.passwordSuggestions = suggestions
    }

    func search(_ text: String) {
        guard var suggestions = chrome?.passwordSuggestions else { return }
        suggestions.query = text
        suggestions.selected = suggestions.rowList.isEmpty ? nil : 0
        chrome?.passwordSuggestions = suggestions
    }

    func dismiss() { finish(nil) }

    func manage() {
        let controller = window?.windowController as? BrowserWindowController
        finish(nil)
        controller?.state.settingsCategory = .passwords
        controller?.showSettings()
    }

    private func finish(_ login: PasswordPick?) {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
        refresh?.cancel()
        refresh = nil
        readTyped = nil
        observers.forEach(NotificationCenter.default.removeObserver)
        observers = []
        // The search field had the keyboard: give it back to the page, so a fill lands in the focused field.
        if let window, chrome?.passwordSuggestions != nil, isSearching(in: window), let pageResponder { window.makeFirstResponder(pageResponder) }
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

    /// Whether the search field (in the list, not the page) has the keyboard.
    private func isSearching(in window: NSWindow) -> Bool {
        guard let editor = window.firstResponder as? NSText, let page = pageResponder as? NSView else { return false }
        return !(editor === page || editor.isDescendant(of: page))
    }

    /// Whether the list used the event; clicks outside close it and still reach the page.
    private func swallows(_ event: NSEvent) -> Bool {
        guard let suggestions = chrome?.passwordSuggestions, let window else { return false }
        if event.type != .keyDown {
            if event.window === window, let size = window.contentView?.bounds.size {
                let point = CGPoint(x: event.locationInWindow.x, y: size.height - event.locationInWindow.y)
                if suggestions.frame(in: size).contains(point) { return false }
            }
            if event.type == .leftMouseDown { closedByClick = (ObjectIdentifier(window), suggestions.anchor, Date()) }
            dismiss()
            return false
        }
        let count = suggestions.rows
        let rows = suggestions.rowList
        switch event.keyCode {
        case 125: select(count == 0 ? nil : suggestions.selected.map { min($0 + 1, count - 1) } ?? 0); return true
        case 126: select(count == 0 ? nil : suggestions.selected.map { max($0 - 1, 0) } ?? count - 1); return true
        case 124, 123:  // → shows a username's other sites, ← hides them
            guard let index = suggestions.selected, rows.indices.contains(index), case .login(let login, let others) = rows[index], others > 0
            else { return false }
            let open = suggestions.expanded.contains(PasswordSuggestions.key(login.username))
            if (event.keyCode == 124) != open { toggle(login.username) }
            return true
        case 36, 76:
            guard let index = suggestions.selected, rows.indices.contains(index) else { dismiss(); return false }
            choose(index)
            return true
        case 53: dismiss(); return true
        case 48: dismiss(); return false  // Tab moves on
        default:
            // Typing: in the search field it searches; in the page's field it narrows the list to what the field holds.
            if isSearching(in: window) { return false }
            if !event.modifierFlags.intersection([.command, .control]).isEmpty, event.charactersIgnoringModifiers != "v" {
                dismiss()
                return false
            }
            guard let readTyped else { dismiss(); return false }
            refresh?.cancel()
            refresh = Task { @MainActor [weak self] in
                try? await Task.sleep(for: .milliseconds(40))
                guard !Task.isCancelled else { return }
                let typed = await readTyped()
                guard !Task.isCancelled else { return }
                // nil: the person is typing a password by hand, or left the field.
                guard let typed else { self?.dismiss(); return }
                self?.update(typed: typed)
            }
            return false
        }
    }

    private func update(typed: String) {
        guard var suggestions = chrome?.passwordSuggestions else { return }
        suggestions.typed = typed
        // Nothing saved starts with what the person is typing (a new account): the list gets out of the way.
        if suggestions.typedMatchesNothing && suggestions.generated == nil { return dismiss() }
        suggestions.selected = suggestions.rowList.isEmpty ? nil : 0
        chrome?.passwordSuggestions = suggestions
    }
}
