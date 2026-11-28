import SwiftUI

/// Settings ▸ Customize: a live mockup of the current layout. The sidebar has its top and bottom rows; Top Tabs has the
/// toolbar's left and right instead. Both have the inside of the address field, and the icons-only sidebar its foot.
/// Drag items into any place, reorder within one, hover and click − to remove, drag (or click) from Available to add.
struct CustomizeSection: View {
    let state: BrowserState

    var body: some View {
        let colors = state.palette
        let tabs = state.usesTabsLayout
        PageSection(title: "Customize",
                    footer: "Drag items into a row, into the address field or into the icons-only sidebar. Drag the address between the sidebar and above the page. Hover and click − to remove; click an item in Available to add it.") {
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
                              zones: tabs ? ChromeZone.toolbarRow : ChromeZone.sidebarRows,
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
            // The icons-only sidebar, with its own place for controls.
            VStack(spacing: 6) {
                VStack(spacing: 3) { ForEach(0..<3, id: \.self) { _ in Circle().fill(colors.tertiary).frame(width: 7, height: 7) } }
                    .padding(.top, 4)
                ZoneView(zone: .rail, state: state, colors: colors, vertical: true)
                ForEach(0..<4, id: \.self) { i in
                    RoundedRectangle(cornerRadius: Radius.inner).fill(i == 0 ? colors.selected : colors.hover).frame(width: 22, height: 22)
                }
                Spacer(minLength: 0)
                Text("Icons").font(.system(size: 9, weight: .medium)).foregroundStyle(colors.tertiary)
            }
            .padding(6)
            .frame(width: 46, height: 250)
            .background(RoundedRectangle(cornerRadius: Radius.card, style: .continuous).fill(colors.panel.opacity(0.8)))
            .help("Icons-only sidebar")
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 4) {
                    TrafficLights()
                    Spacer(minLength: 4)
                    ZoneView(zone: .sidebarTop, state: state, colors: colors)
                }
                // The address: drag it between the sidebar and the bar above the page.
                if pageBar { AddressDropSlot(state: state, colors: colors, abovePage: false) }
                else { AddressChip(state: state, colors: colors) }
                ToggleRow(title: "New Tab", shown: state.chromeLayout.sidebarShowsNewTab, colors: colors, filled: false) {
                    state.chromeLayout.sidebarShowsNewTab.toggle()
                }
                ForEach(0..<3, id: \.self) { i in
                    RoundedRectangle(cornerRadius: Radius.inner).fill(i == 0 ? colors.selected : colors.hover).frame(height: 18)
                }
                Spacer(minLength: 10)
                ZoneView(zone: .sidebarBottom, state: state, colors: colors).frame(maxWidth: .infinity)
            }
            .padding(8)
            .frame(minWidth: 230, maxWidth: 280)
            .frame(height: 250)
            .background(RoundedRectangle(cornerRadius: Radius.card, style: .continuous).fill(colors.panel.opacity(0.8)))
            VStack(spacing: 0) {
                // Above the page: the address, or a spot to drop it.
                HStack(spacing: 8) {
                    if pageBar { AddressChip(state: state, colors: colors) }
                    else { AddressDropSlot(state: state, colors: colors, abovePage: true) }
                }
                .padding(6)
                .background(UnevenRoundedRectangle(topLeadingRadius: Radius.control, topTrailingRadius: Radius.control,
                                                   style: .continuous).fill(pageBar ? colors.tabSheet : .clear))
                UnevenRoundedRectangle(topLeadingRadius: pageBar ? 0 : Radius.control, bottomLeadingRadius: Radius.control,
                                       bottomTrailingRadius: Radius.control, topTrailingRadius: pageBar ? 0 : Radius.control,
                                       style: .continuous)
                    .fill(colors.pageBackground)
            }
            .frame(height: 250)
        }
    }

    private var pageBar: Bool { state.browserPreferences.addressAbovePage == true }
}

/// What a dragged address field carries in the mockup.
private let addressPayload = "ikago-address"

