import AppKit
import SwiftUI

/// Tabs open in Safari on the person's other devices and their Safari Tab Groups (`SafariSyncedTabs`), from the
/// Devices control. A row opens its page in a new tab; a group can open as an Ikago tab group.
struct DevicesDropdown: View {
    let state: BrowserState
    let colors: Palette
    let close: () -> Void
    @State private var expanded: Set<String> = []
    @State private var hoveredGroup: String?
    private var model: SafariSyncedTabsModel { .shared }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Text("Other Devices").font(.system(size: 14, weight: .semibold))
                Spacer()
                ChromeButton(symbol: "xmark", help: "Close", colors: colors, size: 26, glass: false) { close() }
            }
            .padding(.horizontal, 16).padding(.vertical, 10)
            separator
            content
            separator
            footer
        }
        .foregroundStyle(colors.text)
        .tint(colors.accent)
        .surface(.rect(cornerRadius: Radius.sheet), colors)
        .clipShape(.rect(cornerRadius: Radius.sheet))
        .shadow(color: .black.opacity(colors.isDark ? 0.22 : 0.1), radius: 18, y: 6)
        .task {
            await model.refresh(force: true)
            // macOS syncs Safari's copies in the background; pick up each write while the list is open.
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(3))
                await model.refresh()
            }
        }
    }

    @ViewBuilder private var content: some View {
        let tabs = model.tabs
        let devices = tabs.devices.filter { !$0.tabs.isEmpty }
        if model.denied {
            message(symbol: "lock", title: "Allow access to Safari’s tabs",
                    detail: "macOS keeps Safari’s synced tabs private. Allow Ikago in Privacy & Security, then try again.") {
                HStack(spacing: 8) {
                    Button("Open Privacy Settings") {
                        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles") { NSWorkspace.shared.open(url) }
                    }
                    Button("Try Again") { Task { await model.refresh(force: true) } }
                }.buttonStyle(SettingsButtonStyle())
            }
        } else if model.loaded && devices.isEmpty && tabs.groups.isEmpty {
            message(symbol: "iphone", title: "No tabs from other devices",
                    detail: "Turn on Safari in iCloud on your iPhone, and open Safari on this Mac now and then so it syncs.") { EmptyView() }
        } else {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 2) {
                    ForEach(devices) { device in
                        sectionHeader(symbol: device.symbol, title: device.name, day: device.updated)
                        ForEach(device.tabs) { tab in row(tab) }
                    }
                    let quiet = tabs.devices.filter(\.tabs.isEmpty).map(\.name)
                    if !quiet.isEmpty {
                        Text("No open tabs on \(ListFormatter.localizedString(byJoining: quiet))")
                            .font(.system(size: 11)).foregroundStyle(colors.tertiary)
                            .padding(.horizontal, 10).padding(.vertical, 6)
                    }
                    if !tabs.groups.isEmpty {
                        sectionHeader(symbol: "square.on.square", title: "Tab Groups", day: nil)
                        ForEach(tabs.groups) { group in groupRow(group) }
                    }
                }
                .padding(6)
            }
            .scrollIndicators(.never)
        }
    }

    private var footer: some View {
        HStack(spacing: 6) {
            Image(systemName: "safari").font(.system(size: 11))
            if let updated = model.tabs.updated {
                Text("From Safari · updated \(updated.formatted(.relative(presentation: .named)))")
            } else {
                Text("From Safari")
            }
            Spacer()
        }
        .font(.system(size: 11)).foregroundStyle(colors.tertiary)
        .padding(.horizontal, 16).frame(height: 34)
        .help("Safari on this Mac keeps these in sync through iCloud. They update when Safari syncs.")
    }

    /// Safari keeps only the day a device last synced, so it reads as a day, never a time.
    private func sectionHeader(symbol: String, title: String, day: Date?) -> some View {
        HStack(spacing: 6) {
            Image(systemName: symbol).font(.system(size: 11, weight: .medium)).frame(width: 16)
            Text(title).font(.system(size: 11, weight: .semibold)).lineLimit(1)
            Spacer()
            if let day, day > .distantPast {
                Text(Self.dayLabel(day)).font(.system(size: 10)).foregroundStyle(colors.tertiary)
            }
        }
        .foregroundStyle(colors.secondary)
        .padding(.horizontal, 10).padding(.top, 10).padding(.bottom, 4)
    }

    private static func dayLabel(_ day: Date) -> String {
        let calendar = Calendar.current
        if calendar.isDateInToday(day) { return "Today" }
        if calendar.isDateInYesterday(day) { return "Yesterday" }
        return day.formatted(.dateTime.month(.abbreviated).day())
    }

    private func row(_ tab: SafariSyncedTabs.Tab, indent: CGFloat = 0) -> some View {
        HoverRow(colors: colors) {
            state.newTab(url: tab.url)
            close()
        } label: {
            HStack(spacing: 10) {
                FaviconView(pageURL: tab.url, size: 16)
                VStack(alignment: .leading, spacing: 1) {
                    Text(tab.title).font(.system(size: 12.5, weight: .medium)).lineLimit(1)
                    Text(URL(string: tab.url)?.host() ?? tab.url).font(.system(size: 10.5)).foregroundStyle(colors.secondary).lineLimit(1)
                }
                Spacer(minLength: 0)
            }
            .padding(.leading, indent)
        }
        .help(tab.url)
    }

    private func groupRow(_ group: SafariSyncedTabs.Group) -> some View {
        let open = expanded.contains(group.id)
        return VStack(alignment: .leading, spacing: 2) {
            HoverRow(colors: colors) {
                withAnimation(.ikagoQuick) { if open { expanded.remove(group.id) } else { expanded.insert(group.id) } }
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "chevron.right").font(.system(size: 9, weight: .semibold)).foregroundStyle(colors.tertiary)
                        .rotationEffect(.degrees(open ? 90 : 0)).frame(width: 16)
                    Text(group.name).font(.system(size: 12.5, weight: .medium)).lineLimit(1)
                    if let profile = group.profile {
                        Text(profile).font(.system(size: 10, weight: .medium)).foregroundStyle(colors.secondary)
                            .padding(.horizontal, 6).padding(.vertical, 2).background(Capsule().fill(colors.hover))
                    }
                    Spacer(minLength: 4)
                    if hoveredGroup == group.id {
                        Button("Open All") { openAll(group) }.buttonStyle(.plain)
                            .font(.system(size: 11, weight: .medium)).foregroundStyle(colors.accent)
                    } else {
                        Text("\(group.tabs.count)").font(.system(size: 11)).monospacedDigit().foregroundStyle(colors.tertiary)
                    }
                }
            }
            .onHover { hoveredGroup = $0 ? group.id : (hoveredGroup == group.id ? nil : hoveredGroup) }
            if open {
                ForEach(group.tabs) { tab in row(tab, indent: 16) }
            }
        }
    }

    /// The group's tabs as an Ikago tab group in the current Space; tabs already there aren't added twice.
    private func openAll(_ group: SafariSyncedTabs.Group) {
        let tabs = group.tabs.map { ImportTab(url: $0.url, title: $0.title, group: group.name, groupID: group.id) }
        _ = state.mergeImportedTabs(tabs, into: state.activeSpaceID)
        close()
    }

    private func message<Actions: View>(symbol: String, title: String, detail: String, @ViewBuilder actions: () -> Actions) -> some View {
        VStack(spacing: 8) {
            Image(systemName: symbol).font(.system(size: 26, weight: .light)).padding(.bottom, 4)
            Text(title).font(.system(size: 13, weight: .medium)).foregroundStyle(colors.text)
            Text(detail).font(.system(size: 12)).multilineTextAlignment(.center).fixedSize(horizontal: false, vertical: true)
            actions().padding(.top, 6)
        }
        .foregroundStyle(colors.secondary).padding(24).frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var separator: some View { Rectangle().fill(colors.separator).frame(height: 0.5).padding(.horizontal, 12) }
}

