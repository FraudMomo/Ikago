import SwiftUI

// MARK: - Site engine row

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

// MARK: - Page actions

/// The site card's page tools as one row of tiles: Reader, Translate, Save Page As and Add to Applications.
struct SitePageActions: View {
    let state: BrowserState
    weak var commands: BrowserCommands?
    let dismiss: () -> Void

    private var controller: BrowserWindowController? { commands as? BrowserWindowController }

    var body: some View {
        let reading = controller?.activeController?.isReading == true
        let translated = controller?.activeController?.translation != nil
        HStack(spacing: 2) {
            tile("doc.plaintext", reading ? "Close Reader" : "Reader", help: "Show the article on its own (⌥⌘R)", tint: .brown, on: reading) {
                controller?.toggleReader(nil)
            }
            tile("translate", translated ? "Original" : "Translate", help: translated ? "Show the page’s own text" : "Translate this page on this Mac",
                 tint: .blue, on: translated) { controller?.translatePage(nil) }
            tile("arrow.down.doc", "Save As…", help: "Save the page as a web archive or PDF (⌘S)", tint: .green) { controller?.savePageAs(nil) }
            if !state.isPrivate, state.webApp == nil {
                tile("plus.app", "Add App", help: "Add to Applications: its own window and a Dock shortcut", tint: .purple) { controller?.installWebApp(nil) }
            }
        }
        .padding(4)
        .siteCard(state.palette)
    }

    private func tile(_ symbol: String, _ title: String, help: String, tint: Color, on: Bool = false, action: @escaping () -> Void) -> some View {
        PageToolTile(symbol: symbol, title: title, tint: tint, on: on, colors: state.palette) {
            dismiss()
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(150))  // the card closes first
                action()
            }
        }
        .help(help)
    }
}

/// One page tool: its symbol in a tinted circle over a short name; filled while on or under the pointer.
private struct PageToolTile: View {
    let symbol: String
    let title: String
    let tint: Color
    let on: Bool
    let colors: Palette
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            VStack(spacing: 5) {
                SettingTile(symbol: symbol, tint: tint)
                Text(title).font(.system(size: 11, weight: .medium)).lineLimit(1).minimumScaleFactor(0.85)
            }
            .frame(maxWidth: .infinity).padding(.vertical, 8)
            .background(RoundedRectangle(cornerRadius: Radius.control, style: .continuous)
                .fill(on ? tint.opacity(0.16) : colors.text.opacity(hovering ? 0.06 : 0)))
            .contentShape(Rectangle())
        }
        .buttonStyle(SiteCardPressStyle(scale: 0.96))
        .onHover { hovering = $0 }
        .animation(.ikagoQuick, value: hovering)
        .accessibilityLabel(title)
    }
}

// MARK: - Protection control

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
