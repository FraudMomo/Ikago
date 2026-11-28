import SwiftUI

/// One selection treatment shared by regular, pinned and split tabs in both layouts: the old tab's highlight fades out
/// as the new one's fades in. Rows live in separate hosts (the outline's cells, the rail's tiles), so a fade is the one
/// motion that reads the same everywhere.
struct TabSelectionHighlight<S: Shape>: View {
    let shape: S
    let active: Bool
    let color: Color

    var body: some View {
        ZStack {
            if active { shape.fill(color).transition(.opacity) }
        }
        .animation(.ikagoQuick, value: active)
        .allowsHitTesting(false)
    }
}
