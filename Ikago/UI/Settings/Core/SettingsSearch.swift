import SwiftUI

/// One searchable setting: where it lives (category and section) and words people might type for it.
struct SettingsSearchEntry: Identifiable, Hashable {
    let title: String
    let category: SettingsCategory
    let section: String
    var keywords = ""
    var id: String { "\(category.rawValue)/\(section)/\(title)" }

    func matches(_ terms: [String]) -> Bool {
        let haystack = "\(title) \(section) \(category.title) \(keywords)".lowercased()
        return terms.allSatisfy(haystack.contains)
    }
}

enum SettingsSearch {
    /// Every setting becomes an address-field action that opens Settings at it (`openSetting:`). Once per launch.
    @MainActor static func registerPaletteActions() {
        guard PaletteAction.settings.isEmpty else { return }
        PaletteAction.settings = index.map { entry in
            PaletteAction("setting:" + entry.id, entry.title, entry.category.symbol, "",
                          "\(entry.section) \(entry.category.title) \(entry.keywords) setting settings preference", "openSetting:",
                          argument: entry.id, kind: .setting, detail: "Settings · \(entry.category.title)")
        }
    }

    /// Matches every term, titles that start with the query first.
    static func results(for query: String) -> [SettingsSearchEntry] {
        let terms = query.lowercased().split(whereSeparator: \.isWhitespace).map(String.init)
        guard !terms.isEmpty else { return [] }
        let found = index.filter { $0.matches(terms) }
        let lead = query.lowercased().trimmingCharacters(in: .whitespaces)
        return found.filter { $0.title.lowercased().hasPrefix(lead) } + found.filter { !$0.title.lowercased().hasPrefix(lead) }
    }

