import SwiftUI

/// Each Settings category splits into a few sub-pages shown one at a time under a small segmented bar, so a page never
/// lists everything at once. A sub-page names the `PageSection`s it shows (`settingsVisibleSections`); the category's
/// content stays one list, and sections outside the chosen sub-page draw nothing.
struct SettingsSubpage: Identifiable, Equatable {
    let title: String
    let sections: Set<String>
    var id: String { title }
}

extension SettingsCategory {
    var subpages: [SettingsSubpage] {
        func page(_ title: String, _ sections: String...) -> SettingsSubpage { SettingsSubpage(title: title, sections: Set(sections)) }
        switch self {
        case .general:
            return [page("Browser", "Browser Engine", "Default Browser", "Translation", "Apple Intelligence"),
                    page("Web Apps", "Web Apps"),
                    page("Engine by Site", "Engine by Site", "Your Sites"),
                    page("Other Devices", "Other Devices"),
                    page("Advanced", "Advanced")]
        case .appearance:
            return [page("Theme", "Color & Theme", "Materials"),
                    page("Layout", "Layout", "Window and Sidebar", "Full Screen"),
                    page("Details", "Tab Groups", "Tab Animations")]
        case .toolbar:
            return [page("Sidebar", "Sidebar", "Sidebar Essentials", "Bookmarks Bar"),
                    page("Toolbar", "Customize")]
        case .tabs:
            return [page("New Tabs", "New Tab", "Tab Placement", "Background Tabs", "Opening Bookmarks"),
                    page("Links & Peek", "Peek", "Tab Previews"),
                    page("Memory", "Memory")]
        case .search:
            return [page("Search & Address", "Search & Address Bar"), page("Suggestions", "Suggestions")]
        case .extensions:
            return [page("Installed", "Extensions", "Installed", "Safari Extensions"), page("Get & Update", "Add Extensions", "Extension Updates")]
        case .security:
            return [page("Protection", "Status", "Secure Connections", "Website Safety", "Tracking Protection"),
                    page("Permissions", "Downloads", "Notifications"),
                    page("Website Data", "Browsing Data")]
        case .passwords:
            return [page("AutoFill", "AutoFill"), page("Saved", "Saved in Ikago", "Import from Apple Passwords", "Export to Apple Passwords")]
        case .about:
            return [page("Overview", "Ikago"), page("Developer", "Developer")]
        case .history, .imports:
            return []
        }
    }

    /// The sub-page holding `section`, for search results and the address bar's settings.
    func subpage(containing section: String) -> SettingsSubpage? { subpages.first { $0.sections.contains(section) } }

    /// The navigation's group headings, in `navigationGroups` order.
    static let navigationGroupTitles = ["Personalize", "Your Browsing", ""]
}

extension EnvironmentValues {
    /// The sections of the chosen sub-page; nil shows every section.
    @Entry var settingsVisibleSections: Set<String>? = nil
}

/// The sub-pages as a quiet segmented bar: the chosen one sits on a lifted pill that slides between them.
struct SettingsSubnav: View {
    let pages: [SettingsSubpage]
    @Binding var selection: String
    let colors: Palette
    @Namespace private var namespace
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack(spacing: 2) {
            ForEach(pages) { page in
                let selected = page.title == selection
                Button {
                    withAnimation(reduceMotion ? nil : .spring(duration: 0.3, bounce: 0.15)) { selection = page.title }
                } label: {
                    Text(page.title).font(.system(size: 12.5, weight: selected ? .semibold : .medium))
                        .foregroundStyle(selected ? colors.text : colors.secondary)
                        .padding(.horizontal, 14).frame(height: 28)
                        .background {
                            if selected {
                                Capsule().fill(colors.isDark ? Color.white.opacity(0.14) : .white)
                                    .shadow(color: .black.opacity(colors.isDark ? 0.3 : 0.1), radius: 1.5, y: 0.5)
                                    .matchedGeometryEffect(id: "selection", in: namespace)
                            }
                        }
                        .contentShape(Capsule())
                }
                .buttonStyle(SiteCardPressStyle(scale: 0.96))
                .accessibilityAddTraits(selected ? .isSelected : [])
            }
        }
        .padding(3)
        .background(Capsule().fill(colors.text.opacity(colors.isDark ? 0.07 : 0.055)))
    }
}

/// Settings' quieter page color, a step off the cards that sit on it.
enum SettingsColors {
    static func page(_ colors: Palette) -> Color { colors.isDark ? Color(hex: 0x161718) : Color(hex: 0xF2F3F2) }
    static func card(_ colors: Palette) -> Color { colors.isDark ? Color(hex: 0x222325) : .white }
}
