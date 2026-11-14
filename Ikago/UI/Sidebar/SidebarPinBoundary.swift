import SwiftUI

/// A drop line between sections that takes no room in the list: the target hangs over the gap between groups,
/// so groups keep their usual spacing and nothing moves when a drag starts.
struct SidebarPinBoundary: View {
    let state: BrowserState
    let chrome: ChromeModel
    let afterFolderID: String?
    @State private var targeted = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Color.clear.frame(height: 0).overlay {
            Capsule().fill(state.palette.accent.opacity(targeted ? 0.85 : 0))
                .frame(height: 2).padding(.horizontal, 10).frame(height: 8)
                .contentShape(Rectangle())
                .onDrop(of: [.ikagoTab], isTargeted: $targeted) { providers in
                    guard let provider = providers.first else { return false }
                    TabDrag.load(provider, into: state) { id in
                        withAnimation(reduceMotion ? nil : .ikagoQuick) {
                            state.movePin(id, intoGrid: false, afterFolderID: afterFolderID)
                        }
                        chrome.endTabDrag()
                    }
                    return true
                }
        }
        .animation(reduceMotion ? nil : .ikagoQuick, value: targeted)
        .recordLayout("sidebar-pin-boundary-\(afterFolderID ?? "top")")
        .accessibilityLabel(afterFolderID == nil ? "Pin above groups" : "Pin after group")
    }
}
