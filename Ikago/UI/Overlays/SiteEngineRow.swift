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
            let pending = state.browserPreferences.siteEngines?[site].flatMap(BrowserEngine.init(rawValue:)).flatMap { BrowserRuntime.runs($0) ? nil : $0 }
            HStack(spacing: 10) {
                EngineLogo(engine: tab.engine ?? BrowserRuntime.engine, size: 16).frame(width: 26, height: 26)
                    .background(Circle().fill(Color.primary.opacity(0.07)))
                    .contentTransition(.opacity).animation(.ikago, value: tab.engine)
                VStack(alignment: .leading, spacing: 1) {
                    Text("Opens in").font(.system(size: 13)).lineLimit(1)
                    if let pending { Text("\(pending.title) starts after a relaunch").font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(1) }
                }
                .layoutPriority(1)
                Spacer(minLength: 8)
                let current = state.browserPreferences.siteEngines?[site].flatMap(BrowserEngine.init(rawValue:))
                CompactMenu(value: current?.title ?? "Automatic", choices:
                    [MenuChoice(title: "Automatic (\(automatic(host: host, site: site).title))", isOn: current == nil) { selection(site: site).wrappedValue = "" }]
                    + BrowserEngine.allCases.enumerated().map { index, engine in
                        MenuChoice(title: engine.title, isOn: current == engine, separatorBefore: index == 0) { selection(site: site).wrappedValue = engine.rawValue }
                    })
            }
            .padding(.horizontal, 10).frame(minHeight: 44)
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
