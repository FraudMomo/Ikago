import SwiftUI

/// One dot per Space (click to switch, right-click to rename or delete). The active Space's
/// highlight slides between dots. The sidebar's "Spaces" item. Dropping tabs on another Space's dot moves them there.
struct SpaceBar: View {
    let state: BrowserState
    let colors: Palette
    weak var commands: BrowserCommands?
    @Namespace private var selection
    @State private var dropTarget: UUID?
    @Environment(\.inGlassGroup) private var inGroup

    var body: some View {
        HStack(spacing: 4) {
            ForEach(state.spaces) { space in
                let active = space.id == state.activeSpaceID
                Button { withAnimation(.ikago) { state.switchSpace(space.id) } } label: {
                    Image(systemName: space.symbol)
                        .font(.system(size: 12, weight: active ? .semibold : .regular))
                        .foregroundStyle(active ? colors.text : colors.tertiary)
                        .frame(width: 30, height: 30)
                        .background {
                            if active && (inGroup || !colors.glass) {
                                Circle().fill(colors.selected)
                                    .matchedGeometryEffect(id: "active-space", in: selection)
                            }
                        }
                        .contentShape(Circle())
                        .glassControl(Circle(), colors, active: active)
                        .overlay {
                            Circle().strokeBorder(colors.accent, lineWidth: 2)
                                .opacity(dropTarget == space.id ? 1 : 0)
                                .scaleEffect(dropTarget == space.id ? 1.08 : 0.9)
                        }
                        .animation(.ikagoQuick, value: dropTarget)
                }
                .buttonStyle(.plain)
                .dropDestination(for: TabDrag.self) { drags, _ in
                    (commands as? BrowserWindowController)?.chrome.endTabDrag()
                    guard !active, let id = drags.first?.id else { return false }
                    // The dragged tab and every selected tab with it (`TabDrag.companions`), from any window.
                    let ids = TabDrag.travelling(with: id)
                    for tab in ids { BrowserWindows.bring(tab, into: state) }
                    let moving = ids.filter { state.tab($0) != nil }
                    guard !moving.isEmpty else { return false }
                    withAnimation(.ikago) { state.moveTabs(moving, toSpace: space.id) }
                    (commands as? BrowserWindowController)?.chrome.selectedTabIDs = []
                    return true
                } isTargeted: { targeted in
                    if targeted, !active { dropTarget = space.id } else if dropTarget == space.id { dropTarget = nil }
                }
                .help(space.isolated ? "\(space.name) · separate logins" : space.name)
                .contextMenu {
                    Button("Rename…") { commands?.renameSpace(space.id) }
                    Button(space.isolated ? "Use Shared Logins" : "Use Separate Logins") {
                        commands?.setSpaceShared(space.id, shared: !space.isolated)
                    }
                    Text("Future loads use that cookie store. Cookies are not copied.")
                    Button("Delete Space…") { commands?.deleteSpace(space.id) }.disabled(state.spaces.count < 2)
                }
            }
        }
        .frame(height: 32)
    }
}
