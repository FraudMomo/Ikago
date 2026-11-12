import SwiftUI

/// A composed header with a compact visual, rather than a large decorative banner.
struct SettingsCategoryHeader: View {
    let category: SettingsCategory
    let colors: Palette
    var body: some View {
        HStack(spacing: 16) {
            SettingsCategoryArtwork(category: category, colors: colors)
                .frame(width: 56, height: 56)
            VStack(alignment: .leading, spacing: 5) {
                Text(category.title).font(.system(size: 28, weight: .semibold)).tracking(-0.6)
                Text(category.detail).font(.system(size: 12)).foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }.frame(maxWidth: .infinity, alignment: .leading).padding(.bottom, 4)
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
