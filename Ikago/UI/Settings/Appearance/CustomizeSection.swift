import SwiftUI

/// Settings ▸ Customize: a live mockup of the current layout. The sidebar's top row and bottom bar each have a left,
/// centre and right place; Top Tabs has the toolbar's left and right instead. Below them sit the icons-only
/// sidebar's foot and the address field's own buttons. Drag items into any place, reorder within one, hover and click −
/// to remove, drag (or click) from Available to add.
struct CustomizeSection: View {
    let state: BrowserState

    var body: some View {
        let colors = state.palette
        let tabs = state.usesTabsLayout
        PageSection(title: "Customize",
                    footer: "Drag items to the left, centre or right of a row. Hover and click − to remove; click an item in Available to add it.") {
            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    Spacer()
                    Button("Reset to Default") { withAnimation(.ikago) { state.chromeLayout = ChromeLayout() } }
                        .controlSize(.small)
                        .disabled(state.chromeLayout == ChromeLayout())
                }
                ScrollView(.horizontal) {
                    Group {
                        if tabs { TabsMockup(state: state, colors: colors) } else { SidebarMockup(state: state, colors: colors) }
                    }
                    // As wide as the section; narrower than 420 the mockup scrolls instead of squashing.
                    .containerRelativeFrame(.horizontal) { width, _ in max(420, width) }
                }
                .scrollIndicators(.never)
                .padding(14)
                .background(RoundedRectangle(cornerRadius: Radius.card, style: .continuous).fill(colors.tint))
                .environment(\.colorScheme, colors.isDark ? .dark : .light)
                CustomizeExtras(state: state, colors: colors)
                AvailableTray(state: state, colors: colors,
                              zones: tabs ? ChromeZone.toolbarRow : ChromeZone.topRow + ChromeZone.bottomRow,
                              home: tabs ? .toolbarTrailing : .sidebarTop)
            }
            .padding(.vertical, 16)
        }
        .animation(.ikago, value: state.chromeLayout)
    }
}

// MARK: - Mockups

private struct SidebarMockup: View {
    let state: BrowserState
    let colors: Palette

    var body: some View {
        HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 4) {
                    TrafficLights()
                    row(ChromeZone.topRow)
                }
                ToggleRow(title: "Address", shown: state.chromeLayout.sidebarShowsAddress, colors: colors, filled: true) {
                    state.chromeLayout.sidebarShowsAddress.toggle()
                }
                ToggleRow(title: "New Tab", shown: state.chromeLayout.sidebarShowsNewTab, colors: colors, filled: false) {
                    state.chromeLayout.sidebarShowsNewTab.toggle()
                }
                ForEach(0..<3, id: \.self) { i in
                    RoundedRectangle(cornerRadius: Radius.inner).fill(i == 0 ? colors.selected : colors.hover).frame(height: 18)
                }
                Spacer(minLength: 10)
                row(ChromeZone.bottomRow)
            }
            .padding(8)
            .frame(minWidth: 250, maxWidth: 300)
            .frame(height: 250)
            .background(RoundedRectangle(cornerRadius: Radius.card, style: .continuous).fill(colors.panel.opacity(0.8)))
            RoundedRectangle(cornerRadius: Radius.control, style: .continuous).fill(colors.pageBackground).frame(height: 250)
        }
    }

    /// A row's three places: left, centre (centred while there's room, never over the others) and right.
    private func row(_ zones: [ChromeZone]) -> some View {
        ThreeSlotLayout {
            ZoneView(zone: zones[0], state: state, colors: colors)
            ZoneView(zone: zones[1], state: state, colors: colors)
            ZoneView(zone: zones[2], state: state, colors: colors)
        }
        .frame(maxWidth: .infinity)
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
                ItemChip(item: item, zone: zone, colors: colors, spacesAsDots: !zone.isTop && zone != .rail) {
                    withAnimation(.ikago) { state.chromeLayout.remove(item, from: zone.family) }
                }
                .dropDestination(for: String.self) { ids, _ in return place(ids, before: item) }
            }
            if items.isEmpty {
                // An empty place: a small slot, so a row's three places fit beside each other.
                Image(systemName: "plus").font(.system(size: 9, weight: .medium)).foregroundStyle(colors.tertiary)
                    .frame(width: 22)
            }
        }
        .frame(minWidth: 26, minHeight: 30)
        .help(zone == .rail || ChromeZone.toolbarRow.contains(zone) ? zone.title : "\(zone.isTop ? "Top" : "Bottom") \(zone.title.lowercased())")
        .padding(.horizontal, 2)
        .background(RoundedRectangle(cornerRadius: Radius.control, style: .continuous)
            .strokeBorder(targeted ? Color.settingsAccent : colors.separator, style: StrokeStyle(lineWidth: 1, dash: [3, 3]))
            .opacity(targeted || items.isEmpty ? 1 : 0.6))
        .dropDestination(for: String.self) { ids, _ in place(ids, before: nil) } isTargeted: { targeted = $0 }
    }

    private func place(_ ids: [String], before target: ChromeItem?) -> Bool {
        guard let (item, _) = ids.first.flatMap(ChipPayload.parse), zone.allowed.contains(item) else { return false }
        withAnimation(.ikago) { state.chromeLayout.place(item, in: zone, before: target) }
        return true
    }
}

