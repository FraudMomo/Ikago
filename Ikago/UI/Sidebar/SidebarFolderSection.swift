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
    weak var commands: BrowserCommands?
    @ViewBuilder let content: () -> Content
    @State private var hovering = false
    @State private var targeted = false
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

    var body: some View {
        // No spacing between the header and the rows: the gap lives inside the animated frame, so a shut group is
        // the same height with its rows mounted or not (measured: the 2 pt step moved every row below it).
        VStack(spacing: 0) {
            header
            if mounted || isOpen {
                VStack(spacing: 2, content: content)
                    .padding(.horizontal, 4)
                    .padding(.top, 2)
                    .padding(.bottom, 4)
                    .fixedSize(horizontal: false, vertical: true)
                    .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { contentHeight = $0 }
                    // Only the frame's height animates; the rows keep their place and the clip reveals them.
                    .frame(height: isOpen ? contentHeight : 0, alignment: .top)
                    .clipped()
                    .opacity(isOpen ? 1 : 0)
            }
        }
        .background {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(fill)
                .allowsHitTesting(false)
                .opacity(isOpen ? 1 : 0)
        }
        .padding(.vertical, 3)
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

    private var header: some View {
        Button { state.toggleFolder(folder.id) } label: {
            HStack(spacing: 8) {
                FolderLabel(folder: folder, colors: colors, isActive: containsActiveTab, style: state.groupLabelStyle)
                Spacer(minLength: 4)
                if state.showsGroupTabCounts {
                    Text(count, format: .number)
                        .font(.system(size: 10, weight: .medium).monospacedDigit())
                        .foregroundStyle(colors.tertiary)
                        .opacity(!isOpen || hovering || targeted ? 1 : 0)
                }
                Image(systemName: "chevron.right")
                    .font(.system(size: 8, weight: .semibold))
                    .rotationEffect(.degrees(isOpen ? 90 : 0))
                    .foregroundStyle(hovering ? colors.secondary : colors.tertiary)
                    .frame(width: 12)
            }
            .padding(.horizontal, 10)
            .frame(height: 34)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .background {
            TabSelectionHighlight(shape: RoundedRectangle(cornerRadius: 10, style: .continuous),
                                  active: showSelection && containsActiveTab && !folder.isOpen, color: colors.selected,
                                  selection: selection, id: "active-tab")
            if targeted || (hovering && !(showSelection && containsActiveTab && !folder.isOpen)) {
                RoundedRectangle(cornerRadius: 10, style: .continuous).fill(targeted ? colors.selected : colors.hover)
            }
        }
        .sidebarHover($hovering)
        .animation(.ikagoQuick, value: hovering)
        .animation(.ikagoQuick, value: targeted)
        .dropDestination(for: TabDrag.self) { drags, _ in
            chrome.endTabDrag()
            guard let id = drags.first?.id, state.tab(id) != nil else { return false }
            withAnimation(.ikagoQuick) { state.moveToFolder(id, folderID: folder.id) }
            return true
        } isTargeted: { targeted = $0 }
        .contextMenu { FolderContextMenu(folder: folder, state: state, commands: commands) }
        .accessibilityLabel(folder.name)
        .accessibilityValue(folder.disclosureValue(count: count, showsCount: state.showsGroupTabCounts))
        .help(folder.disclosureHelp(count: count, showsCount: state.showsGroupTabCounts))
    }
}
