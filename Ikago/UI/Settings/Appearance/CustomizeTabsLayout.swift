import SwiftUI

/// Settings ▸ Customize in Top Tabs: the tab row, then the toolbar with its four places (the window's edges and
/// either side of the address field), above the page.
struct TabsMockup: View {
    let state: BrowserState
    let colors: Palette

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 6) {
                TrafficLights()
                FakeTab(colors: colors, active: true, width: 90)
                FakeTab(colors: colors, active: false, width: 90)
                Image(systemName: "plus").font(.system(size: 9, weight: .medium)).foregroundStyle(colors.tertiary)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 8).padding(.bottom, 6)
            HStack(spacing: 8) {
                ZoneView(zone: .toolbarLeading, state: state, colors: colors)
                Spacer(minLength: 4)
                ZoneView(zone: .toolbarNearLeading, state: state, colors: colors)
                RoundedRectangle(cornerRadius: Radius.inner, style: .continuous).fill(colors.hover.opacity(1.5))
                    .frame(height: 24)
                    .overlay { Text("Address").font(.system(size: 11)).foregroundStyle(colors.secondary) }
                    .frame(minWidth: 80, maxWidth: 200)
                ZoneView(zone: .toolbarNearTrailing, state: state, colors: colors)
                Spacer(minLength: 4)
                ZoneView(zone: .toolbarTrailing, state: state, colors: colors)
            }
            .padding(6)
            .frame(height: CGFloat(state.tabsToolbarHeight) + 8)
            .background(UnevenRoundedRectangle(topLeadingRadius: Radius.control, topTrailingRadius: Radius.control,
                                               style: .continuous).fill(colors.tabSheet))
            Rectangle().fill(colors.pageBackground).frame(height: 120)
                .clipShape(UnevenRoundedRectangle(bottomLeadingRadius: Radius.control, bottomTrailingRadius: Radius.control,
                                                  style: .continuous))
        }
    }
}

/// Below the mockup: the icons-only sidebar's foot, the address field's own buttons and, in Top Tabs, the bar's
/// height.
struct CustomizeExtras: View {
    let state: BrowserState
    let colors: Palette

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            // Top Tabs has no full sidebar mockup: the icons-only sidebar's place is listed here instead.
            if state.usesTabsLayout { line("Icons-only sidebar") { ZoneView(zone: .rail, state: state, colors: colors) } }
            if !state.usesTabsLayout && state.browserPreferences.addressAbovePage == true {
                line("Address style") {
                    SettingsMenu(selection: Binding(
                        get: { state.browserPreferences.pageBarStyle ?? .wide },
                        set: { new in withAnimation(.ikago) { state.browserPreferences.pageBarStyle = new == .wide ? nil : new } }
                    ), options: TabsAddressStyle.allCases.map { ($0, $0.name) })
                }
            }
            line("In the address field") {
                HStack(spacing: 6) {
                    toggle("Reload", symbol: "arrow.clockwise", shown: state.chromeLayout.addressShowsReload) {
                        state.chromeLayout.addressShowsReload.toggle()
                    }
                    toggle("Site & Extensions", symbol: "puzzlepiece.extension", shown: state.chromeLayout.addressShowsSiteInfo) {
                        state.chromeLayout.addressShowsSiteInfo.toggle()
                    }
                }
            }
            if state.usesTabsLayout {
                line("Bar height") { BarHeightSlider(state: state) }
            }
        }
    }

    private func line(_ title: String, @ViewBuilder content: () -> some View) -> some View {
        HStack(spacing: 10) {
            Text(title).font(.system(size: 12, weight: .semibold)).foregroundStyle(.secondary).frame(width: 140, alignment: .leading)
            content()
            Spacer(minLength: 0)
        }
    }

    private func toggle(_ title: String, symbol: String, shown: Bool, action: @escaping () -> Void) -> some View {
        Button { withAnimation(.ikago) { action() } } label: {
            Label(title, systemImage: shown ? symbol : "eye.slash")
                .font(.system(size: 12))
                .padding(.horizontal, 10).padding(.vertical, 5)
                .background(Capsule().fill(Color.primary.opacity(shown ? 0.08 : 0.03)))
                .opacity(shown ? 1 : 0.5)
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .help(shown ? "Shown while the pointer is over the address. Click to hide." : "Hidden. Click to show.")
    }
}

/// What a dragged control carries: the item, and the place it came from (none from Available).
enum ChipPayload {
    static func make(_ item: ChromeItem, from zone: ChromeZone) -> String { "\(item.rawValue)@\(zone.rawValue)" }

    static func parse(_ text: String) -> (ChromeItem, ChromeZone?)? {
        let parts = text.split(separator: "@", maxSplits: 1).map(String.init)
        guard let item = parts.first.flatMap(ChromeItem.init(rawValue:)) else { return nil }
        return (item, parts.count > 1 ? ChromeZone(rawValue: parts[1]) : nil)
    }
}

/// The address bar's height in points, any value from 26 to 52. The bar (and the page under it) resizes once when the
/// slider is let go, not on every step: pages must not be resized frame by frame.
private struct BarHeightSlider: View {
    let state: BrowserState
    @State private var value: Double?

    var body: some View {
        let current = value ?? Double(state.tabsToolbarHeight)
        HStack(spacing: 10) {
            Slider(value: Binding(get: { current }, set: { value = $0.rounded() }), in: 26...52, step: 1) { editing in
                guard !editing, let value else { return }
                state.browserPreferences.tabsBarHeight = value == TabsBarHeight.standard.rawValue ? nil : value
                self.value = nil
            }
            .frame(width: 160)
            Text("\(Int(current)) pt").font(.system(size: 12)).monospacedDigit().foregroundStyle(.secondary).frame(width: 40, alignment: .trailing)
            if state.browserPreferences.tabsBarHeight != nil {
                Button("Reset") { state.browserPreferences.tabsBarHeight = nil }
                    .buttonStyle(.plain).font(.system(size: 12)).foregroundStyle(.secondary)
            }
        }
    }
}
