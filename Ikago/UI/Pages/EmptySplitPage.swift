import SwiftUI

struct EmptySplitPage: View {
    let state: BrowserState
    let tabID: String?
    @State private var targeted = false
    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "rectangle.split.2x1").font(.system(size: 28)).foregroundStyle(.secondary)
            Text("Drag another tab here").font(.title3.weight(.medium))
            Text("Drop a tab from the sidebar or top bar to fill this split pane.")
                .foregroundStyle(.secondary).multilineTextAlignment(.center)
            Button("Close Empty Pane") { if let tabID { state.closeTab(tabID) } }
                .controlSize(.small)
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(targeted ? state.palette.accent.opacity(0.12) : state.palette.pageBackground)
        .contentShape(Rectangle())
        .dropDestination(for: TabDrag.self) { tabs, _ in
            guard let tabID, let id = tabs.first?.id else { return false }
            state.fillEmptySplit(tabID, with: id)
            return true
        } isTargeted: { targeted = $0 }
    }
}
