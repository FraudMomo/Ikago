import AppKit
import SwiftUI

/// Saved addresses or cards offered under a form field, on either engine.
struct AutofillSuggestions: Equatable {
    struct Row: Equatable, Identifiable {
        let id: UUID
        let title: String
        let detail: String
    }

    let id = UUID()
    /// The field in window coordinates (bottom-left origin), or a small rect at the pointer.
    var anchor: CGRect
    var card: Bool
    var rows: [Row]
    var selected: Int? = 0

    static let width: CGFloat = 300
    static let rowHeight: CGFloat = 46
    static let headerHeight: CGFloat = 30
    static let footerHeight: CGFloat = 38
    static let visibleRows = 4

    var height: CGFloat { Self.headerHeight + CGFloat(min(rows.count, Self.visibleRows)) * Self.rowHeight + Self.footerHeight + 14 }

    /// Under the field, or above it when there's no room below; top-left origin, inside `size`.
    func frame(in size: CGSize) -> CGRect {
        let width = max(Self.width, min(anchor.width, 380))
        let x = min(max(8, anchor.minX), size.width - width - 8)
        let below = size.height - anchor.minY + 6
        let y = below + height <= size.height - 8 ? below : max(8, size.height - anchor.maxY - 6 - height)
        return CGRect(x: x, y: y, width: width, height: height)
    }
}

/// Shows the suggestions in a browser window and waits for a choice. The page keeps the keyboard; arrows, Return and
/// Escape are read by a local monitor while the list is open, and a click elsewhere closes it.
@MainActor
final class AutofillSuggestionsPresenter {
    static let shared = AutofillSuggestionsPresenter()
    private var continuation: CheckedContinuation<UUID?, Never>?
    private weak var chrome: ChromeModel?
    private weak var window: NSWindow?
    private var monitor: Any?
    private var observers: [NSObjectProtocol] = []

    /// The chosen row's id, or nil when dismissed or when the window isn't a browser window.
    func present(_ rows: [AutofillSuggestions.Row], card: Bool, anchor: CGRect, in window: NSWindow) async -> UUID? {
        guard !rows.isEmpty, let controller = window.windowController as? BrowserWindowController else { return nil }
        if let current = chrome?.autofillSuggestions, self.window === window, current.card == card,
           abs(current.anchor.minX - anchor.minX) < 1, abs(current.anchor.minY - anchor.minY) < 1 { return nil }
        finish(nil)
        chrome = controller.chrome
        self.window = window
        controller.chrome.autofillSuggestions = AutofillSuggestions(anchor: anchor, card: card, rows: rows)
        install()
        return await withCheckedContinuation { continuation = $0 }
    }

    func choose(_ index: Int) {
        guard let rows = chrome?.autofillSuggestions?.rows, rows.indices.contains(index) else { return }
        finish(rows[index].id)
    }

    func select(_ index: Int?) { chrome?.autofillSuggestions?.selected = index }
    func dismiss() { finish(nil) }

    func manage() {
        let controller = window?.windowController as? BrowserWindowController
        finish(nil)
        controller?.state.settingsCategory = .autofill
        controller?.showSettings()
    }

    private func finish(_ id: UUID?) {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
        observers.forEach(NotificationCenter.default.removeObserver)
        observers = []
        chrome?.autofillSuggestions = nil
        let pending = continuation
        continuation = nil
        pending?.resume(returning: id)
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

    private func swallows(_ event: NSEvent) -> Bool {
        guard let suggestions = chrome?.autofillSuggestions, let window else { return false }
        if event.type != .keyDown {
            if event.window === window, let size = window.contentView?.bounds.size {
                let point = CGPoint(x: event.locationInWindow.x, y: size.height - event.locationInWindow.y)
                if suggestions.frame(in: size).contains(point) { return false }
            }
            dismiss()
            return false
        }
        let count = suggestions.rows.count
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

/// The list: a row per address or card, what it is above, a way to the settings below.
struct AutofillSuggestionsView: View {
    let suggestions: AutofillSuggestions
    let colors: Palette
    private var presenter: AutofillSuggestionsPresenter { .shared }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 6) {
                Image(systemName: suggestions.card ? "creditcard.fill" : "person.crop.circle.fill").font(.system(size: 10, weight: .semibold))
                Text(suggestions.card ? "Cards" : "Addresses").font(.system(size: 11, weight: .semibold))
                Spacer(minLength: 8)
                if suggestions.card {
                    Image(systemName: "touchid").font(.system(size: 12)).foregroundStyle(colors.tertiary)
                        .help("Each card fill asks for Touch ID or your Mac password")
                }
            }
            .foregroundStyle(colors.secondary)
            .padding(.horizontal, 10)
            .frame(height: AutofillSuggestions.headerHeight)
            ScrollView {
                VStack(spacing: 0) {
                    ForEach(Array(suggestions.rows.enumerated()), id: \.element.id) { index, row in self.row(row, index: index) }
                }
            }
            .scrollDisabled(suggestions.rows.count <= AutofillSuggestions.visibleRows)
            Rectangle().fill(colors.separator).frame(height: 0.5).padding(.horizontal, 8).padding(.vertical, 4)
            Button { presenter.manage() } label: {
                HStack(spacing: 8) {
                    Image(systemName: "gearshape").font(.system(size: 12)).frame(width: 30)
                    Text(suggestions.card ? "Manage Cards…" : "Manage Addresses…").font(.system(size: 12))
                    Spacer()
                }
                .foregroundStyle(colors.secondary)
                .padding(.horizontal, 8)
                .frame(height: AutofillSuggestions.footerHeight - 8)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .padding(6)
        .modalSurface(colors, radius: Radius.card)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(suggestions.card ? "Saved cards" : "Saved addresses")
    }

    private func row(_ row: AutofillSuggestions.Row, index: Int) -> some View {
        let selected = suggestions.selected == index
        return Button { presenter.choose(index) } label: {
            HStack(spacing: 10) {
                Image(systemName: suggestions.card ? "creditcard" : "house").font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.white)
                    .frame(width: 30, height: 30)
                    .background(Circle().fill(LinearGradient(colors: [(suggestions.card ? Color.indigo : Color.teal).opacity(0.85),
                                                                       suggestions.card ? Color.indigo : Color.teal],
                                                             startPoint: .top, endPoint: .bottom)))
                VStack(alignment: .leading, spacing: 1) {
                    Text(row.title).font(.system(size: 13, weight: .medium)).foregroundStyle(colors.text).lineLimit(1)
                    if !row.detail.isEmpty {
                        Text(row.detail).font(.system(size: 11)).foregroundStyle(colors.secondary).lineLimit(1)
                    }
                }
                Spacer(minLength: 8)
                Image(systemName: "return").font(.system(size: 10, weight: .semibold)).foregroundStyle(colors.tertiary)
                    .opacity(selected ? 1 : 0)
            }
            .padding(.horizontal, 8)
            .frame(height: AutofillSuggestions.rowHeight)
            .background(RoundedRectangle(cornerRadius: Radius.control, style: .continuous).fill(selected ? colors.hover : .clear))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { inside in if inside { presenter.select(index) } }
        .accessibilityLabel("Fill \(row.title)")
    }
}
