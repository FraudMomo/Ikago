import SwiftUI

/// Settings ▸ Security ▸ Permissions ▸ Notifications: whether sites may ask, and the sites already decided.
struct NotificationSettingsSection: View {
    @Bindable var state: BrowserState

    private var decided: [(host: String, choice: SitePermission)] {
        (state.browserPreferences.sitePermissions ?? [:]).compactMap { host, entry in entry.notifications.map { (host, $0) } }
            .sorted { $0.host < $1.host }
    }

    var body: some View {
        PageSection(title: "Notifications",
                    footer: "Sites ask the first time they want to notify you. Notifications arrive through macOS and never in private windows.") {
            PageRow(title: "Website notifications", subtitle: "Let sites ask to send notifications") {
                Toggle("Website notifications", isOn: Binding(get: { state.browserPreferences.websiteNotifications ?? true },
                                                              set: { state.browserPreferences.websiteNotifications = $0 ? nil : false }))
                    .labelsHidden().toggleStyle(.switch)
            }
            ForEach(decided, id: \.host) { site in
                PageDivider()
                PageRow(title: site.host, subtitle: nil) {
                    HStack(spacing: 8) {
                        CompactMenu(value: site.choice.title, choices: [SitePermission.allow, .block].map { choice in
                            MenuChoice(title: choice.title, isOn: choice == site.choice) {
                                state.setSitePermission(choice, .notifications, host: site.host)
                            }
                        })
                        Button("Remove") { state.setSitePermission(.ask, .notifications, host: site.host) }
                    }
                }
            }
        }
    }
}
