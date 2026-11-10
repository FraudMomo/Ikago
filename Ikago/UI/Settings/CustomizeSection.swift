import SwiftUI

/// Settings ▸ Customize: live mockups of the top bar and sidebar. Drag items to reorder or
/// move them, hover and click − to remove, drag (or click) from Available to add.
struct CustomizeSection: View {
    let state: BrowserState
    @State private var editingTopBar: Bool

    init(state: BrowserState) {
        self.state = state
        _editingTopBar = State(initialValue: state.tabLayout == .horizontal)
    }

    var body: some View {
        let colors = state.palette
        PageSection(title: "Customize",
                    footer: "Drag to reorder or move between places, inside the island or on either side of it. Hover an item and click − to remove it; drag or click an item in Available to add it.") {
            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    Picker("", selection: $editingTopBar.animation(.ikago)) {
                        Text("Top Bar").tag(true)
                        Text("Sidebar").tag(false)
                    }
                    .pickerStyle(.segmented).labelsHidden().fixedSize()
                    Spacer()
                    Button("Reset to Default") { withAnimation(.ikago) { state.chromeLayout = ChromeLayout() } }
                        .controlSize(.small)
                        .disabled(state.chromeLayout == ChromeLayout())
                }
                ScrollView(.horizontal) {
                    Group {
                        if editingTopBar { TopBarMockup(state: state, colors: colors) } else { SidebarMockup(state: state, colors: colors) }
                    }
                    .frame(minWidth: 420)  // narrower than this the mockup scrolls instead of squashing
                }
                .scrollIndicators(.never)
                .padding(14)
                .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(colors.tint))
                .environment(\.colorScheme, colors.isDark ? .dark : .light)
                AvailableTray(state: state, colors: colors, topBar: editingTopBar)
            }
            .padding(16)
        }
        .animation(.ikago, value: state.chromeLayout)
    }
}

// MARK: - Mockups

private struct TopBarMockup: View {
    let state: BrowserState
    let colors: Palette

    var body: some View {
        VStack(spacing: 10) {
            if state.topTabStyle == .separate {
                HStack(spacing: 6) {
                    TrafficLights()
                    ZoneView(zone: .topBarOuterLeading, state: state, colors: colors)
                    ZoneView(zone: .topBarLeading, state: state, colors: colors)
                    RoundedRectangle(cornerRadius: 5).fill(colors.hover.opacity(2)).frame(minWidth: 100, maxWidth: .infinity).frame(height: 24)
                    ZoneView(zone: .topBarTrailing, state: state, colors: colors)
                    ZoneView(zone: .topBarOuterTrailing, state: state, colors: colors)
                }
                HStack(spacing: 3) {
                    ForEach(0..<3, id: \.self) { i in RoundedRectangle(cornerRadius: 4).fill(i == 1 ? colors.selected : colors.hover).frame(height: 18) }
                }
            } else {
            HStack(spacing: 6) {
                TrafficLights()
                ZoneView(zone: .topBarOuterLeading, state: state, colors: colors)
                Spacer(minLength: 4)
                HStack(spacing: 4) {
                    ZoneView(zone: .topBarLeading, state: state, colors: colors)
                    FakeTab(colors: colors, active: false, width: 64)
                    FakeTab(colors: colors, active: true, width: 110)
                    FakeTab(colors: colors, active: false, width: 64)
                    ZoneView(zone: .topBarTrailing, state: state, colors: colors)
                }
                .padding(4)
                .background(Capsule().fill(colors.panel.opacity(0.8)))
                Spacer(minLength: 4)
                ZoneView(zone: .topBarOuterTrailing, state: state, colors: colors)
            }
            }
            RoundedRectangle(cornerRadius: 8, style: .continuous).fill(colors.pageBackground).frame(height: 90)
        }
    }
}

private struct SidebarMockup: View {
    let state: BrowserState
    let colors: Palette

    var body: some View {
        HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 4) {
                    TrafficLights()
                    Spacer(minLength: 6)
                    ZoneView(zone: .sidebarTop, state: state, colors: colors)
                }
                ToggleRow(title: "Address", shown: state.chromeLayout.sidebarShowsAddress, colors: colors, filled: true) {
                    state.chromeLayout.sidebarShowsAddress.toggle()
                }
                ToggleRow(title: "New Tab", shown: state.chromeLayout.sidebarShowsNewTab, colors: colors, filled: false) {
                    state.chromeLayout.sidebarShowsNewTab.toggle()
                }
                ForEach(0..<3, id: \.self) { i in
                    RoundedRectangle(cornerRadius: 6).fill(i == 0 ? colors.selected : colors.hover).frame(height: 18)
                }
                Spacer(minLength: 10)
                HStack {
                    Spacer(minLength: 0)
                    ZoneView(zone: .sidebarBottom, state: state, colors: colors)
                    Spacer(minLength: 0)
                }
            }
            .padding(8)
            .frame(minWidth: 190, maxWidth: 250)
            .frame(height: 250)
            .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(colors.panel.opacity(0.8)))
            RoundedRectangle(cornerRadius: 8, style: .continuous).fill(colors.pageBackground).frame(height: 250)
        }
    }
}

/// A spot that holds items: drop onto an item to go before it, onto the spot to go last.
struct ZoneView: View {
    let zone: ChromeZone
    let state: BrowserState
    let colors: Palette
    @State private var targeted = false

