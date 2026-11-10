import SwiftUI
import IKCEFBridge

struct CEFSecurityDetails: View {
    let state: BrowserState
    private var profile: String { state.isPrivate ? state.privateProfileID : state.activeSpace.profileID }
    @State private var issue: String?
    @State private var snapshot: [AnyHashable: Any] = [:]
    var body: some View {
        PageRow(title: "Third-party cookies", subtitle: "Saved separately for this Chromium Space") {
            Picker("Third-party cookies", selection: Binding(get: { snapshot["cookieControlsMode"] as? Int ?? 1 },
                set: { set("profile.cookie_controls_mode", $0) })) {
                Text("Allow").tag(0)
                Text("Block").tag(1)
                Text("Block in private browsing").tag(2)
            }.labelsHidden().frame(maxWidth: 230).disabled(snapshot["ready"] as? Bool != true)
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
        if let issue, !issue.isEmpty { Text(issue).font(.system(size: 12)).foregroundStyle(.red).padding(12) }
    }
    private func set(_ name: String, _ value: Any) {
        do { try IKCEFSecurity.setPreference(name, value: value, profile: profile) }
        catch { issue = error.localizedDescription }
    }
}
