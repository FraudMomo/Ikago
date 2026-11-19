import SwiftUI

/// The site popover's settings for the current site, in sections: Permissions (camera, microphone and notifications,
/// each with what it is set to and for how long, and a red note while in use), This Site (which engine opens it, tracker
/// blocking, keeping it awake, zoom), then clearing its data.
struct SiteSettingsCard: View {
    let state: BrowserState
    let tab: TabItem
    weak var commands: BrowserCommands?
    @State private var clearing = false
    @State private var cleared = false

    private var host: String { URL(string: tab.url)?.host?.lowercased() ?? "" }

    var body: some View {
        let colors = state.palette
        VStack(alignment: .leading, spacing: 12) {
            // Only what this site has asked for (or what was set for it): every site starts at Ask for everything, so
            // listing the whole catalog would only lengthen the card.
            let listed = listedPermissions
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    SiteCardHeading(title: "Permissions", colors: colors)
                    Spacer()
                    if !listed.isEmpty && !state.isPrivate {
                        Button("Reset") { withAnimation(.ikagoQuick) { resetPermissions() } }
                            .buttonStyle(.plain).font(.system(size: 11, weight: .medium)).foregroundStyle(colors.secondary)
                            .padding(.trailing, 4)
                            .help("Forget this site's permissions: it asks again for each")
                    }
                }
                VStack(spacing: 0) {
                    if listed.isEmpty {
                        Text("This site hasn't asked for any permissions.")
                            .font(.system(size: 12)).foregroundStyle(colors.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 12).frame(minHeight: 38)
                    }
                    ForEach(Array(listed.enumerated()), id: \.element.rawValue) { index, kind in
                        if index > 0 { SiteCardDivider() }
                        permissionRow(kind, inUse: kind == .camera ? tab.cameraActive : kind == .microphone ? tab.microphoneActive : false)
                    }
                }
                .siteCard(colors)
            }
            VStack(alignment: .leading, spacing: 6) {
                SiteCardHeading(title: "This Site", colors: colors)
                VStack(spacing: 0) {
                    if !state.isPrivate, BrowserState.siteForRule(tab.url) != nil {
                        SiteEngineRow(state: state, tab: tab, commands: commands)
                        SiteCardDivider()
                    }
                    SiteProtectionControl(state: state, tab: tab, commands: commands)
                    SiteCardDivider()
                    SiteSettingRow(symbol: "moon.zzz.fill", title: "Keep awake", detail: "Never unloaded to save memory", tint: .indigo) {
                        Toggle("Keep awake", isOn: Binding(get: { state.keepsAwake(host) }, set: { state.setKeepsAwake($0, host: host) }))
                            .labelsHidden().toggleStyle(.switch).controlSize(.mini)
                    }
                    if let page = commands?.activeExtensionTab?.page, commands?.activeExtensionTab?.tab.id == tab.id {
                        SiteCardDivider()
                        ZoomRow(page: page)
                    }
                }
                .siteCard(colors)
            }
            ClearSiteDataButton(colors: colors, clearing: clearing, cleared: cleared, host: host) { Task { await clearSiteData() } }
                .disabled(clearing || cleared || state.isPrivate)
        }
    }

    /// The kinds this site's card lists; the camera and microphone too while in use.
    private var listedPermissions: [PermissionRequest.Kinds] {
        var kinds = state.listedPermissions(host: host, tabID: tab.id)
        if tab.cameraActive, !kinds.contains(.camera) { kinds.insert(.camera, at: 0) }
        if tab.microphoneActive, !kinds.contains(.microphone) { kinds.insert(.microphone, at: kinds.contains(.camera) ? 1 : 0) }
        return kinds
    }

    private func resetPermissions() {
        state.visitGrants[tab.id] = nil
        state.resetSitePermissions(host: host)
    }

    /// One permission: what it is set to, for how long, and a menu to change it (Allow Once lives only in the prompt).
    private func permissionRow(_ kind: PermissionRequest.Kinds, inUse: Bool) -> some View {
        let saved = state.sitePermission(kind, host: host)
        let current = state.permission(kind, host: host, tabID: tab.id)
        let expiry = state.sitePermissionExpiry(kind, host: host)
        let visit = current == .allow && saved != .allow
        return SiteSettingRow(symbol: PermissionPrompt.symbol(kind), title: PermissionPrompt.title(kind),
                              detail: inUse ? "In use now" : status(current, expiry: expiry, visit: visit),
                              tint: PermissionPrompt.tint(kind), detailTint: inUse ? .red : .secondary) {
            CompactMenu(value: visit ? "Once" : expiry != nil ? "1 Day" : current.title, choices: [
                MenuChoice(title: "Ask", isOn: current == .ask) { set(.ask, kind) },
                MenuChoice(title: PermissionGrant.day.title, isOn: expiry != nil, separatorBefore: true) { set(.allow, kind, for: .day) },
                MenuChoice(title: PermissionGrant.always.title, isOn: saved == .allow && expiry == nil) { set(.allow, kind) },
                MenuChoice(title: "Block", isOn: current == .block, separatorBefore: true) { set(.block, kind) },
            ])
            .disabled(state.isPrivate)
        }
    }

    private func set(_ value: SitePermission, _ kind: PermissionRequest.Kinds, for grant: PermissionGrant = .always) {
        withAnimation(.ikagoQuick) {
            // A choice here replaces this visit's Allow Once for the kind.
            state.visitGrants[tab.id]?.kinds.remove(kind)
            state.setSitePermission(value, kind, host: host,
                                    until: grant == .day ? Date().addingTimeInterval(PermissionGrant.dayLength) : nil)
        }
    }

    private func status(_ value: SitePermission, expiry: Date?, visit: Bool) -> String {
        if visit { return "Allowed while you stay on this site" }
        if let expiry { return "Allowed until \(expiry.formatted(Calendar.current.isDateInToday(expiry) ? .dateTime.hour().minute() : .dateTime.weekday(.abbreviated).hour().minute()))" }
        switch value {
        case .ask: return "Asks each time"
        case .allow: return "Always allowed"
        case .block: return "Blocked"
        }
    }

    private func clearSiteData() async {
        guard let url = URL(string: tab.url) else { return }
        clearing = true
        try? await EngineCookieSync.clearSite(profile: state.activeSpace.profileID, url: url)
        clearing = false
        cleared = true
        commands?.activeExtensionTab?.page?.reload()
    }
}

