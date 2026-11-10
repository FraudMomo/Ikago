import SwiftUI

/// "Private" beside the address in a private window, so it can't be mistaken for a normal one.
struct PrivateBadge: View {
    let state: BrowserState
    let colors: Palette

    var body: some View {
        if state.isPrivate {
            Text("Private")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(colors.text)
                .padding(.horizontal, 7).frame(height: 17)
                .background(Capsule().fill(colors.text.opacity(0.14)))
                .help("Private window: history, website data and the session are not kept")
        }
    }
}
