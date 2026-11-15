import SwiftUI

/// Settings ▸ General ▸ Web Apps: the sites kept as apps, to open, find in Finder or remove.
struct WebAppsSection: View {
    @Bindable var state: BrowserState

    var body: some View {
        let apps = WebApps.all(state)
        PageSection(title: "Web Apps",
                    footer: "Add a site from its site card (the button at the end of the address). A web app opens in its own Ikago window, without the sidebar, on the Space it was added from.") {
            if apps.isEmpty {
                PageRow(title: "No web apps yet", subtitle: "Open a site, then choose Add to Applications from its site card.") { EmptyView() }
            }
            ForEach(Array(apps.enumerated()), id: \.element.id) { index, app in
                if index > 0 { PageDivider() }
                PageRow(title: app.name, subtitle: app.host) {
                    HStack(spacing: 8) {
                        Button("Open") { WebApps.open(app.id) }
                        Button("Show in Finder") { NSWorkspace.shared.activateFileViewerSelecting([WebAppLauncher.url(for: app)]) }
                        Button("Remove", role: .destructive) { WebApps.remove(app, state: state) }
                    }
                    .buttonStyle(SettingsButtonStyle())
                }
            }
        }
    }
}

/// Settings ▸ General ▸ Browser ▸ Translation: the language pages are translated into.
struct TranslationSettingsSection: View {
    @Bindable var state: BrowserState

    var body: some View {
        PageSection(title: "Translation", footer: "Translate Page runs on this Mac with Apple’s Translation. The first time for a language, macOS asks to download it.") {
            PageRow(title: "Translate pages into", subtitle: "Translate Page starts here; pick any other language in its card") {
                SettingsMenu(selection: Binding(get: { state.browserPreferences.translationLanguage ?? "" },
                                                set: { state.browserPreferences.translationLanguage = $0.isEmpty ? nil : $0 }),
                             options: [("", "Mac’s language (\(PageTranslation.name(Locale.current.language)))")]
                                + PageTranslation.choices.map { ($0, PageTranslation.name(Locale.Language(identifier: $0))) })
            }
        }
    }
}
