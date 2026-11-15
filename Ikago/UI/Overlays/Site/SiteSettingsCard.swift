import SwiftUI

/// The site popover's settings for the current site, in one card: camera and microphone (ask, allow or block; a red
/// dot while in use), which engine opens it, tracker blocking, keeping it awake, zoom, and clearing its data.
struct SiteSettingsCard: View {
    let state: BrowserState
    let tab: TabItem
    weak var commands: BrowserCommands?
    @State private var clearing = false
    @State private var cleared = false

    private var host: String { URL(string: tab.url)?.host?.lowercased() ?? "" }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            VStack(spacing: 0) {
                permissionRow(.camera, title: "Camera", symbol: "video.fill", tint: .blue, inUse: tab.cameraActive)
                SiteCardDivider()
                permissionRow(.microphone, title: "Microphone", symbol: "mic.fill", tint: .orange, inUse: tab.microphoneActive)
                if !state.isPrivate, BrowserState.siteForRule(tab.url) != nil {
                    SiteCardDivider()
                    SiteEngineRow(state: state, tab: tab, commands: commands)
                }
                SiteCardDivider()
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
            .siteCard(state.palette)
            ClearSiteDataButton(colors: state.palette, clearing: clearing, cleared: cleared, host: host) { Task { await clearSiteData() } }
                .disabled(clearing || cleared || state.isPrivate)
        }
    }

    private func permissionRow(_ kind: PermissionRequest.Kinds, title: String, symbol: String, tint: Color, inUse: Bool) -> some View {
        SiteSettingRow(symbol: symbol, title: title, detail: inUse ? "In use now" : nil, tint: tint, detailTint: .red) {
            let current = state.sitePermission(kind, host: host)
            CompactMenu(value: current.title, choices: SitePermission.allCases.map { choice in
                MenuChoice(title: choice.title, isOn: choice == current) {
                    withAnimation(.ikagoQuick) { state.setSitePermission(choice, kind, host: host) }
                }
            })
            .disabled(state.isPrivate)
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
