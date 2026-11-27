import AppKit
import SwiftUI

// The sidebar list's pieces (`SidebarOutlineList`): its scroll view, the outline view and its row backgrounds, the cell
// that hosts a row's SwiftUI view, and the rows themselves.

/// The list's scroll view: the sidebar's slim overlay scroller (`SlimScroller`) at all times. AppKit resets the style to a
/// classic scroll bar, with its track down the list's edge, when a mouse is connected; this one stays overlay.
final class OutlineScrollView: NSScrollView {
    override var scrollerStyle: NSScroller.Style {
        get { .overlay }
        set { super.scrollerStyle = .overlay }
    }
}

/// The outline itself: rows never take the keyboard's focus ring, and a drag starts from a row's body.
final class SidebarOutlineTable: NSOutlineView {
    /// A press that ended as a click (not a drag) on this row.
    var onClick: ((Int) -> Void)?
    var dragStarted = false
    /// A drag moved over the list: where it lands now (`SidebarOutlineController.updateDrop`).
    var onDragMoved: ((any NSDraggingInfo) -> NSDragOperation)?
    override var acceptsFirstResponder: Bool { false }
    /// A click in a window that isn't in front selects the tab at once, as the sidebar's rows always did.
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    /// The outline tracks the press itself (a drag starts once it moves); a press it returns from without a drag, released
    /// over the same row, is a click.
    override func mouseDown(with event: NSEvent) {
        dragStarted = false
        let row = self.row(at: convert(event.locationInWindow, from: nil))
        super.mouseDown(with: event)
        guard !dragStarted, row >= 0, let up = NSApp.currentEvent, up.type == .leftMouseUp,
              self.row(at: convert(up.locationInWindow, from: nil)) == row else { return }
        onClick?(row)
    }

    /// A drop AppKit refused although the list allows it: AppKit's own check reads its last `validateDrop`, which it
    /// skips when only the pointer moved. Whether the list takes it.
    var onDrop: ((any NSDraggingInfo) -> Bool)?
    /// AppKit is done with a drop: after the drop concludes for a drag from elsewhere, after the drag session ends for a
    /// drag from this list (AppKit's own end of that session still reads the rows as they were).
    var onDragFinished: (() -> Void)?

    override func concludeDragOperation(_ sender: (any NSDraggingInfo)?) {
        super.concludeDragOperation(sender)
        if (sender?.draggingSource as? NSView) !== self { onDragFinished?() }
    }

    override func draggingSession(_ session: NSDraggingSession, endedAt screenPoint: NSPoint, operation: NSDragOperation) {
        super.draggingSession(session, endedAt: screenPoint, operation: operation)
        onDragFinished?()
    }

    /// AppKit's own drop first: it clears its drop state (left behind, the next row move raised inside AppKit) and asks
    /// the list (`acceptDrop`) when its last check allowed the drop.
    override func performDragOperation(_ sender: any NSDraggingInfo) -> Bool {
        super.performDragOperation(sender) || onDrop?(sender) == true
    }

    /// AppKit asks where a drop goes only when its own guess changes; the list's place follows the pointer, so it is
    /// asked as a drag enters and on every move.
    override func draggingEntered(_ sender: any NSDraggingInfo) -> NSDragOperation {
        let operation = super.draggingEntered(sender)
        return onDragMoved?(sender) ?? operation
    }

    override func draggingUpdated(_ sender: any NSDraggingInfo) -> NSDragOperation {
        let operation = super.draggingUpdated(sender)
        return onDragMoved?(sender) ?? operation
    }

    override func frameOfOutlineCell(atRow row: Int) -> NSRect { .zero }  // no disclosure triangles: headers have chevrons
    override func validateProposedFirstResponder(_ responder: NSResponder, for event: NSEvent?) -> Bool { true }
}

