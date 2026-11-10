import SwiftUI

/// Which engine opens which site: ready-made lists, then the person's own sites. Shown under the engine cards.
struct SiteEnginesSection: View {
    @Bindable var state: BrowserState
    @State private var newSite = ""
    @State private var newEngine = BrowserEngine.webkit
    @State private var invalid = false

    private var preferences: BrowserPreferences { state.browserPreferences }
    private var defaultEngine: BrowserEngine { preferences.preferredEngine }

    var body: some View {
        PageSection(title: "Engine by Site",
                    footer: "Pages from these sites open in the engine you choose; everything else uses \(defaultEngine.title). A tab switches engines as you browse and shows which one took over. Sign-ins move with a site when you change its engine, but sign-ins through another site (such as Sign in with Google) may ask again. Private windows always use \(defaultEngine.title).") {
            ForEach(Array(SiteEngineList.all.enumerated()), id: \.element.id) { index, list in
                if index > 0 { PageDivider() }
                PageRow(title: list.title, subtitle: "\(list.sites.prefix(4).joined(separator: ", "))… · \(list.suggested.title) suggested: \(list.reason)") {
                    enginePicker(listSelection(list.id))
                }
            }
        }
        PageSection(title: "Your Sites", footer: "A site includes its subdomains. Your sites win over the lists above.") {
            let rules = (preferences.siteEngines ?? [:]).sorted { $0.key < $1.key }
            ForEach(Array(rules.enumerated()), id: \.element.key) { index, rule in
                if index > 0 { PageDivider() }
                PageRow(title: rule.key) {
                    HStack(spacing: 6) {
                        enginePicker(siteSelection(rule.key), allowsDefault: false)
                        Button { state.setSiteEngine(nil, for: rule.key) } label: { Image(systemName: "minus.circle") }
                            .buttonStyle(.borderless).help("Remove \(rule.key)")
                    }
                }
            }
            if !rules.isEmpty { PageDivider() }
            PageRow(title: "Add a site", subtitle: invalid ? "Enter a site such as example.com." : nil) {
                HStack(spacing: 6) {
                    TextField("example.com", text: $newSite).textFieldStyle(.roundedBorder).frame(width: 150).onSubmit(add)
                    Picker("Engine", selection: $newEngine) {
                        ForEach(BrowserEngine.allCases) { Text($0.title).tag($0) }
                    }.labelsHidden().fixedSize()
                    Button("Add", action: add).disabled(newSite.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
        if state.siteEnginesNeedRelaunch {
            HStack(spacing: 10) {
                Image(systemName: "arrow.triangle.2.circlepath").foregroundStyle(.secondary)
                Text("Relaunch to start Chromium for these sites.").font(.system(size: 13))
                Spacer(minLength: 8)
                Button("Relaunch Now") { state.saveNow(); AppRelaunch.relaunch() }.buttonStyle(.borderedProminent)
            }
            .padding(.horizontal, 4)
        }
    }

    private func enginePicker(_ selection: Binding<String>, allowsDefault: Bool = true) -> some View {
        Picker("Engine", selection: selection) {
            if allowsDefault { Text("Default (\(defaultEngine.title))").tag("") }
            ForEach(BrowserEngine.allCases) { Text($0.title).tag($0.rawValue) }
        }
        .labelsHidden().fixedSize()
    }

    private func listSelection(_ id: String) -> Binding<String> {
        Binding(get: { preferences.siteEngineLists?[id] ?? "" },
                set: { state.setListEngine(BrowserEngine(rawValue: $0), for: id) })
    }

    private func siteSelection(_ site: String) -> Binding<String> {
        Binding(get: { preferences.siteEngines?[site] ?? "" },
                set: { if let engine = BrowserEngine(rawValue: $0) { state.setSiteEngine(engine, for: site) } })
    }

    private func add() {
        guard let site = SiteEngines.normalizedSite(newSite) else { invalid = true; return }
        invalid = false
        state.setSiteEngine(newEngine, for: site)
        newSite = ""
    }
}
