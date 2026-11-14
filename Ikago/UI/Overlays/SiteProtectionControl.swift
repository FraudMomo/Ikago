import SwiftUI

/// Explicit, reversible recovery when a site's player depends on blocked requests.
struct SiteProtectionControl: View {
    let state: BrowserState
    let tab: TabItem
    weak var commands: BrowserCommands?
    @State private var changing = false
    private var host: String { URL(string: tab.url)?.host?.lowercased() ?? "" }
    private var disabled: Bool { (state.browserPreferences.trackerExceptions ?? []).contains(host) }
    var body: some View {
        SiteSettingRow(symbol: "hand.raised.fill", title: "Block trackers", detail: changing ? "Reloading…" : "Turning it off reloads the site", tint: .green) {
            Toggle("Block trackers", isOn: Binding(get: { !disabled }, set: { enabled in
                var exceptions = state.browserPreferences.trackerExceptions ?? []
                exceptions.removeAll { $0 == host }
                if !enabled { exceptions.append(host) }
                state.browserPreferences.trackerExceptions = exceptions
                BrowserSecurity.shared.apply(state.browserPreferences, rebuildRules: false)
                changing = true
                Task { @MainActor in
                    await BrowserSecurity.shared.prepare()
                    changing = false
                    if commands?.activeExtensionTab?.tab.id == tab.id { commands?.activeExtensionTab?.page?.reload() }
                }
            })).labelsHidden().toggleStyle(.switch).controlSize(.mini).disabled(changing || host.isEmpty)
        }
    }
}