/// A row's background: a piece of its group's card in Cards style.
final class OutlineRowView: NSTableRowView {
    enum CardPiece { case top, middle, bottom, whole }
    var card: (piece: CardPiece, fill: NSColor)? { didSet { needsDisplay = true } }
    /// The icon sidebar's tile column (start, width): the card sits behind it only.
    var cardColumn: (start: CGFloat, width: CGFloat)? { didSet { needsDisplay = true } }
    private var area: NSRect {
        guard let cardColumn else { return bounds }
        return NSRect(x: cardColumn.start, y: bounds.minY, width: cardColumn.width, height: bounds.height)
    }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func drawBackground(in dirtyRect: NSRect) {
        guard let card else { return }
        // Rows sit apart: the middle pieces reach across the gaps so the card is one surface.
        let gap: CGFloat = cardColumn == nil ? 1 : 2
        var rect = area.insetBy(dx: 0, dy: -gap)
        let radius = Radius.card
        switch card.piece {
        case .top: rect.size.height += radius; if !isFlipped { rect.origin.y -= radius }
        case .bottom: rect.size.height += radius; if isFlipped { rect.origin.y -= radius }
        case .middle: break
        case .whole: rect = area
        }
        card.fill.setFill()
        let clip = NSBezierPath(rect: area.insetBy(dx: 0, dy: -gap))
        clip.addClip()
        if card.piece == .middle { NSBezierPath(rect: rect).fill() } else {
            NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius).fill()
        }
    }

    override func drawSelection(in dirtyRect: NSRect) {}
}

/// A reusable cell hosting a row's SwiftUI view. It lets the outline have clicks and drags on the row's body, and the
/// row its own controls at the trailing end, right clicks (its menu) and middle clicks.
final class OutlineHostingCell: NSTableCellView {
    private let host = NSHostingView(rootView: AnyView(EmptyView()))
    var kind: SidebarOutline.Row.Kind = .divider
    /// Icon sidebar tiles: the tile's body is the outline's (select, drag); its sound badge at the corner is its own.
    var railInset: CGFloat?
    var root: AnyView = AnyView(EmptyView()) { didSet { host.rootView = root } }
    /// How far the row sits in from the cell's edges for its place in the list (a group's card, a folder's indent).
    var insets: (leading: CGFloat, trailing: CGFloat) = (0, 0) { didSet { if insets != oldValue { needsLayout = true } } }

    init(identifier: NSUserInterfaceItemIdentifier) {
        super.init(frame: .zero)
        self.identifier = identifier
        host.sizingOptions = []
        host.safeAreaRegions = []
        host.translatesAutoresizingMaskIntoConstraints = true
        host.autoresizingMask = [.width, .height]
        addSubview(host)
    }

    @available(*, unavailable) required init?(coder: NSCoder) { fatalError() }

    override func layout() {
        super.layout()
        host.frame = NSRect(x: insets.leading, y: 0, width: max(0, bounds.width - insets.leading - insets.trailing), height: bounds.height)
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        guard let hit = super.hitTest(point) else { return nil }
        let event = NSApp.currentEvent?.type
        // Right and middle clicks always go to the row (menus, close); split rows handle their own chips.
        if event == .rightMouseDown || event == .otherMouseDown || event == .otherMouseUp { return hit }
        if let railInset {
            let local = convert(point, from: superview)
            let corner = isFlipped ? local.y > bounds.height - 16 : local.y < 16
            if case .tabs = kind, corner, local.x > railInset + 22 { return hit }
            if case .divider = kind { return hit }
            return nil
        }
        if case .tabs(let ids) = kind, ids.count > 1 { return hit }
        // The row's own controls live at its trailing end (close, mute, camera, the group's count).
        let local = convert(point, from: superview)
        if case .tabs = kind, local.x > bounds.width - insets.trailing - 60 { return hit }
        return nil
    }
}

/// A tab row as the sidebar draws it.
struct OutlineTabRow: View {
    let id: String
    let state: BrowserState
    let chrome: ChromeModel
    let colors: Palette
    weak var commands: BrowserCommands?
    @Namespace private var selection

    var body: some View {
        if let tab = state.tab(id) {
            TabRowView(tab: tab, isActive: tab.id == state.activeTabID, isInSplit: false, colors: colors, selection: selection, commands: commands)
                .tabSelectionTint(chrome.selectedTabIDs.contains(tab.id), colors: colors)
                .contextMenu { TabContextMenu(tab: tab, state: state, commands: commands) }
                .onMiddleClick { withAnimation(.ikago) { commands?.closeTab(tab.id) } }
                .travellingWithDrag(tab.id, chrome: chrome)
                .recordLayout("sidebar-tab-\(tab.id)")
        }
    }
}

struct OutlineSplitRow: View {
    let ids: [String]
    let state: BrowserState
    let chrome: ChromeModel
    let colors: Palette
    weak var commands: BrowserCommands?
    @Namespace private var selection

    var body: some View {
        let tabs = ids.compactMap(state.tab)
        if !tabs.isEmpty {
            SplitGroupRow(tabs: tabs, state: state, chrome: chrome, colors: colors, selection: selection, commands: commands, dropsHere: false)
        }
    }
}