/// One setting: its symbol in a tinted circle, a title (and a short detail), and its control at the end.
struct SiteSettingRow<Control: View>: View {
    let symbol: String
    let title: String
    var detail: String? = nil
    let tint: Color
    var detailTint: Color = .secondary
    @ViewBuilder let control: Control

    var body: some View {
        HStack(spacing: 10) {
            SettingTile(symbol: symbol, tint: tint)
            VStack(alignment: .leading, spacing: 1) {
                Text(title).font(.system(size: 13)).lineLimit(1)
                if let detail {
                    Text(detail).font(.system(size: 11)).foregroundStyle(detailTint).lineLimit(1).transition(.opacity)
                }
            }
            .layoutPriority(1)
            Spacer(minLength: 8)
            control
        }
        .padding(.horizontal, 10).frame(minHeight: 40)
        .animation(.ikagoQuick, value: detail)
    }
}

/// A setting's symbol in a soft circle of its color.
struct SettingTile: View {
    let symbol: String
    let tint: Color
    var body: some View {
        Image(systemName: symbol).font(.system(size: 11, weight: .semibold)).foregroundStyle(.white)
            .frame(width: 26, height: 26)
            .background(Circle().fill(tint.gradient))
    }
}

/// Page zoom in 10 % steps: a stepper pill (smaller, the level, larger), and Reset while the page isn't at 100 %.
private struct ZoomRow: View {
    let page: WebTab
    @State private var percent = 100

    var body: some View {
        SiteSettingRow(symbol: "plus.magnifyingglass", title: "Zoom", tint: .teal) {
            HStack(spacing: 8) {
                if percent != 100 {
                    Button("Reset") { set(100) }
                        .font(.system(size: 12, weight: .medium)).foregroundStyle(Color.accentColor)
                        .buttonStyle(SiteCardPressStyle())
                        .help("Actual Size (⌘0)")
                        .transition(.opacity.combined(with: .scale(scale: 0.8, anchor: .trailing)))
                }
                HStack(spacing: 0) {
                    SiteIconButton(symbol: "minus", help: "Zoom Out (⌘−)") { set(PageZoom.stepped(percent, by: -1)) }
                        .disabled(percent <= PageZoom.range.lowerBound)
                    Text("\(percent)%").font(.system(size: 12, weight: .medium).monospacedDigit())
                        .frame(width: 42).contentTransition(.numericText(value: Double(percent)))
                    SiteIconButton(symbol: "plus", help: "Zoom In (⌘+)") { set(PageZoom.stepped(percent, by: 1)) }
                        .disabled(percent >= PageZoom.range.upperBound)
                }
                .padding(.horizontal, 1).frame(height: 24)
                .background(SiteControlPill(shape: Capsule()))
            }
        }
        .onAppear { percent = page.zoomPercent }
    }

    private func set(_ value: Int) {
        withAnimation(.spring(duration: 0.25, bounce: 0.2)) { percent = value }
        page.zoomPercent = value
    }
}

/// Clear Site Data as a row of its own: red, with a hover fill, and a checkmark once done.
private struct ClearSiteDataButton: View {
    let colors: Palette
    let clearing: Bool
    let cleared: Bool
    let host: String
    let action: () -> Void
    @State private var hovering = false
    @Environment(\.isEnabled) private var enabled

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: cleared ? "checkmark.circle.fill" : "trash")
                    .font(.system(size: 12, weight: .semibold)).contentTransition(.symbolEffect(.replace))
                Text(clearing ? "Clearing…" : cleared ? "Site data cleared" : "Clear Site Data")
                    .font(.system(size: 13, weight: .medium)).contentTransition(.opacity)
                Spacer(minLength: 0)
                if clearing { ProgressView().controlSize(.mini).transition(.opacity) }
            }
            .foregroundStyle(cleared ? Color.green : Color.red)
            .padding(.horizontal, 12).frame(height: 36)
            .background(Color.red.opacity(hovering && !cleared ? 0.08 : 0))
            .contentShape(Rectangle())
        }
        .buttonStyle(SiteCardPressStyle())
        .onHover { hovering = $0 && enabled }
        .siteCard(colors)
        .opacity(enabled || cleared ? 1 : 0.5)
        .help("Signs you out of \(host) and removes what it stored")
        .animation(.ikagoQuick, value: hovering)
        .animation(.ikago, value: cleared)
        .animation(.ikago, value: clearing)
    }
}
