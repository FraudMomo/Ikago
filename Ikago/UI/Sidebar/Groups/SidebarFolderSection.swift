import SwiftUI

/// A quiet section header with the group's icon; open, the whole group sits on a light fill of its color,
/// keeping member rows styled like other tabs.
struct SidebarFolderSection<Content: View>: View {
    let folder: TabFolder
    let state: BrowserState
    let chrome: ChromeModel
    let colors: Palette
    let selection: Namespace.ID
    let showSelection: Bool
    /// The group's tab count and whether it holds the active tab, worked out once by the list for every group.
    let count: Int
    let containsActiveTab: Bool
    /// Every tab in the group is closed or asleep: the header fades back until it is hovered or a tab wakes.
    var sleeping = false
    /// 0 for a top-level group; nested groups sit inside their parent's card as plain headers.
    var depth = 0
    weak var commands: BrowserCommands?
    @ViewBuilder let content: () -> Content
    @State private var hovering = false
    @State private var targeted = false
    /// Where a dragged group would land on this header (`GroupDropZone`).
    @State private var groupZone: GroupDropZone?
    @State private var headerHeight = MeasuredLength()
    /// What is drawn. It follows `folder.isOpen` from inside the list's own view graph: the list renders in a separate
    /// host, where an animation started in the sidebar's (or by a menu command) doesn't arrive.
    @State private var open: Bool?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Rows stay mounted while the group is open and while it animates shut.
    @State private var mounted = false
    /// The rows' natural height, measured; the group's frame animates between 0 and this.
    @State private var contentHeight: CGFloat?
    @State private var closing: DispatchWorkItem?

    private var isOpen: Bool { open ?? folder.isOpen }
    private var asFolder: Bool { state.sidebarGroupStyle == .folders }
    private var nested: Bool { depth > 0 }
    /// Indented under the parent's name, no card or pill of its own: one card per top-level group.
    private var plain: Bool { asFolder || nested }

    var body: some View {
        // No spacing between the header and the rows: the gap lives inside the animated frame, so a shut group is
        // the same height with its rows mounted or not (measured: the 2 pt step moved every row below it).
        VStack(spacing: 0) {
            header
            if mounted || isOpen {
                VStack(spacing: 2, content: content)
                    // Cards inset their rows a little; folders indent them under the folder, like a file tree.
                    .padding(.leading, asFolder ? 22 : nested ? 16 : 4)
                    .padding(.trailing, plain ? 0 : 4)
                    .padding(.top, plain ? 0 : 2)
                    .padding(.bottom, plain ? 0 : 4)
                    .fixedSize(horizontal: false, vertical: true)
                    .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { contentHeight = $0 }
                    // Only the frame's height animates; the rows keep their place and the clip reveals them.
                    .frame(height: isOpen ? contentHeight : 0, alignment: .top)
                    .clipped()
                    .opacity(isOpen ? 1 : 0)
            }
        }
        .background {
            RoundedRectangle(cornerRadius: pill ? Self.pillRadius : Radius.row, style: .continuous)
                .fill(fill)
                .allowsHitTesting(false)
                .opacity(isOpen && !plain ? 1 : 0)
        }
        .padding(.vertical, plain ? 0 : pill ? 1 : 3)
        .recordLayout("sidebar-folder-\(folder.id)")
#if DEBUG
        .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { GroupDisclosureProbe.shared.note(folder.name, $0) }
#endif
        .onAppear {
            if open == nil { open = folder.isOpen; mounted = folder.isOpen }
        }
        .onChange(of: folder.isOpen) { _, now in setOpen(now) }
    }

    private func setOpen(_ now: Bool) {
        closing?.cancel()
        let animation: Animation? = reduceMotion ? nil : .groupDisclosure
        if now {
            // Mount the rows shut first so their height is known, then open: the frame has something to animate to.
            if !mounted {
                mounted = true
                var transaction = Transaction()
                transaction.disablesAnimations = true
                withTransaction(transaction) { open = false }
                DispatchQueue.main.async { withAnimation(animation) { open = true } }
            } else {
                withAnimation(animation) { open = true }
            }
        } else {
            withAnimation(animation) { open = false }
            let work = DispatchWorkItem { mounted = false }
            closing = work
            // The spring is still a few points from shut at its nominal duration; unmount once it has settled.
            DispatchQueue.main.asyncAfter(deadline: .now() + (reduceMotion ? 0 : Animation.groupDisclosureDuration * 1.6), execute: work)
        }
    }