/// A group's header: the group's icon where favicons sit, its name, the chevron, and its count; a click (on the outline)
/// opens or shuts it.
struct OutlineGroupHeader: View {
    let id: String
    let state: BrowserState
    let chrome: ChromeModel
    let colors: Palette
    weak var commands: BrowserCommands?
    @State private var hovering = false
    @Namespace private var selection

    var body: some View {
        if let folder = state.folders.first(where: { $0.id == id }) {
            let members = state.tabs(inSubtree: folder)
            // A group inside another has no color pill.
            let nested = folder.parentID.map { parent in state.folders.contains { $0.id == parent } } ?? false
            let pill = state.groupLabelStyle == .colorPill && !nested
            let containsActive = members.contains { $0.id == state.activeTabID }
            let sleeping = TabListView.isSleeping(members, activeID: state.activeTabID)
            let tint = folder.tagValue?.color ?? colors.tertiary
            HStack(spacing: 9) {
                FolderIcon(folder: folder, colors: colors, size: 13).frame(width: 16, height: 16)
                    .recordLayout("folder-icon-symbol-\(folder.id)")
                HStack(spacing: 5) {
                    Text(folder.name).lineLimit(1).font(.system(size: 13, weight: .semibold)).foregroundStyle(colors.text)
                    if !pill { chevron(open: folder.isOpen).padding(.top, 1) }
                }
                Spacer(minLength: 4)
                if state.showsGroupTabCounts {
                    Text(members.count, format: .number).font(.system(size: 11, weight: .medium).monospacedDigit())
                        .foregroundStyle(colors.tertiary).opacity(!folder.isOpen || hovering ? 1 : 0)
                }
                if pill { chevron(open: folder.isOpen).frame(width: 12) }
            }
            .padding(.horizontal, 10)
            .frame(maxHeight: .infinity)
            .background {
                if pill {
                    let shape = RoundedRectangle(cornerRadius: Radius.control, style: .continuous)
                    shape.fill(tint.opacity(colors.isDark ? 0.18 : 0.12))
                        .overlay(alignment: .leading) { Rectangle().fill(tint).frame(width: 3) }
                        .clipShape(shape)
                }
            }
            .opacity(sleeping && !hovering ? 0.5 : 1)
            .background {
                TabSelectionHighlight(shape: RoundedRectangle(cornerRadius: Radius.row, style: .continuous),
                                      active: containsActive && !folder.isOpen, color: colors.selected, selection: selection, id: "active-tab")
                if hovering && !(containsActive && !folder.isOpen) {
                    RoundedRectangle(cornerRadius: Radius.row, style: .continuous).fill(colors.hover)
                }
            }
            .contentShape(Rectangle())
            .sidebarHover($hovering)
            .animation(.ikagoQuick, value: hovering)
            .contextMenu { FolderContextMenu(folder: folder, state: state, commands: commands) }
            .recordLayout("sidebar-folder-\(folder.id)")
            .accessibilityElement(children: .combine)
            .accessibilityLabel(folder.name)
            .accessibilityValue(folder.disclosureValue(count: members.count, showsCount: state.showsGroupTabCounts))
        }
    }

    private func chevron(open: Bool) -> some View {
        Image(systemName: "chevron.down").font(.system(size: 9, weight: .bold))
            .rotationEffect(.degrees(open ? 0 : -90))
            .foregroundStyle(hovering ? colors.secondary : colors.tertiary)
    }
}

/// The line between the block and the tabs, and New Tab under it.
struct OutlineNewTabRow: View {
    let colors: Palette
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        VStack(spacing: 0) {
            Rectangle().fill(colors.separator).frame(height: 1).padding(.horizontal, 10).padding(.vertical, 6)
            HStack(spacing: 8) {
                Image(systemName: "plus").font(.system(size: 12, weight: .semibold)).frame(width: 16)
                Text("New Tab")
                Spacer()
            }
            .font(.system(size: 13))
            .foregroundStyle(colors.secondary)
            .padding(.horizontal, 10)
            .frame(height: 32)
            .background(RoundedRectangle(cornerRadius: Radius.row, style: .continuous).fill(hovering ? colors.hover : .clear))
            .sidebarHover($hovering)
            .animation(.ikagoQuick, value: hovering)
            .help("New Tab (⌘T)")
        }
    }
}
