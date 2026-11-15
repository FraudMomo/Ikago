import IKCEFBridge
import SwiftUI

// MARK: - Security dashboard

/// What's protecting you right now, at a glance. Every tile reports an actual setting.
struct SecurityDashboard: View {
    let state: BrowserState

    private struct Tile: Identifiable {
        let symbol: String, title: String, status: String, tone: Color
        var id: String { title }
    }

    private var tiles: [Tile] {
        let preferences = state.browserPreferences
        let chromium = BrowserRuntime.engine == .chromium
        return [
            Tile(symbol: "lock.fill", title: "Connections", status: preferences.forceHTTPS == true ? "HTTPS required" : "HTTPS preferred",
                 tone: preferences.forceHTTPS == true ? .green : .blue),
            Tile(symbol: "checkmark.seal.fill", title: "Certificates", status: "Always enforced", tone: .green),
            Tile(symbol: "eye.slash.fill", title: "Trackers", status: preferences.blockTrackers ?? true ? "Common ones blocked" : "Not blocked",
                 tone: preferences.blockTrackers ?? true ? .green : .orange),
            Tile(symbol: "shippingbox.fill", title: "Website sandbox", status: chromium ? "Chromium sandbox on" : "Apple’s sandbox on", tone: .green),
            Tile(symbol: "exclamationmark.shield.fill", title: "Fraud warnings",
                 status: preferences.fraudulentWebsiteWarning ?? true ? "Look-alikes and phishing lists" : "Off",
                 tone: preferences.fraudulentWebsiteWarning ?? true ? .green : .orange),
            Tile(symbol: "externaldrive.fill.badge.checkmark", title: "Stored data",
                 status: ProtectedStorage.isProtected ? "Locked to Ikago" : "Not locked", tone: ProtectedStorage.isProtected ? .green : .orange),
            Tile(symbol: "camera.fill", title: "Camera and mic", status: "Ask every site", tone: .green),
            Tile(symbol: "arrow.down.circle.fill", title: "Downloads", status: preferences.askBeforeDownloads ?? true ? "Ask each site" : "Not asked",
                 tone: preferences.askBeforeDownloads ?? true ? .green : .orange),
        ]
    }

    var body: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 200), spacing: 10)], spacing: 10) {
            ForEach(tiles) { tile in
                HStack(spacing: 10) {
                    IconTile(symbol: tile.symbol, tint: tile.tone, size: 24)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(tile.title).font(.system(size: 13)).lineLimit(1)
                        Text(tile.status).font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(1)
                    }
                    Spacer(minLength: 0)
                }
                .padding(.vertical, 4)
                .accessibilityElement(children: .combine)
            }
        }
        .padding(.horizontal, 12).padding(.vertical, 8)
    }
}

// MARK: - Chromium security details

struct CEFSecurityDetails: View {
    let state: BrowserState
    private var profile: String { state.isPrivate ? state.privateProfileID : state.activeSpace.profileID }
    @State private var issue: String?
    @State private var snapshot: [AnyHashable: Any] = [:]
    var body: some View {
        PageRow(title: "Third-party cookies", subtitle: "Saved separately for this Chromium Space") {
            SettingsMenu(selection: Binding(get: { snapshot["cookieControlsMode"] as? Int ?? 1 },
                set: { set("profile.cookie_controls_mode", $0) }), options: [(0, "Allow"), (1, "Block"), (2, "Block in private browsing")]).frame(maxWidth: 230).disabled(snapshot["ready"] as? Bool != true)
        }
        .task(id: "\(profile):\(CEFNativePreferences.shared.revision)") {
            do { try CEFSessions.prepare(profile) }
            catch { issue = error.localizedDescription; return }
            var latest = IKCEFSecurity.snapshot(forProfile: profile)
            for _ in 0..<20 where latest["ready"] as? Bool != true {
                try? await Task.sleep(for: .milliseconds(100))
                guard !Task.isCancelled else { return }
                latest = IKCEFSecurity.snapshot(forProfile: profile)
            }
            snapshot = latest
            issue = (snapshot["issues"] as? [String])?.joined(separator: "\n")
        }
        if let issue, !issue.isEmpty { Text(issue).font(.system(size: 12)).foregroundStyle(.red).padding(.vertical, 12) }
    }
    private func set(_ name: String, _ value: Any) {
        do { try IKCEFSecurity.setPreference(name, value: value, profile: profile) }
        catch { issue = error.localizedDescription }
    }
}
