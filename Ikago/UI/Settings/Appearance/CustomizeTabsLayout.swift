import SwiftUI

/// Settings ▸ Customize in Top Tabs: the tab row, then the toolbar with its places (left, right, and inside the
/// address field), above the page.
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
                AddressChip(state: state, colors: colors).frame(maxWidth: 260)
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

/// Below the mockup: in Top Tabs, the icons-only sidebar's foot; above the page, the address's style.
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
        }
    }

    private func line(_ title: String, @ViewBuilder content: () -> some View) -> some View {
        HStack(spacing: 10) {
            Text(title).font(.system(size: 12, weight: .semibold)).foregroundStyle(.secondary).frame(width: 140, alignment: .leading)
            content()
            Spacer(minLength: 0)
        }
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
