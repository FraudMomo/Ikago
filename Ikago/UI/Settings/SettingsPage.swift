import SwiftUI

enum SettingsCategory: String, CaseIterable, Identifiable {
    case general, appearance, toolbar, tabs, search, extensions, security, passwords, imports, about
    var id: String { rawValue }
    var title: String {
        switch self {
        case .general: "General"
        case .appearance: "Appearance"
        case .toolbar: "Sidebar & Toolbar"
        case .tabs: "Tabs"
        case .search: "Search"
        case .extensions: "Extensions"
        case .security: "Privacy & Security"
        case .passwords: "Passwords"
        case .imports: "Import"
        case .about: "About"
        }
    }
    static var navigationGroups: [[Self]] {
        [[.general, .appearance, .toolbar, .tabs, .search], [.extensions, .security, .passwords], [.imports, .about]]
    }
    var symbol: String {
        switch self {
        case .general: "gearshape"
        case .appearance: "paintpalette"
        case .toolbar: "sidebar.left"
        case .tabs: "square.on.square"
        case .search: "magnifyingglass"
        case .extensions: "puzzlepiece.extension"
        case .security: "hand.raised"
        case .passwords: "key"
        case .imports: "square.and.arrow.down"
        case .about: "info.circle"
        }
    }
}

/// Each category has its own page and scroll position; narrow windows use a category menu.
/// The search field above the categories lists matching settings and opens each at its section.
struct SettingsPage: View {
    @Bindable var state: BrowserState
    weak var commands: BrowserCommands?
    @State private var query = ""
    @State private var target: String?
    @State private var highlight: String?
    @FocusState private var searchFocused: Bool

    var body: some View {
        GeometryReader { geometry in
            let wide = geometry.size.width >= 760
            let navigationWidth: CGFloat = wide ? 220 : 0
            HStack(spacing: 0) {
                if wide {
                    navigation.frame(width: navigationWidth, height: geometry.size.height)
                        .recordLayout("settings-navigation")
                }
                VStack(spacing: 0) {
                    if !wide {
                        Picker("Settings", selection: $state.settingsCategory) {
                            ForEach(SettingsCategory.allCases) { Label($0.title, systemImage: $0.symbol).tag($0) }
                        }.pickerStyle(.menu).padding(16).frame(maxWidth: .infinity, alignment: .leading)
                    }
                    PageScaffold(title: state.settingsCategory.title, colors: state.palette, scrollTarget: target) {
                        categoryContent
                    }
                    .environment(\.settingsHighlight, highlight)
                    .id(state.settingsCategory).recordLayout("settings-content")
                }
                .frame(width: max(0, geometry.size.width - navigationWidth), height: geometry.size.height)
            }
            .frame(width: geometry.size.width, height: geometry.size.height, alignment: .topLeading)
            .background(state.palette.pageBackground)
            .buttonStyle(.automatic)  // standard macOS controls, not the browser's glass
        }.recordLayout("settings")
    }

    private var navigation: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Settings").font(.system(size: 20, weight: .semibold))
                .padding(.leading, 10).padding(.top, 20)
            SettingsSearchField(text: $query, focused: $searchFocused)
            ScrollView {
                if query.trimmingCharacters(in: .whitespaces).isEmpty {
                    categories
                } else {
                    SettingsSearchResults(results: SettingsSearch.results(for: query), colors: state.palette, open: open)
                }
            }
            .scrollIndicators(.never)
        }
        .padding(.horizontal, 12).padding(.top, 16)
        .foregroundStyle(state.palette.text)
        .overlay(alignment: .trailing) { Color.primary.opacity(0.08).frame(width: 1) }
    }

    private var categories: some View {
        VStack(alignment: .leading, spacing: 14) {
            ForEach(Array(SettingsCategory.navigationGroups.enumerated()), id: \.offset) { _, categories in
                VStack(spacing: 2) {
                    ForEach(categories) { category in
                        SettingsNavigationRow(category: category, selected: state.settingsCategory == category, colors: state.palette) {
                            target = nil
                            state.settingsCategory = category
                        }
                    }
                }
            }
        }
        .padding(.bottom, 16)
    }

    /// Opens a result's page at its section and outlines the section for a moment.
    private func open(_ entry: SettingsSearchEntry) {
        state.settingsCategory = entry.category
        target = entry.section
        highlight = entry.section
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(1.4))
            if highlight == entry.section { highlight = nil }
        }
    }

    @ViewBuilder private var categoryContent: some View {
        switch state.settingsCategory {
        case .general:
            EngineSettingsSection(state: state)
            SiteEnginesSection(state: state)
            DefaultBrowserSection()
        case .search:
            SearchSettingsSection(state: state)
        case .appearance:
            PageSection(title: "Layout") {
                HStack(spacing: 14) {
                    ForEach(TabLayout.allCases) { layout in
                        LayoutCard(layout: layout, selected: state.tabLayout == layout, colors: state.palette) { state.tabLayout = layout }
                    }
                }.padding(16)
            }
            if state.tabLayout == .horizontal { TopBarSettingsSection(state: state) }
            SpacingSection(state: state)
            AppearanceSection(state: state)
            GroupAppearanceSection(state: state)
            TabMotionSection(state: state)
        case .toolbar:
            EssentialsSettingsSection(state: state)
            CustomizeSection(state: state)
        case .tabs:
            NewTabSection(state: state)
            TabPlacementSection(state: state)
            BookmarkOpeningSection(state: state)
            BrowserFeaturesSection(state: state)
        case .extensions:
            // Each engine has its own extensions; with per-site engines both can run.
            if BrowserRuntime.runs(.webkit) {
                ExtensionsSection(commands: commands)
                ExtensionUpdatesSection()
            }
            if BrowserRuntime.runs(.chromium) {
                CEFExtensionsSection(state: state, commands: commands)
            }
        case .security:
            PageSection(title: "Status") { SecurityDashboard(state: state) }
            SecuritySettingsSection(state: state)
            TrackingProtectionSection(state: state)
            PrivacySettingsSection(state: state)
        case .passwords:
            PasswordSettingsSection(state: state)
        case .imports:
            BrowserImportSection(state: state)
        case .about: AboutSettingsSection(state: state)
        }
    }
}

private struct SettingsNavigationRow: View {
    let category: SettingsCategory
    let selected: Bool
    let colors: Palette
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: category.symbol).font(.system(size: 14, weight: selected ? .medium : .regular))
                    .frame(width: 20)
                Text(category.title).font(.system(size: 13, weight: selected ? .medium : .regular)).lineLimit(1)
                Spacer(minLength: 0)
            }
            .foregroundStyle(selected ? colors.text : colors.secondary)
            .padding(.horizontal, 10).frame(height: 32)
            .background(RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color.primary.opacity(selected ? 0.09 : hovering ? 0.045 : 0)))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}