/// One placed item: drag to move; hover shows − to remove.
private struct ItemChip: View {
    let item: ChromeItem
    let zone: ChromeZone
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
        .background(RoundedRectangle(cornerRadius: Radius.control).fill(hovering ? colors.hover.opacity(2) : .clear))
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
        .draggable(ChipPayload.make(item, from: zone)) { ChipPreview(item: item) }
        .help(item.name)
    }
}

/// Items not placed in the layout's places. Drop an item here to remove it from the place it came from.
private struct AvailableTray: View {
    let state: BrowserState
    let colors: Palette
    let zones: [ChromeZone]
    /// Where a click adds an item.
    let home: ChromeZone
    @State private var targeted = false

    var body: some View {
        let items = state.chromeLayout.available(in: zones)
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
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .draggable(item.rawValue) { ChipPreview(item: item) }
                .help("Click or drag to add")
            }
            Spacer(minLength: 0)
        } }
        .scrollIndicators(.never)
        .padding(8)
        .background(RoundedRectangle(cornerRadius: Radius.row, style: .continuous)
            .strokeBorder(targeted ? Color.red.opacity(0.6) : .clear, style: StrokeStyle(lineWidth: 1, dash: [3, 3])))
        .dropDestination(for: String.self) { ids, _ in
            guard let (item, from) = ids.first.flatMap(ChipPayload.parse) else { return false }
            withAnimation(.ikago) { state.chromeLayout.remove(item, from: from?.family ?? zones) }
            return true
        } isTargeted: { targeted = $0 }
    }

    private func add(_ item: ChromeItem) {
        withAnimation(.ikago) { state.chromeLayout.place(item, in: home) }
    }
}

// MARK: - Mockup pieces

private struct ChipPreview: View {
    let item: ChromeItem
    var body: some View {
        Label(item.name, systemImage: item.symbol).font(.system(size: 12)).padding(6)
            .background(RoundedRectangle(cornerRadius: Radius.inner).fill(Color(white: 0.5).opacity(0.3)))
    }
}

struct TrafficLights: View {
    var body: some View {
        HStack(spacing: 5) {
            ForEach([Color.red, .yellow, .green], id: \.self) { Circle().fill($0.opacity(0.85)).frame(width: 9, height: 9) }
        }
    }
}

struct FakeTab: View {
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
            .background(RoundedRectangle(cornerRadius: Radius.inner).fill(filled ? colors.hover.opacity(1.5) : .clear))
            .opacity(shown ? 1 : 0.4)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(shown ? "Click to hide" : "Click to show")
    }
}
