import AppKit
import Observation

/// Transient window-chrome state the SwiftUI shell animates: overlays, sidebar peek,
/// and an in-progress tab drag. Not persisted.
@MainActor
@Observable
final class ChromeModel {
    var textPrompt: IntegratedTextPrompt?
    var editFolderID: String?
    var showNewSpace = false
    var spaceSubmitRequest = 0
    var showNotes = false
    /// Clear Browsing Data (`ClearDataSheet`), over the window.
    var showClearData = false
    /// The site card (`SiteInfoOverlay`) and where its button was clicked, in the shell's coordinates.
    var showSiteInfo = false
    var siteInfoAnchor = CGPoint(x: 300, y: 40)
    /// Tabs picked together with Shift- or ⌘-click (`TabClick`); empty when one tab is simply open.
    var selectedTabIDs: Set<String> = []
    /// Where the next Shift-click range starts: the tab last clicked.
    @ObservationIgnored var selectionAnchor: String?
    var bookmarkToEdit: Bookmark?
    var hoverCandidateID: String?
    var hoverImage: NSImage?
    var hoverTabID: String?
    var hoverTabAnchor = CGRect.zero
    var previewTabID: String?
    /// Peek growing into its tab: the card moves to `peekTarget` (the page's place, shell coordinates) before the
    /// same live page becomes the tab.
    var peekExpanding = false
    var peekTarget = CGRect.zero
    var showPageAssistant = false
    /// Saved logins under the focused sign-in field (`PasswordSuggestionsPresenter`).
    var passwordSuggestions: PasswordSuggestions?
    /// "Save password?" after a sign-in (`PasswordSavePresenter`).
    var passwordSave: PasswordSaveOffer?
    /// The page translation in progress or just done (`TranslationCard`, run by `TranslationHost`).
    var translationJob: TranslationJob?
    /// Extensions asking to read the page's website, on the first visit (`ExtensionAccessCard`).
    var extensionAccessOffer: ExtensionAccessOffer?
    var showPalette = false
    var showFind = false
    var showDownloads = false
    /// Tabs from the person's other devices (`DevicesDropdown`).
    var showDevices = false
    /// Native popovers (an extension's popup) open over this window; counted by `BrowserWindowController`.
    var nativePopovers = 0

    /// Something floats over the sidebar and the tab row: tabs underneath draw no hover and show no card.
    var coversTabs: Bool {
        showSiteInfo || showDevices || showDownloads || showClearData || showNewSpace || showNotes || showPalette
            || textPrompt != nil || editFolderID != nil || passwordSuggestions != nil || previewTabID != nil || nativePopovers > 0
    }
    /// A live two-finger swipe between Spaces in the sidebar (`SidebarSpaceSwipe`).
    let spaceSwipe = SpaceSwipe()

    /// The sidebar's address field is being edited in place (Integrated style).
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
    /// Top Tabs: the address field's frame in the shell's coordinates, for the suggestions under it.
    var addressFieldFrame: CGRect?
    @ObservationIgnored private var peekHide: Task<Void, Never>?
    /// Watches the pointer while a tab's hover card is up (`BrowserWindowController.showTabHover`).
    @ObservationIgnored var hoverWatch: Task<Void, Never>?
    @ObservationIgnored private var dragWatch: Task<Void, Never>?
    /// A tab drag ended with no drop in this window: the tab and where the pointer let go, on screen. The window tears
    /// the tab off into a new window when that is outside every Ikago window (`BrowserWindows.tearOff`).
    @ObservationIgnored var onTabDragEnded: ((String, NSPoint) -> Void)?

    /// Whether `tabID`'s address is being edited in place. Checked per tab, so a tab switched
    /// to mid-edit never shows the field (with the old tab's text) for even a frame.
    func isEditingAddress(of tabID: String?) -> Bool { inlineAddress && editingTabID == tabID }

    /// The pointer is over the revealed sidebar.
    @ObservationIgnored var peekHovered = false
    /// Something in the revealed chrome is in use (typing an address, the downloads list, a tab drag): it stays.
    var holdsPeek: Bool { inlineAddress || showDownloads || draggingTabID != nil || draggingFolderID != nil }

    func peek() {
        peekHide?.cancel()
        peeking = true
    }

    /// Hide the peeked sidebar shortly after the pointer leaves it, unless it is in use.
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
        // Dragging one selected tab carries the others.
        TabDrag.companions = selectedTabIDs.count > 1 && selectedTabIDs.contains(id) ? Array(selectedTabIDs.subtracting([id])) : []
        dragWatch?.cancel()
        dragWatch = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(60))
                if NSEvent.pressedMouseButtons & 1 == 0 {
                    let released = NSEvent.mouseLocation
                    // Keep drop targets alive until AppKit has delivered the mouse-up drop (a drop here cancels this).
                    try? await Task.sleep(for: .milliseconds(250))
                    guard !Task.isCancelled, let self else { return }
                    self.draggingTabID = nil
                    self.onTabDragEnded?(id, released)
                    return
                }
            }
        }
    }

    func endTabDrag() {
        dragWatch?.cancel()
        draggingTabID = nil
    }

    /// A group being dragged by its header (`GroupDrag`): its header dims and drop targets for groups show.
    var draggingFolderID: String?

    /// Starts a group drag; like tab drags, the mouse button tells when it ended without a drop.
    func beginFolderDrag(_ id: String) {
        draggingFolderID = id
        dragWatch?.cancel()
        dragWatch = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(60))
                if NSEvent.pressedMouseButtons & 1 == 0 {
                    try? await Task.sleep(for: .milliseconds(250))
                    guard !Task.isCancelled else { return }
                    self?.draggingFolderID = nil
                    return
                }
            }
        }
    }

    func endFolderDrag() {
        dragWatch?.cancel()
        draggingFolderID = nil
    }
}
