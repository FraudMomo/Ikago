import SwiftUI
import IKCEFBridge

struct SecuritySettingsSection: View {
    @Bindable var state: BrowserState
    var body: some View {
        PageSection(title: "Secure Connections") {
            option("Always require HTTPS", subtitle: "Upgrade or block insecure sites", key: \.forceHTTPS, defaultValue: true)
            PageDivider()
            option("Warn before insecure HTTP fallback", subtitle: "When a site has no HTTPS", key: \.warnInsecureHTTP, defaultValue: true)
                .disabled(state.browserPreferences.forceHTTPS == true || BrowserRuntime.engine == .chromium)
            PageDivider()
            option("Allow HTTP on localhost", subtitle: "Keep local development servers reachable", key: \.httpsAllowLocal, defaultValue: true)
                .disabled(state.browserPreferences.forceHTTPS != true)
            PageDivider()
            PageRow(title: "Allow HTTP for these sites", subtitle: "Comma-separated, includes subdomains") {
                TextField("router.lan, dev.example.test", text: Binding(get: { state.browserPreferences.httpsExceptions ?? "" },
                                                                    set: { state.browserPreferences.httpsExceptions = $0 }))
                    .textFieldStyle(.roundedBorder).frame(maxWidth: 280)
            }
            .disabled(state.browserPreferences.forceHTTPS != true)
        }
        DownloadSettingsSection(state: state)
        PageSection(title: "Website Safety", footer: "Lists are checked on this Mac; your browsing isn’t sent anywhere. New phishing sites can slip through.") {
            option("Warn about fraudulent websites", subtitle: "Look-alike addresses and public phishing lists", key: \.fraudulentWebsiteWarning, defaultValue: true)
            if BrowserRuntime.engine == .chromium {
                PageDivider()
                CEFSecurityDetails(state: state)
            }
        }
    }
    private func option(_ title: String, subtitle: String, key: WritableKeyPath<BrowserPreferences, Bool?>, defaultValue: Bool) -> some View {
        PageRow(title: title, subtitle: subtitle) {
            Toggle(title, isOn: Binding(get: { state.browserPreferences[keyPath: key] ?? defaultValue },
                                       set: { state.browserPreferences[keyPath: key] = $0 }))
                .labelsHidden().toggleStyle(.switch)
        }
    }
}

struct TrackingProtectionSection: View {
    let state: BrowserState

    var body: some View {
        PageSection(title: "Tracking Protection", footer: "Reload open pages after changing these.") {
            option("Block common trackers", subtitle: "A curated list of common trackers", key: \.blockTrackers, defaultValue: true)
            if BrowserRuntime.engine == .webkit {
                PageDivider()
                option("Block third-party cookies", subtitle: "Some embedded sign-ins may need this off", key: \.blockThirdPartyCookies, defaultValue: true)
            } else {
                Text("Manage Chromium’s per-Space cookie policy under Website Safety.").font(.system(size: 12)).foregroundStyle(.secondary).padding(12)
            }
            if let issue = BrowserSecurity.shared.blockingIssue {
                PageDivider()
                Text(issue).foregroundStyle(.red).padding(16)
            }
        }
    }
    private func option(_ title: String, subtitle: String, key: WritableKeyPath<BrowserPreferences, Bool?>, defaultValue: Bool) -> some View {
        PageRow(title: title, subtitle: subtitle) {
            Toggle(title, isOn: Binding(get: { state.browserPreferences[keyPath: key] ?? defaultValue },
                                       set: { state.browserPreferences[keyPath: key] = $0 }))
                .labelsHidden().toggleStyle(.switch)
        }
    }
}

/// Which sites may save files without asking.
struct DownloadSettingsSection: View {
    @Bindable var state: BrowserState

    var body: some View {
        PageSection(title: "Downloads") {
            PageRow(title: "Ask before a site downloads files", subtitle: "The first time each site tries") {
                Toggle("Ask before a site downloads files", isOn: Binding(get: { state.browserPreferences.askBeforeDownloads ?? true },
                                                                          set: { state.browserPreferences.askBeforeDownloads = $0 }))
                    .labelsHidden().toggleStyle(.switch)
            }
            ForEach(state.browserPreferences.downloadSites ?? [], id: \.self) { site in
                PageDivider()
                PageRow(title: site) {
                    Button("Remove") { state.browserPreferences.downloadSites?.removeAll { $0 == site } }
                }
            }
        }
    }
}
