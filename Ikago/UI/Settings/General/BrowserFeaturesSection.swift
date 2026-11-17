import SwiftUI

struct BrowserFeaturesSection: View {
    @Bindable var state: BrowserState

    var body: some View {
        PageSection(title: "Tab Previews") {
            PageRow(title: "Show a preview on hover", subtitle: "Title, site and memory after resting on a tab") {
                Toggle("Show a preview on hover", isOn: Binding(get: { state.browserPreferences.tabHoverPreviews != false },
                    set: { state.browserPreferences.tabHoverPreviews = $0 ? nil : false })).labelsHidden().toggleStyle(.switch)
            }
            if state.browserPreferences.tabHoverPreviews != false {
                PageDivider()
                PageRow(title: "Include a page thumbnail") {
                    Toggle("Include a page thumbnail", isOn: Binding(get: { state.browserPreferences.tabPreviewThumbnails != false },
                        set: { state.browserPreferences.tabPreviewThumbnails = $0 ? nil : false })).labelsHidden().toggleStyle(.switch)
                }
            }
        }
        PageSection(title: "Background Tabs") {
            PageRow(title: "Load new tabs in the background") {
                Toggle("Load new tabs in the background", isOn: Binding(get: { state.browserPreferences.loadBackgroundTabs ?? true },
                    set: { state.browserPreferences.loadBackgroundTabs = $0 })).labelsHidden().toggleStyle(.switch)
            }
        }
    }
}

/// Settings ▸ Performance: how Ikago saves memory, and its live performance monitor.
struct PerformanceSettingsSection: View {
    @Bindable var state: BrowserState
    weak var commands: BrowserCommands?

    var body: some View {
        PageSection(title: "Memory", footer: "Released pages reload when selected. Visible pages, playing media and unsaved forms stay open.") {
            PageRow(title: "Memory approach", subtitle: state.browserPreferences.resourcePolicy.summary) {
                SettingsMenu(selection: $state.browserPreferences.resourcePolicy, options: ResourcePolicy.allCases.map { ($0, $0.title) })
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
        PageSection(title: "Monitor", footer: "Frame times, CPU and memory for Ikago and each open page, updated live.") {
            PageRow(title: "Performance monitor", subtitle: "See what each tab and Ikago itself are using") {
                Button("Open") { commands?.openPage(.performance) }
            }
        }
    }
}

struct TabPlacementSection: View {
    @Bindable var state: BrowserState

    var body: some View {
        PageSection(title: "Tab Placement") {
            PageRow(title: "New tab position",
                    subtitle: state.usesTabsLayout ? "Tabs above the page open on the right" : nil) {
                SettingsMenu(selection: $state.newTabPosition, options: NewTabPosition.allCases.map { ($0, $0.title) })
                .disabled(state.usesTabsLayout)
            }
            .opacity(state.usesTabsLayout ? 0.5 : 1)
            PageDivider()
            PageRow(title: "Links opened in new tabs") {
                SettingsMenu(selection: $state.linkTabPosition, options: LinkTabPosition.allCases.map { ($0, $0.title) })
            }
        }
    }
}