    /// The group's color, lightly; a neutral wash without one.
    private var fill: Color {
        guard let tint = folder.tagValue?.color else { return colors.text.opacity(colors.isDark ? 0.06 : 0.04) }
        return tint.opacity(colors.isDark ? 0.16 : 0.11)
    }

    /// The Color pill label spans the whole header like a bookmark in a book: a light wash of the group's color with a
    /// solid spine of it down the leading edge. Squarer than a tab row (`Radius.control`), so groups read as their own kind.
    private var pill: Bool { state.groupLabelStyle == .colorPill && !nested }
    static var pillRadius: CGFloat { Radius.control }
    private var tint: Color { folder.tagValue?.color ?? colors.tertiary }
    private var pillFill: Color { tint.opacity(colors.isDark ? 0.18 : 0.12) }

    private var chevron: some View {
        Image(systemName: "chevron.down")
            .font(.system(size: 9, weight: .bold))
            .rotationEffect(.degrees(isOpen ? 0 : -90))
            .foregroundStyle(hovering ? colors.secondary : colors.tertiary)
    }

    /// Laid out like a tab row: the group's icon where tab favicons sit, the name where their titles start. The name
    /// is semibold, a title for the rows under it. A pill keeps its chevron at the far end, out of the colored label;
    /// plain headers put it right after the name, like a disclosure title.
    private var header: some View {
        Button { state.toggleFolder(folder.id) } label: {
            HStack(spacing: 9) {
                FolderIcon(folder: folder, colors: colors, size: 13).frame(width: 16, height: 16)
                HStack(spacing: 5) {
                    Text(folder.name).lineLimit(1)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(colors.text)
                    if !pill { chevron.padding(.top, 1) }
                }
                Spacer(minLength: 4)
                if state.showsGroupTabCounts {
                    Text(count, format: .number)
                        .font(.system(size: 11, weight: .medium).monospacedDigit())
                        .foregroundStyle(colors.tertiary)
                        .opacity(!isOpen || hovering || targeted ? 1 : 0)
                }
                if pill { chevron.frame(width: 12) }
            }
            .padding(.horizontal, 10)
            .frame(height: pill ? 32 : nested ? 30 : 34)
            .background {
                if pill {
                    let shape = RoundedRectangle(cornerRadius: Self.pillRadius, style: .continuous)
                    shape.fill(pillFill)
                        .overlay(alignment: .leading) { Rectangle().fill(tint).frame(width: 3) }
                        .clipShape(shape)
                }
            }
            .opacity(sleeping && !hovering && !targeted ? 0.5 : 1)
            .animation(reduceMotion ? nil : .ikago, value: sleeping)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .background {
            TabSelectionHighlight(shape: RoundedRectangle(cornerRadius: Radius.row, style: .continuous),
                                  active: showSelection && containsActiveTab && !folder.isOpen, color: colors.selected,
                                  selection: selection, id: "active-tab")
            let into = targeted || groupZone == .into
            if into || (hovering && !(showSelection && containsActiveTab && !folder.isOpen)) {
                RoundedRectangle(cornerRadius: Radius.row, style: .continuous).fill(into ? colors.selected : colors.hover)
            }
        }
        .sidebarHover($hovering)
        .animation(.ikagoQuick, value: hovering)
        .animation(.ikagoQuick, value: targeted)
        .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { headerHeight.value = $0 }
        .opacity(chrome.draggingFolderID == folder.id ? 0.5 : 1)
        .overlay(alignment: groupZone == .after ? .bottom : .top) {
            if groupZone == .before || groupZone == .after {
                GroupInsertionLine(colors: colors).offset(y: groupZone == .after ? 1 : -1).transition(.opacity)
            }
        }
        .animation(.ikagoQuick, value: groupZone)
        .onDrag {
            chrome.beginFolderDrag(folder.id)
            return GroupDrag.provider(folder.id)
        } preview: {
            GroupDragPreview(folder: folder, colors: colors)
        }
        .onDrop(of: [.ikagoTab, .ikagoGroup], delegate: FolderHeaderDropDelegate(
            folder: folder, state: state, chrome: chrome, length: headerHeight,
            tabTargeted: $targeted, zone: $groupZone))
        .onChange(of: chrome.draggingFolderID) { _, id in if id == nil { groupZone = nil } }
        .contextMenu { FolderContextMenu(folder: folder, state: state, commands: commands) }
        .accessibilityLabel(folder.name)
        .accessibilityValue(folder.disclosureValue(count: count, showsCount: state.showsGroupTabCounts))
    }
}
