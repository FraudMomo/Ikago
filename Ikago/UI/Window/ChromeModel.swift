import AppKit
import Observation

/// Transient window-chrome state the SwiftUI shell animates: overlays, sidebar peek,
/// and an in-progress tab drag. Not persisted.
@MainActor
@Observable
final class ChromeModel {
    var bookmarkToEdit: Bookmark?
    var showPalette = false
    var showFind = false
    var showDownloads = false
    var showTabOverview = false
    /// Top Bar layout: the active tab is the address field.
    var inlineAddress = false
    /// The tab whose address is being edited; switching to another tab ends editing.
    var editingTabID: String?
    /// Collapsed sidebar slid in from the left edge.
    var peeking = false
    /// A sidebar tab is being dragged (drag-to-split targets appear only then).
    var draggingTabID: String?
    /// The Downloads button's frame in the shell's coordinates when it sits in a separately hosted part of the window
    /// (the sidebar, `IsolatedHost`), where the shell can't read its anchor.
    var downloadsButtonFrame: CGRect?
    /// The top bar's address field, in the shell's coordinates, for the suggestions popup (see `downloadsButtonFrame`).
    var addressFieldFrame: CGRect?
    @ObservationIgnored private var peekHide: Task<Void, Never>?
    @ObservationIgnored private var dragWatch: Task<Void, Never>?

    /// Whether `tabID`'s address is being edited in place. Checked per tab, so a tab switched
    /// to mid-edit never shows the field (with the old tab's text) for even a frame.
    func isEditingAddress(of tabID: String?) -> Bool { inlineAddress && editingTabID == tabID }

    /// The pointer is over the revealed sidebar or top bar.
    @ObservationIgnored var peekHovered = false
    /// Something in the revealed chrome is in use (typing an address, the downloads list, a tab drag): it stays.
    var holdsPeek: Bool { inlineAddress || showDownloads || draggingTabID != nil }

    func peek() {
        peekHide?.cancel()
        peeking = true
    }

    /// Hide the peeked sidebar or top bar shortly after the pointer leaves it, unless it is in use.
    func endPeek(after delay: Duration = .milliseconds(350)) {
        peekHide?.cancel()
        peekHide = Task { [weak self] in
            try? await Task.sleep(for: delay)
            guard !Task.isCancelled, let self, !self.peekHovered, !self.holdsPeek else { return }
            self.peeking = false
        }
    }

    /// Starts a tab drag. SwiftUI reports no drag end, so watch the mouse button instead.
    func beginTabDrag(_ id: String) {
        draggingTabID = id
        dragWatch?.cancel()
        dragWatch = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(200))
                if NSEvent.pressedMouseButtons & 1 == 0 {
                    // Keep drop targets alive until AppKit has delivered the mouse-up drop.
                    try? await Task.sleep(for: .milliseconds(250))
                    if !Task.isCancelled { self?.draggingTabID = nil }
                    return
                }
            }
        }
    }

    func endTabDrag() {
        dragWatch?.cancel()
        draggingTabID = nil
    }
}