    static let index: [SettingsSearchEntry] = [
        .init(title: "Sidebar side", category: .appearance, section: "Window and Sidebar", keywords: "left right window controls traffic lights"),
        .init(title: "Page assistance", category: .general, section: "Apple Intelligence", keywords: "ai summarize chat local model"),
        .init(title: "Browser engine", category: .general, section: "Browser Engine", keywords: "webkit chromium relaunch"),
        .init(title: "Translate X videos", category: .general, section: "Advanced", keywords: "twitter video h.264 av1 chromium"),
        .init(title: "Engine by site", category: .general, section: "Engine by Site", keywords: "webkit chromium rules"),
        .init(title: "Add a site", category: .general, section: "Your Sites", keywords: "engine rule"),
        .init(title: "Default browser", category: .general, section: "Default Browser"),
        .init(title: "Tabs from other devices", category: .general, section: "Other Devices", keywords: "iphone ipad safari icloud tab groups sync"),
        .init(title: "Save passwords", category: .passwords, section: "AutoFill", keywords: "offer save update login"),
        .init(title: "Export to Apple Passwords", category: .passwords, section: "Export to Apple Passwords", keywords: "icloud keychain sync csv"),
        .init(title: "Website notifications", category: .security, section: "Notifications", keywords: "alerts push permission sites banner"),
        .init(title: "Translate pages into", category: .general, section: "Translation", keywords: "language translate page on device"),
        .init(title: "Web apps", category: .general, section: "Web Apps", keywords: "install site application dock launchpad window"),
        .init(title: "Handoff", category: .general, section: "Other Devices", keywords: "iphone continuity continue sync"),

        .init(title: "Layout", category: .appearance, section: "Layout", keywords: "sidebar tabs top row chrome attached"),
        .init(title: "Window border", category: .appearance, section: "Window and Sidebar", keywords: "inset margin"),
        .init(title: "Sidebar style", category: .appearance, section: "Window and Sidebar", keywords: "full icons rail hidden"),
        .init(title: "Sidebar gap", category: .appearance, section: "Window and Sidebar", keywords: "spacing"),
        .init(title: "Move from the page's top edge", category: .appearance, section: "Moving the Window", keywords: "drag window grab title bar header"),
        .init(title: "Edge height", category: .appearance, section: "Moving the Window", keywords: "drag window grab thin"),
        .init(title: "Double-click to zoom", category: .appearance, section: "Moving the Window", keywords: "maximize fill window"),
        .init(title: "Use the area beside the camera", category: .appearance, section: "Full Screen", keywords: "notch"),
        .init(title: "Light or dark mode", category: .appearance, section: "Color & Theme", keywords: "appearance system"),
        .init(title: "Space colors", category: .appearance, section: "Color & Theme", keywords: "theme tint"),
        .init(title: "Liquid Glass", category: .appearance, section: "Materials", keywords: "transparency"),
        .init(title: "Translucent sidebar", category: .appearance, section: "Materials", keywords: "frosted vibrancy"),
        .init(title: "Tab group labels", category: .appearance, section: "Tab Groups", keywords: "minimal color pill folder"),
        .init(title: "Groups in the sidebar", category: .appearance, section: "Tab Groups", keywords: "cards folders tree indent"),
        .init(title: "Address bar", category: .appearance, section: "Sidebar + Tabs", keywords: "url centered centred full width wide title dia chrome"),
        .init(title: "Reveal sidebar at the window edge", category: .appearance, section: "Window and Sidebar", keywords: "peek hover edge hidden sidebar slide"),
        .init(title: "Groups in Sidebar + Tabs", category: .appearance, section: "Tab Groups", keywords: "tab row top bar chips icon sidebar rail where placement"),
        .init(title: "Show tab counts", category: .appearance, section: "Tab Groups"),
        .init(title: "Instant tab switching", category: .appearance, section: "Tab Animations", keywords: "fade motion"),
        .init(title: "Tab highlight animation", category: .appearance, section: "Tab Animations", keywords: "slide spring motion"),

        .init(title: "Tab previews", category: .tabs, section: "Tab Previews", keywords: "hover popover card"),
        .init(title: "Open links in Peek", category: .tabs, section: "Peek", keywords: "shift click preview link automatic off"),
        .init(title: "Peek links from pinned tabs", category: .tabs, section: "Peek", keywords: "automatic other sites"),
        .init(title: "Peek search results", category: .tabs, section: "Peek", keywords: "automatic google"),
        .init(title: "Peek links that open a new tab", category: .tabs, section: "Peek", keywords: "automatic target blank"),
        .init(title: "Page thumbnail in previews", category: .tabs, section: "Tab Previews", keywords: "hover screenshot image"),
        .init(title: "Space header and shortcuts", category: .toolbar, section: "Sidebar", keywords: "space name assistant bookmarks history navigation"),
        .init(title: "Keep pinned tabs and groups in view", category: .toolbar, section: "Sidebar", keywords: "pinned pins fixed sticky scroll top"),
        .init(title: "Pinned-tab grid", category: .toolbar, section: "Sidebar Essentials", keywords: "essentials pins"),
        .init(title: "Grid columns", category: .toolbar, section: "Sidebar Essentials", keywords: "pinned tabs size count"),
        .init(title: "Show bookmarks bar", category: .toolbar, section: "Bookmarks Bar"),
        .init(title: "Switch to an open tab", category: .toolbar, section: "Opening Bookmarks", keywords: "bookmarks"),
        .init(title: "Customize toolbar", category: .toolbar, section: "Customize", keywords: "buttons controls sidebar"),
        .init(title: "Bar height", category: .toolbar, section: "Customize", keywords: "tabs toolbar address height compact large"),
        .init(title: "Address field buttons", category: .toolbar, section: "Customize", keywords: "reload refresh site extensions puzzle"),
        .init(title: "Icons-only sidebar controls", category: .toolbar, section: "Customize", keywords: "rail compact icons downloads"),

        .init(title: "New tabs open", category: .tabs, section: "New Tab", keywords: "homepage command bar extension"),
        .init(title: "Focus address bar on new tabs", category: .tabs, section: "New Tab"),
        .init(title: "New tab position", category: .tabs, section: "Tab Placement", keywords: "top bottom"),
        .init(title: "Links opened in new tabs", category: .tabs, section: "Tab Placement"),
        .init(title: "Load new tabs in the background", category: .tabs, section: "Background Tabs"),
        .init(title: "Memory approach", category: .performance, section: "Memory", keywords: "conservative balanced responsive resources pressure ram inactive tabs hibernate sleep"),
        .init(title: "Keep pinned tabs awake", category: .performance, section: "Memory", keywords: "pins essentials"),
        .init(title: "Always keep these sites awake", category: .performance, section: "Memory", keywords: "exceptions sleep memory"),
        .init(title: "Performance monitor", category: .performance, section: "Monitor", keywords: "cpu memory energy frames speed slow fps"),

        .init(title: "Search engine", category: .search, section: "Search & Address Bar", keywords: "google duckduckgo bing"),
        .init(title: "Address bar activation", category: .search, section: "Search & Address Bar", keywords: "floating integrated"),
        .init(title: "Suggestions", category: .search, section: "Suggestions", keywords: "history switch to tab autocomplete"),

        .init(title: "Installed extensions", category: .extensions, section: "Extensions", keywords: "add remove web store"),
        .init(title: "Extension website access", category: .extensions, section: "Installed", keywords: "permissions allow every website ask privacy site access"),
        .init(title: "Extension updates", category: .extensions, section: "Extension Updates", keywords: "automatic"),
        .init(title: "Safari extensions", category: .extensions, section: "Safari Extensions", keywords: "app store mac apps webkit"),

        .init(title: "Always require HTTPS", category: .security, section: "Secure Connections", keywords: "http insecure"),
        .init(title: "Allow HTTP for these sites", category: .security, section: "Secure Connections", keywords: "localhost exceptions"),
        .init(title: "Ask before downloads", category: .security, section: "Downloads", keywords: "files"),
        .init(title: "Warn about fraudulent websites", category: .security, section: "Website Safety", keywords: "phishing"),
        .init(title: "Block trackers", category: .security, section: "Tracking Protection", keywords: "privacy"),
        .init(title: "Block third-party cookies", category: .security, section: "Tracking Protection", keywords: "privacy"),
        .init(title: "Clear website data", category: .security, section: "Browsing Data", keywords: "cookies cache"),
        .init(title: "Clear browsing history", category: .security, section: "Browsing Data"),
        .init(title: "Browsing history", category: .history, section: "History", keywords: "visited pages sites search by date by site"),
        .init(title: "Clear browsing data", category: .history, section: "History",
              keywords: "delete history cookies cache searches last hour today since yesterday custom range"),
        .init(title: "Clear data when quitting", category: .security, section: "Browsing Data"),

        .init(title: "Fill passwords", category: .passwords, section: "AutoFill", keywords: "autofill touch id"),
        .init(title: "Import passwords", category: .passwords, section: "Import from Apple Passwords", keywords: "csv export"),
        .init(title: "Saved passwords", category: .passwords, section: "Saved in Ikago", keywords: "vault logins"),

        .init(title: "Import browser data", category: .imports, section: "Import", keywords: "bookmarks history tabs chrome firefox"),

        .init(title: "Version", category: .about, section: "Ikago", keywords: "about"),
        .init(title: "Automatic security updates", category: .about, section: "Ikago", keywords: "chromium"),
        .init(title: "Developer tools", category: .about, section: "Developer", keywords: "inspect element devtools"),
    ]
}

