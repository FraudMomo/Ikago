import SwiftUI

/// One dot per Space (click to switch, right-click to rename or delete). The active Space's
/// highlight slides between dots. The sidebar's "Spaces" item.
struct SpaceBar: View {
    let state: BrowserState
    let colors: Palette
    weak var commands: BrowserCommands?
    @Namespace private var selection
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
                }
                .buttonStyle(.plain)
                .help(space.isolated ? "\(space.name) · separate logins" : space.name)
                .contextMenu {
                    Button("Rename…") { commands?.renameSpace(space.id) }
                    Button("Delete Space…") { commands?.deleteSpace(space.id) }.disabled(state.spaces.count < 2)
                }
            }
        }
        .frame(height: 32)
    }
}
