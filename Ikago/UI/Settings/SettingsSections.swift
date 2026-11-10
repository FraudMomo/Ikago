import SwiftUI
import WebKit

struct SearchSettingsSection: View {
    @Bindable var state: BrowserState
    var body: some View {
        PageSection(title: "Search & Address Bar") {
            PageRow(title: "Search engine") {
                Picker("Search engine", selection: $state.searchEngine) {
                    ForEach(SearchEngine.allCases) { Text($0.name).tag($0) }
                }.labelsHidden()
            }
            PageDivider()
            PageRow(title: "Address bar activation", subtitle: "Sidebar only. Integrated edits in the sidebar; Floating opens a search island. Top Bar always edits inline.") {
                Picker("Address bar", selection: $state.addressStyle) {
                    ForEach(AddressStyle.allCases) { Text($0.name).tag($0) }
                }.labelsHidden().disabled(state.tabLayout.usesTopTabs)
            }
        }
        PageSection(title: "Suggestions", footer: "Search-engine autocomplete sends search text as you type to your selected engine. Addresses are excluded. Suggestions may be unavailable when offline.") {
            PageRow(title: "Show history in suggestions") {
                Toggle("History suggestions", isOn: $state.searchShowsHistory).labelsHidden().toggleStyle(.switch)
            }
            PageDivider()
            PageRow(title: "Show Switch to Tab suggestions") {
                Toggle("Switch to Tab suggestions", isOn: Binding(
                    get: { state.browserPreferences.showSwitchToTabSuggestions ?? true },
                    set: { state.browserPreferences.showSwitchToTabSuggestions = $0 }))
                    .labelsHidden().toggleStyle(.switch)
            }
            PageDivider()
            PageRow(title: "Search-engine autocomplete") {
                Toggle("Search-engine autocomplete", isOn: Binding(
                    get: { state.browserPreferences.searchEngineAutocomplete ?? false },
                    set: { state.browserPreferences.searchEngineAutocomplete = $0 }))
                    .labelsHidden().toggleStyle(.switch)
            }
        }
    }
}

struct PrivacySettingsSection: View {
    let state: BrowserState
    @State private var confirmClear = false
    @State private var cleared = false
    @State private var cacheCleared = false
    @State private var clearing = false
    @State private var issue: String?

    private func clearWebsiteData() async {
        clearing = true
        defer { clearing = false }
        do {
            try await EngineCookieSync.clearBothEngines(profile: state.activeSpace.profileID,
                                                        knownURLs: state.history.map(\.url) + state.tabs.map(\.url))
            cleared = true
            issue = nil
        } catch { issue = error.localizedDescription }
    }

    var body: some View {
        PageSection(title: "Browsing Data", footer: "Camera and microphone requests are denied unless you allow them. Popups need a click.") {
            PageRow(title: "Website data", subtitle: "Cookies, logins and storage for “\(state.activeSpace.name)”") {
                Button(clearing ? "Clearing…" : cleared ? "Cleared" : "Clear…") { confirmClear = true }
                    .disabled(clearing || state.isPrivate)
                    .confirmationDialog("Clear all website data for this Space?", isPresented: $confirmClear) {
                        Button("Clear Website Data", role: .destructive) { Task { await clearWebsiteData() } }
                    } message: { Text("You will be signed out of websites in this Space. Extensions stay installed.") }
            }
            if let issue {
                Text(issue).font(.system(size: 12)).foregroundStyle(.red).padding(.horizontal, 16).padding(.bottom, 10)
            }
            PageDivider()
            PageRow(title: "Browsing history", subtitle: "\(state.history.count) pages") {
                Button("Clear") { state.history.removeAll(); state.scheduleSave() }.disabled(state.history.isEmpty)
            }
            PageDivider()
            PageRow(title: "Cached site icons", subtitle: "Saved icons for tabs, pins and bookmarks across Spaces") {
                Button(cacheCleared ? "Cleared" : "Clear Cache") { FaviconCache.shared.clear(); cacheCleared = true }
            }
            PageDivider()
            PageRow(title: "Clear history and website data when quitting",
                    subtitle: "Every Space. Open tabs and bookmarks stay") {
                Toggle("Clear when quitting", isOn: Binding(get: { state.browserPreferences.clearDataOnQuit ?? false },
                                                           set: { state.browserPreferences.clearDataOnQuit = $0 }))
                    .labelsHidden().toggleStyle(.switch)
            }
        }
    }
}

struct AboutSettingsSection: View {
    @Bindable var state: BrowserState
    var body: some View {
        HStack(spacing: 18) {
            Image(nsImage: NSApp.applicationIconImage).resizable().frame(width: 84, height: 84)
                .shadow(color: .black.opacity(0.25), radius: 12, y: 6)
            VStack(alignment: .leading, spacing: 6) {
                Text("Ikago").font(.system(size: 22, weight: .bold))
                Text("A lightweight native browser for the Mac").font(.system(size: 13)).foregroundStyle(.secondary)
                HStack(spacing: 6) {
                    EngineLogo(engine: BrowserRuntime.engine, size: 16)
                    Text("Running on \(BrowserRuntime.engine.title)").font(.system(size: 12, weight: .medium))
                }
            }
        }
        .padding(.vertical, 4)
        PageSection(title: "Ikago") {
            PageRow(title: "Version", subtitle: "\(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.1.0") (\(Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "1"))") { EmptyView() }
            PageDivider()
            PageRow(title: "Browser engine", subtitle: BrowserRuntime.engine == .webkit ? "Apple WebKit · engine security updates arrive with macOS" : "Chromium \(CEFVersion.chromium)") { EmptyView() }
            PageDivider()
            PageRow(title: "Chromium", subtitle: "Version \(CEFVersion.chromium)") { EmptyView() }
            PageDivider()
            ChromiumUpdateRow()
        }
        PageSection(title: "Developer") {
            PageRow(title: "Developer tools", subtitle: "Inspect Element and ⌥⌘I") {
                Toggle("Developer tools", isOn: $state.developerTools).labelsHidden().toggleStyle(.switch)
            }
        }
    }
}

/// Automatic Chromium updates, run in the background by `scripts/auto_update.py`.
private struct ChromiumUpdateRow: View {
    private var updates: ChromiumUpdates { .shared }

    var body: some View {
        PageRow(title: "Automatic security updates", subtitle: updates.summary) {
            HStack(spacing: 8) {
                if updates.isReady {
                    Button("Relaunch to Update") { updates.relaunchToInstall() }.buttonStyle(.borderedProminent)
                } else if updates.isEnabled {
                    Button("Check Now") { updates.checkNow() }
                }
                Toggle("Automatic security updates", isOn: Binding(get: { updates.isEnabled }, set: { updates.setEnabled($0) }))
                    .labelsHidden().toggleStyle(.switch)
            }
        }
        .onAppear { updates.refresh() }
    }
}

struct ExtensionUpdatesSection: View {
    var body: some View {
        PageSection(title: "Extension Updates", footer: ExtensionManager.shared.updateMessage) {
            PageRow(title: "Chrome Web Store extensions") {
                Button("Check for Updates") { Task { await ExtensionManager.shared.checkForUpdates(force: true) } }
                    .disabled(ExtensionManager.shared.checkingUpdates)
            }
        }
    }
}
