import SwiftUI
import UniformTypeIdentifiers

extension View {
    /// Only live tabs can be moved into tab lists, pins or splits.
    func openTabDrop(state: BrowserState, chrome: ChromeModel, perform: @escaping @MainActor @Sendable (String, CGPoint) -> Void) -> some View {
        onDrop(of: [.ikagoTab], isTargeted: nil) { providers, point in
            guard let provider = providers.first else { return false }
            chrome.endTabDrag()
            TabDrag.load(provider) { id in if state.tab(id) != nil { perform(id, point) } }
            return true
        }
    }
}
