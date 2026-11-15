import SwiftUI

/// Settings ▸ General ▸ Other Devices: Safari's tabs from the person's iPhone, iPad and other Macs, and Handoff.
struct OtherDevicesSection: View {
    @Bindable var state: BrowserState

    var body: some View {
        PageSection(title: "Other Devices",
                    footer: "Tabs come from Safari on this Mac, which syncs them through iCloud; they stay on this Mac. Handoff needs the same Apple Account, Bluetooth and Wi-Fi.") {
            PageRow(title: "Tabs from other devices", subtitle: "Show Safari’s open tabs and Tab Groups from your iPhone and iPad in a Devices button") {
                Toggle("Tabs from other devices", isOn: Binding(get: { state.browserPreferences.safariDeviceTabs == true }, set: setDeviceTabs))
                    .labelsHidden().toggleStyle(.switch)
            }
            PageDivider()
            PageRow(title: "Handoff", subtitle: "Continue this page on your iPhone, and open pages from it here when Ikago is your default browser") {
                Toggle("Handoff", isOn: Binding(get: { state.browserPreferences.handoff == true },
                                                set: { state.browserPreferences.handoff = $0 ? true : nil }))
                    .labelsHidden().toggleStyle(.switch)
            }
        }
    }

    /// Turning it on places the Devices control at the end of the sidebar's top row; off removes it.
    private func setDeviceTabs(_ on: Bool) {
        state.browserPreferences.safariDeviceTabs = on ? true : nil
        if on {
            if !state.chromeLayout.contains(.devices) { state.chromeLayout.place(.devices, in: .sidebarTop) }
            Task { await SafariSyncedTabsModel.shared.refresh(force: true) }
        } else {
            state.chromeLayout.remove(.devices)
        }
    }
}