    var body: some View {
        let items = state.chromeLayout[zone]
        HStack(spacing: 2) {
            ForEach(items) { item in
                ItemChip(item: item, colors: colors, spacesAsDots: zone == .sidebarBottom) {
                    withAnimation(.ikago) { state.chromeLayout.remove(item, from: zone) }
                }
                .dropDestination(for: String.self) { ids, _ in return place(ids, before: item) }
            }
            if items.isEmpty {
                Text("Drop here").font(.system(size: 10)).foregroundStyle(colors.tertiary).padding(.horizontal, 8)
            }
        }
        .frame(minWidth: 40, minHeight: 30)
        .padding(.horizontal, 2)
        .background(RoundedRectangle(cornerRadius: 8, style: .continuous)
            .strokeBorder(targeted ? Color.accentColor : colors.separator, style: StrokeStyle(lineWidth: 1, dash: [3, 3]))
            .opacity(targeted || items.isEmpty ? 1 : 0.6))
        .dropDestination(for: String.self) { ids, _ in place(ids, before: nil) } isTargeted: { targeted = $0 }
    }

    private func place(_ ids: [String], before target: ChromeItem?) -> Bool {
        guard let id = ids.first, let item = ChromeItem(rawValue: id), zone.allowed.contains(item) else { return false }
        withAnimation(.ikago) { state.chromeLayout.place(item, in: zone, before: target) }
        return true
    }
}

/// One placed item: drag to move; hover shows − to remove.
private struct ItemChip: View {
    let item: ChromeItem
    let colors: Palette
    var spacesAsDots = false
    let onRemove: () -> Void
    @State private var hovering = false

    var body: some View {
        Group {
            if item == .spaces && spacesAsDots {
                HStack(spacing: 3) {
                    ForEach(0..<3, id: \.self) { i in Circle().fill(i == 0 ? colors.text : colors.tertiary).frame(width: 6, height: 6) }
                }
                .frame(width: 40, height: 26)
            } else {
                Image(systemName: item.symbol)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(colors.secondary)
                    .frame(width: 26, height: 26)
            }
        }
        .background(RoundedRectangle(cornerRadius: 7).fill(hovering ? colors.hover.opacity(2) : .clear))
        .overlay(alignment: .topTrailing) {
            if hovering {
                Button(action: onRemove) {
                    Image(systemName: "minus.circle.fill").font(.system(size: 11)).foregroundStyle(.white, .red)
                }
                .buttonStyle(.plain)
                .offset(x: 4, y: -4)
                .transition(.scale.combined(with: .opacity))
            }
        }
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
        .animation(.ikagoQuick, value: hovering)
        .draggable(item.rawValue) { ChipPreview(item: item) }
        .help(item.name)
    }
}

/// Items not placed in the bar being edited. Drop an item here to remove it.
private struct AvailableTray: View {
    let state: BrowserState
    let colors: Palette
    let topBar: Bool
    @State private var targeted = false

    var body: some View {
        let items = state.chromeLayout.available(topBar: topBar)
        ScrollView(.horizontal) { HStack(spacing: 8) {
            Text("Available").font(.system(size: 12, weight: .semibold)).foregroundStyle(.secondary)
            if items.isEmpty {
                Text("Everything is in use. Drag an item here to remove it.").font(.system(size: 12)).foregroundStyle(.tertiary)
            }
            ForEach(items) { item in
                Button { add(item) } label: {
                    Label(item.name, systemImage: item.symbol)
                        .font(.system(size: 12))
                        .padding(.horizontal, 10).padding(.vertical, 5)
                        .background(Capsule().fill(Color.primary.opacity(0.06)))
                }
                .buttonStyle(.plain)
                .draggable(item.rawValue) { ChipPreview(item: item) }
                .help("Click or drag to add")
            }
            Spacer(minLength: 0)
        } }
        .scrollIndicators(.never)
        .padding(8)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous)
            .strokeBorder(targeted ? Color.red.opacity(0.6) : .clear, style: StrokeStyle(lineWidth: 1, dash: [3, 3])))
        .dropDestination(for: String.self) { ids, _ in
            guard let id = ids.first, let item = ChromeItem(rawValue: id) else { return false }
            withAnimation(.ikago) { state.chromeLayout.remove(item, fromTopBar: topBar) }
            return true
        } isTargeted: { targeted = $0 }
    }

    private func add(_ item: ChromeItem) {
        withAnimation(.ikago) { state.chromeLayout.place(item, in: topBar ? .topBarTrailing : .sidebarTop) }
    }
}

// MARK: - Mockup pieces

private struct ChipPreview: View {
    let item: ChromeItem
    var body: some View {
        Label(item.name, systemImage: item.symbol).font(.system(size: 12)).padding(6)
            .background(RoundedRectangle(cornerRadius: 6).fill(Color(white: 0.5).opacity(0.3)))
    }
}

private struct TrafficLights: View {
    var body: some View {
        HStack(spacing: 5) {
            ForEach([Color.red, .yellow, .green], id: \.self) { Circle().fill($0.opacity(0.85)).frame(width: 9, height: 9) }
        }
    }
}

private struct FakeTab: View {
    let colors: Palette
    let active: Bool
    let width: CGFloat
    var body: some View {
        Capsule().fill(active ? colors.selected : colors.hover).frame(width: width, height: 22)
    }
}

/// A sidebar row that can be shown or hidden by clicking it.
private struct ToggleRow: View {
    let title: String
    let shown: Bool
    let colors: Palette
    let filled: Bool
    let toggle: () -> Void

    var body: some View {
        Button { withAnimation(.ikago) { toggle() } } label: {
            HStack {
                Text(title).font(.system(size: 11)).foregroundStyle(colors.secondary)
                Spacer()
                Image(systemName: shown ? "eye" : "eye.slash").font(.system(size: 10)).foregroundStyle(colors.tertiary)
            }
            .padding(.horizontal, 8)
            .frame(height: 24)
            .background(RoundedRectangle(cornerRadius: 6).fill(filled ? colors.hover.opacity(1.5) : .clear))
            .opacity(shown ? 1 : 0.4)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(shown ? "Click to hide" : "Click to show")
    }
}
