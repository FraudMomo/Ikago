import SwiftUI

/// The new-tab button's right-click menu: reopen a closed tab group (see `BrowserState+ClosedGroups`).
struct ClosedGroupItems: View {
    let state: BrowserState

    var body: some View {
        let folders = state.closedFolders
        if folders.isEmpty {
            Text("No Closed Groups")
        } else {
            Section("Reopen Closed Group") {
                ForEach(folders) { folder in
                    Button(folder.name) { state.reopenFolder(folder.id) }
                }
            }
        }
    }
}
