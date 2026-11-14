import SwiftUI

/// The page's title and one short line, set like a document heading: no artwork, no banner.
struct SettingsCategoryHeader: View {
    let category: SettingsCategory
    let colors: Palette
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(category.title).font(.system(size: 24, weight: .semibold)).tracking(-0.4)
            Text(category.detail).font(.system(size: 13)).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

extension SettingsCategory {
    var detail: String {
        switch self {
        case .general: "Your engine and everyday tools"
        case .appearance: "Shape your browsing space"
        case .toolbar: "Keep useful controls within reach"
        case .tabs: "Opening, organizing and memory"
        case .search: "Search and address suggestions"
        case .extensions: "Manage what runs in your browser"
        case .history: "Pages you’ve visited, and clearing browsing data"
        case .security: "Connections, permissions and browsing data"
        case .passwords: "Sign in with your preferred password source"
        case .imports: "Choose what to bring from another browser"
        case .about: "Version, updates and developer tools"
        }
    }
}

extension EnvironmentValues {
    @Entry var settingsSurface = false
}
