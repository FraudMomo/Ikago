import SwiftUI
import IKCEFBridge

struct SecuritySettingsSection: View {
    @Bindable var state: BrowserState
    var body: some View {
        PageSection(title: "Secure Connections", footer: "HTTPS-only mode never falls back to HTTP, except for the addresses you allow above. Otherwise, the browser prefers HTTPS and warns before insecure fallback. Localhost and loopback (127.0.0.1) are never upgraded or warned about, so development servers keep working. Invalid HTTPS certificates stay blocked.") {
            option("Always require HTTPS", subtitle: "Upgrade HTTP addresses; block sites that cannot connect securely", key: \.forceHTTPS, defaultValue: true)
            PageDivider()
            option("Warn before insecure HTTP fallback", subtitle: "Ask before opening an insecure site when HTTPS is unavailable", key: \.warnInsecureHTTP, defaultValue: true)
                .disabled(state.browserPreferences.forceHTTPS == true || BrowserRuntime.engine == .chromium)
            PageDivider()
            option("Allow HTTP on localhost", subtitle: "In HTTPS-only mode, keep local development servers reachable", key: \.httpsAllowLocal, defaultValue: true)
                .disabled(state.browserPreferences.forceHTTPS != true)
            PageDivider()
            PageRow(title: "Allow HTTP for these sites", subtitle: "In HTTPS-only mode. Hosts separated by commas; includes subdomains") {
                TextField("router.lan, dev.example.test", text: Binding(get: { state.browserPreferences.httpsExceptions ?? "" },
                                                                    set: { state.browserPreferences.httpsExceptions = $0 }))
                    .textFieldStyle(.roundedBorder).frame(maxWidth: 280)
            }
            .disabled(state.browserPreferences.forceHTTPS != true)
        }
        DownloadSettingsSection(state: state)
        PageSection(title: "Website Safety", footer: (BrowserRuntime.engine == .webkit ? "Uses WebKit’s fraudulent website warnings. " : "")
                    + "Ikago warns about addresses imitating well-known sites and sites you use, and sites on public phishing lists (phishunt.io and PhishDestroy). The lists download to this Mac and are checked here, so your browsing isn’t sent anywhere. Brand-new phishing sites may not be caught, and this doesn’t scan for malware.") {
            option("Warn about fraudulent websites", subtitle: "Show a warning before opening suspected phishing sites", key: \.fraudulentWebsiteWarning, defaultValue: true)
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
        PageSection(title: "Tracking Protection", footer: "Covers a curated starter list of common third-party trackers. The selected engine handles cookie policy natively. Reload open pages after changing these settings. If a site breaks, turn off the relevant protection and reload.") {
            option("Block common trackers", subtitle: "Enabled by default in every Space", key: \.blockTrackers, defaultValue: true)
            if BrowserRuntime.engine == .webkit {
                PageDivider()
                option("Block third-party cookies", subtitle: "Reduce cross-site tracking; some embedded sign-ins may need this turned off", key: \.blockThirdPartyCookies, defaultValue: true)
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
        PageSection(title: "Downloads", footer: "A site can’t save a file until you allow it. Files keep macOS’s quarantine flag, so Gatekeeper checks anything you open.") {
            PageRow(title: "Ask before a site downloads files", subtitle: "Applies the first time each site tries") {
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