/// The address field in the mockup, wherever it is, with the place for controls inside it: drag it to the other place;
/// the eye hides it (in the sidebar).
struct AddressChip: View {
    let state: BrowserState
    let colors: Palette

    var body: some View {
        let above = state.browserPreferences.addressAbovePage == true
        let shown = above || state.chromeLayout.sidebarShowsAddress
        HStack(spacing: 6) {
            Image(systemName: "line.3.horizontal").font(.system(size: 9, weight: .semibold)).foregroundStyle(colors.tertiary)
            Text("Address").font(.system(size: 11)).foregroundStyle(colors.secondary)
            Spacer(minLength: 4)
            ZoneView(zone: .address, state: state, colors: colors, small: true)
            if !above && !state.usesTabsLayout {
                Button { withAnimation(.ikago) { state.chromeLayout.sidebarShowsAddress.toggle() } } label: {
                    Image(systemName: shown ? "eye" : "eye.slash").font(.system(size: 10)).foregroundStyle(colors.tertiary)
                }
                .buttonStyle(.plain).help(shown ? "Hide the address field" : "Show the address field")
            }
        }
        .padding(.horizontal, 8)
        .frame(height: 30)
        .frame(minWidth: 80, maxWidth: .infinity)
        .background(RoundedRectangle(cornerRadius: Radius.inner, style: .continuous).fill(colors.hover.opacity(1.5)))
        .opacity(shown ? 1 : 0.45)
        .contentShape(Rectangle())
        .draggable(addressPayload) {
            Text("Address").font(.system(size: 11)).padding(.horizontal, 10).padding(.vertical, 4)
                .background(Capsule().fill(Color.settingsAccent.opacity(0.2)))
        }
        .help(above ? "Drag into the sidebar to put the address there" : "Drag above the page to put the address there")
    }
}

/// The place the address isn't: drop it here to move it.
private struct AddressDropSlot: View {
    let state: BrowserState
    let colors: Palette
    let abovePage: Bool
    @State private var targeted = false

    var body: some View {
        Text(abovePage ? "Drop the address here to put it above the page" : "Drop the address here")
            .font(.system(size: 10)).foregroundStyle(colors.tertiary)
            .frame(maxWidth: .infinity).frame(height: 24)
            .background(RoundedRectangle(cornerRadius: Radius.inner, style: .continuous)
                .strokeBorder(targeted ? Color.settingsAccent : colors.separator, style: StrokeStyle(lineWidth: 1, dash: [3, 3])))
            .dropDestination(for: String.self) { items, _ in
                guard items.first == addressPayload else { return false }
                withAnimation(.ikago) {
                    state.browserPreferences.addressAbovePage = abovePage ? true : nil
                    if !abovePage { state.chromeLayout.sidebarShowsAddress = true }
                }
                return true
            } isTargeted: { targeted = $0 }
    }
}

/// A spot that holds items: drop onto an item to go before it, onto the spot to go last.
struct ZoneView: View {
    let zone: ChromeZone
    let state: BrowserState
    let colors: Palette
    /// Items stacked top to bottom (the icons-only sidebar).
    var vertical = false
    /// Inside the address field's chip: shorter.
    var small = false
    @State private var targeted = false

    var body: some View {
        let items = state.chromeLayout[zone]
        let stack = vertical ? AnyLayout(VStackLayout(spacing: 2)) : AnyLayout(HStackLayout(spacing: 2))
        stack {
            ForEach(items) { item in
                ItemChip(item: item, zone: zone, colors: colors, spacesAsDots: zone == .sidebarBottom) {
                    withAnimation(.ikago) { state.chromeLayout.remove(item, from: zone.family) }
                }
                .dropDestination(for: String.self) { ids, _ in return place(ids, before: item) }
            }
            if items.isEmpty {
                // An empty place: a small slot, so a row's three places fit beside each other.
                Image(systemName: "plus").font(.system(size: 9, weight: .medium)).foregroundStyle(colors.tertiary)
                    .frame(width: 22, height: vertical ? 22 : nil)
            }
        }
        .frame(minWidth: 26, minHeight: small ? 24 : 30)
        .help(zone.title)
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
