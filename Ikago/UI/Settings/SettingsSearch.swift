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
    /// Matches every term, titles that start with the query first.
    static func results(for query: String) -> [SettingsSearchEntry] {
        let terms = query.lowercased().split(whereSeparator: \.isWhitespace).map(String.init)
        guard !terms.isEmpty else { return [] }
        let found = index.filter { $0.matches(terms) }
        let lead = query.lowercased().trimmingCharacters(in: .whitespaces)
        return found.filter { $0.title.lowercased().hasPrefix(lead) } + found.filter { !$0.title.lowercased().hasPrefix(lead) }
    }

    static let index: [SettingsSearchEntry] = [
        .init(title: "Browser engine", category: .general, section: "Browser Engine", keywords: "webkit chromium relaunch"),
        .init(title: "Translate X videos", category: .general, section: "Chromium", keywords: "twitter video h.264 av1"),
        .init(title: "Live wave in the media player", category: .general, section: "Chromium", keywords: "audio sound"),
        .init(title: "Engine by site", category: .general, section: "Engine by Site", keywords: "webkit chromium rules"),
        .init(title: "Add a site", category: .general, section: "Your Sites", keywords: "engine rule"),
        .init(title: "Default browser", category: .general, section: "Default Browser"),

        .init(title: "Layout", category: .appearance, section: "Layout", keywords: "sidebar top bar tabs"),
        .init(title: "Window border", category: .appearance, section: "Window and Sidebar", keywords: "inset margin"),
        .init(title: "Sidebar style", category: .appearance, section: "Window and Sidebar", keywords: "full icons rail hidden"),
        .init(title: "Sidebar gap", category: .appearance, section: "Window and Sidebar", keywords: "spacing"),
        .init(title: "Floating toolbar", category: .appearance, section: "Top Bar Window"),
        .init(title: "Use the area beside the camera", category: .appearance, section: "Full Screen", keywords: "notch"),
        .init(title: "Light or dark mode", category: .appearance, section: "Color & Theme", keywords: "appearance system"),
        .init(title: "Space colors", category: .appearance, section: "Color & Theme", keywords: "theme tint"),
        .init(title: "Liquid Glass", category: .appearance, section: "Materials", keywords: "transparency"),
        .init(title: "Translucent sidebar", category: .appearance, section: "Materials", keywords: "frosted vibrancy"),
        .init(title: "Tab group labels", category: .appearance, section: "Tab Groups", keywords: "minimal color pill folder"),
        .init(title: "Show tab counts", category: .appearance, section: "Tab Groups"),
        .init(title: "Instant tab switching", category: .appearance, section: "Tab Animations", keywords: "fade motion"),
        .init(title: "Tab highlight animation", category: .appearance, section: "Tab Animations", keywords: "slide spring motion"),
        .init(title: "Tab bar style", category: .appearance, section: "Top Bar Tabs", keywords: "separate compact"),

        .init(title: "Pinned-tab grid", category: .toolbar, section: "Sidebar Essentials", keywords: "essentials pins"),
        .init(title: "Show pinned tabs", category: .toolbar, section: "Pinned Essentials", keywords: "essentials pins top bar"),
        .init(title: "Show bookmarks bar", category: .toolbar, section: "Bookmarks Bar"),
        .init(title: "Switch to an open tab", category: .toolbar, section: "Opening Bookmarks", keywords: "bookmarks"),
        .init(title: "Customize toolbar", category: .toolbar, section: "Customize", keywords: "buttons controls sidebar"),

        .init(title: "New tabs open", category: .tabs, section: "New Tab", keywords: "homepage command bar extension"),
        .init(title: "Focus address bar on new tabs", category: .tabs, section: "New Tab"),
        .init(title: "New tab position", category: .tabs, section: "Tab Placement", keywords: "top bottom"),
        .init(title: "Links opened in new tabs", category: .tabs, section: "Tab Placement"),
        .init(title: "Load new tabs in the background", category: .tabs, section: "Background Tabs"),
        .init(title: "Hibernate inactive tabs", category: .tabs, section: "Memory", keywords: "sleep memory"),
        .init(title: "Keep pinned tabs awake", category: .tabs, section: "Memory", keywords: "hibernate"),

        .init(title: "Search engine", category: .search, section: "Search & Address Bar", keywords: "google duckduckgo bing"),
        .init(title: "Address bar activation", category: .search, section: "Search & Address Bar", keywords: "floating integrated"),
        .init(title: "Suggestions", category: .search, section: "Suggestions", keywords: "history switch to tab autocomplete"),

        .init(title: "Installed extensions", category: .extensions, section: "Extensions", keywords: "add remove web store"),
        .init(title: "Extension updates", category: .extensions, section: "Extension Updates", keywords: "automatic"),

        .init(title: "Always require HTTPS", category: .security, section: "Secure Connections", keywords: "http insecure"),
        .init(title: "Allow HTTP for these sites", category: .security, section: "Secure Connections", keywords: "localhost exceptions"),
        .init(title: "Ask before downloads", category: .security, section: "Downloads", keywords: "files"),
        .init(title: "Warn about fraudulent websites", category: .security, section: "Website Safety", keywords: "phishing"),
        .init(title: "Block trackers", category: .security, section: "Tracking Protection", keywords: "privacy"),
        .init(title: "Block third-party cookies", category: .security, section: "Tracking Protection", keywords: "privacy"),
        .init(title: "Clear website data", category: .security, section: "Browsing Data", keywords: "cookies cache"),
        .init(title: "Clear browsing history", category: .security, section: "Browsing Data"),
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
        .padding(.horizontal, 8).frame(height: 28)
        .background(RoundedRectangle(cornerRadius: 7, style: .continuous).fill(Color.primary.opacity(0.06)))
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
        configuration.label.background(RoundedRectangle(cornerRadius: 8, style: .continuous)
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
