import SwiftUI

/// "Opens in": which engine this site uses, in the site popover. Changing it reopens the page in that engine
/// when it runs; Chromium otherwise starts after a relaunch.
struct SiteEngineRow: View {
    let state: BrowserState
    let tab: TabItem
    weak var commands: BrowserCommands?

    var body: some View {
        if !state.isPrivate, let site = BrowserState.siteForRule(tab.url) {
            let host = URL(string: tab.url)?.host?.lowercased() ?? site
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    EngineLogo(engine: tab.engine ?? BrowserRuntime.engine, size: 16)
                    Text("Opens in").font(.system(size: 12))
                    Spacer(minLength: 8)
                    Picker("Opens in", selection: selection(site: site)) {
                        Text("Automatic (\(automatic(host: host, site: site).title))").tag("")
                        ForEach(BrowserEngine.allCases) { Text($0.title).tag($0.rawValue) }
                    }
                    .labelsHidden().pickerStyle(.menu).controlSize(.small).fixedSize()
                }
                if let chosen = state.browserPreferences.siteEngines?[site].flatMap(BrowserEngine.init(rawValue:)), !BrowserRuntime.runs(chosen) {
                    Text("\(chosen.title) starts after a relaunch.").font(.system(size: 11)).foregroundStyle(.secondary)
                }
            }
        }
    }

    /// What the site would use without its own rule: a list it's in, or the default engine.
    private func automatic(host: String, site: String) -> BrowserEngine {
        var preferences = state.browserPreferences
        preferences.siteEngines?[site] = nil
        return SiteEngines.rule(forHost: host, preferences: preferences) ?? preferences.preferredEngine
    }

    private func selection(site: String) -> Binding<String> {
        Binding(get: { state.browserPreferences.siteEngines?[site] ?? "" }, set: { raw in
            let engine = BrowserEngine(rawValue: raw)
            // Open tabs of the site follow (BrowserState.siteEnginesChanged), after its sign-in has moved.
            state.setSiteEngine(engine, for: site)
        })
    }
}