/// A full-width row that highlights under the pointer.
private struct HoverRow<Label: View>: View {
    let colors: Palette
    let action: () -> Void
    @ViewBuilder let label: Label
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            label.padding(.horizontal, 10).padding(.vertical, 7).frame(maxWidth: .infinity, alignment: .leading)
                .background(RoundedRectangle(cornerRadius: Radius.control, style: .continuous).fill(hovering ? colors.hover : .clear))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
    }
}

/// Hangs from the Devices control, like the Downloads list.
struct DevicesDropdownOverlay: View {
    let state: BrowserState
    let chrome: ChromeModel
    let anchor: CGRect?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        GeometryReader { geometry in
            let bounds = anchor ?? CGRect(x: 40, y: 42, width: 24, height: 24)
            let desired = Self.desiredHeight(SafariSyncedTabsModel.shared.tabs)
            let width = min(380, max(0, geometry.size.width - 24))
            let below = max(0, geometry.size.height - bounds.maxY - 20)
            let above = max(0, bounds.minY - 20)
            let height = min(min(560, desired), max(160, max(below, above)))
            let x = max(12, min(bounds.minX, geometry.size.width - width - 12))
            let y = below >= height ? bounds.maxY + 8 : max(12, bounds.minY - height - 8)
            ZStack(alignment: .topLeading) {
                Color.clear.contentShape(Rectangle()).onTapGesture { dismiss() }
                DevicesDropdown(state: state, colors: state.palette, close: dismiss)
                    .frame(width: width, height: height).offset(x: x, y: y)
                    .transition(.opacity.combined(with: .scale(scale: 0.97, anchor: .top)))
            }
        }
    }

    private func dismiss() { withAnimation(reduceMotion ? nil : .ikagoQuick) { chrome.showDevices = false } }

    /// Roughly the list's own height, so a short list doesn't leave an empty card; long lists scroll.
    private static func desiredHeight(_ tabs: SafariSyncedTabs) -> CGFloat {
        let devices = tabs.devices.filter { !$0.tabs.isEmpty }
        var height: CGFloat = 50 + 34 + 12
        height += CGFloat(devices.count) * 30 + CGFloat(devices.reduce(0) { $0 + $1.tabs.count }) * 45
        if devices.count < tabs.devices.count { height += 26 }
        if !tabs.groups.isEmpty { height += 32 + CGFloat(tabs.groups.count) * 34 + 24 }
        return devices.isEmpty && tabs.groups.isEmpty ? 260 : height
    }
}

/// The Devices control (Settings ▸ Customize, placed when Other Devices is turned on).
struct DevicesToolbarButton: View {
    let colors: Palette
    weak var commands: BrowserCommands?
    var size: CGFloat = 28

    var body: some View {
        Button { commands?.toggleDevices() } label: {
            Image(systemName: "iphone").font(.system(size: 14, weight: .medium))
                .frame(width: size, height: size)
                .background(Circle().fill(commands?.devicesPresented == true ? colors.selected : .clear))
                .contentShape(Circle())
                .glassControl(Circle(), colors)
        }
        .buttonStyle(.plain).foregroundStyle(colors.glass ? colors.text.opacity(0.85) : colors.secondary)
        .anchorPreference(key: DownloadsAnchorKey.self, value: .bounds) { DownloadAnchors(devices: $0) }
        .help("Tabs from Other Devices")
        .accessibilityLabel("Tabs from Other Devices")
    }
}
