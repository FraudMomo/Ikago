import SwiftUI

struct BrowserFeaturesSection: View {
    @Bindable var state: BrowserState

    var body: some View {
        PageSection(title: "Background Tabs") {
            PageRow(title: "Load new tabs in the background") {
                Toggle("Load new tabs in the background", isOn: Binding(get: { state.browserPreferences.loadBackgroundTabs ?? true },
                    set: { state.browserPreferences.loadBackgroundTabs = $0 })).labelsHidden().toggleStyle(.switch)
            }
        }
        PageSection(title: "Memory", footer: "Released pages reload when selected. Visible pages, playing media and unsaved forms stay open.") {
            PageRow(title: "Memory approach", subtitle: state.browserPreferences.resourcePolicy.summary) {
                Picker("Memory approach", selection: $state.browserPreferences.resourcePolicy) {
                    ForEach(ResourcePolicy.allCases) { Text($0.title).tag($0) }
                }.labelsHidden()
            }
            PageDivider()
            PageRow(title: "Keep pinned tabs awake") {
                Toggle("Keep pinned tabs awake", isOn: $state.browserPreferences.protectPinnedTabs)
                    .labelsHidden().toggleStyle(.switch)
            }
            PageDivider()
            PageRow(title: "Always keep these sites awake", subtitle: "Comma-separated, includes subdomains") {
                TextField("mail.example.com, example.org", text: $state.browserPreferences.hibernationExceptions)
                    .textFieldStyle(.roundedBorder).frame(maxWidth: 280)
            }
        }
    }
}

struct TabPlacementSection: View {
    @Bindable var state: BrowserState

    var body: some View {
        PageSection(title: "Tab Placement", footer: "Applies to the Sidebar layout.") {
            PageRow(title: "New tab position") {
                Picker("New tab position", selection: $state.newTabPosition) {
                    ForEach(NewTabPosition.allCases) { Text($0.title).tag($0) }
                }.labelsHidden()
            }
            PageDivider()
            PageRow(title: "Links opened in new tabs") {
                Picker("Links opened in new tabs", selection: $state.linkTabPosition) {
                    ForEach(LinkTabPosition.allCases) { Text($0.title).tag($0) }
                }.labelsHidden()
            }
        }
    }
}