/// The navigation column's search field, in the quiet style of the rows below it.
struct SettingsSearchField: View {
    @Binding var text: String
    var focused: FocusState<Bool>.Binding

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass").font(.system(size: 12)).foregroundStyle(.secondary)
            TextField("Search Settings", text: $text).textFieldStyle(.plain).font(.system(size: 13)).focused(focused)
            if !text.isEmpty {
                Button { text = "" } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary) }
                    .buttonStyle(.plain).accessibilityLabel("Clear search")
            }
        }
        .padding(.horizontal, 9).frame(height: 30)
        .background(RoundedRectangle(cornerRadius: Radius.control, style: .continuous).fill(Color.primary.opacity(0.045)))
        .overlay(RoundedRectangle(cornerRadius: Radius.control, style: .continuous).strokeBorder(Color.primary.opacity(0.07), lineWidth: 0.5))
    }
}

/// Matching settings, each opening its page at the right section.
struct SettingsSearchResults: View {
    let results: [SettingsSearchEntry]
    let colors: Palette
    let open: (SettingsSearchEntry) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            if results.isEmpty {
                Text("No Results").font(.system(size: 13)).foregroundStyle(.secondary).padding(10)
            }
            ForEach(results) { entry in
                Button { open(entry) } label: {
                    VStack(alignment: .leading, spacing: 1) {
                        Text(entry.title).font(.system(size: 13)).foregroundStyle(colors.text).lineLimit(1)
                        Text(entry.category.title).font(.system(size: 11)).foregroundStyle(colors.secondary).lineLimit(1)
                    }
                    .padding(.horizontal, 10).padding(.vertical, 5)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
                }
                .buttonStyle(SettingsResultStyle())
            }
        }
    }
}

private struct SettingsResultStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.background(RoundedRectangle(cornerRadius: Radius.control, style: .continuous)
            .fill(Color.primary.opacity(configuration.isPressed ? 0.09 : 0)))
    }
}

/// The section a search result points at, so its page can scroll there and mark it briefly.
private struct SettingsHighlightKey: EnvironmentKey { static let defaultValue: String? = nil }
extension EnvironmentValues {
    var settingsHighlight: String? {
        get { self[SettingsHighlightKey.self] }
        set { self[SettingsHighlightKey.self] = newValue }
    }
}
