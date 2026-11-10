import SwiftUI

enum SettingsCategory: String, CaseIterable, Identifiable {
    case general, search, tabs, appearance, toolbar, extensions, security, passwords, privacy, imports, about
    var id: String { rawValue }
    var navigationTitle: String { self == .imports ? "Import Data" : title }
    var title: String {
        switch self {
        case .general: "General"
        case .search: "Search"
        case .toolbar: "Toolbar & Sidebar"
        case .appearance: "Appearance"
        case .tabs: "Tabs & Memory"
        case .extensions: "Extensions"
        case .security: "Security"
        case .passwords: "Passwords"
        case .privacy: "Privacy"
        case .imports: "Import Browser Data"
        case .about: "About & Updates"
        }
    }
    var detail: String {
        switch self {
        case .general: "Browser engine, default browser and importing data."
        case .search: "Search engine and address bar suggestions."
        case .tabs: "New tabs, link placement, bookmarks and memory."
        case .appearance: "Layout, colors, spacing and motion."
        case .toolbar: "Toolbar controls, pinned tabs and the bookmarks bar."
        case .extensions: "Installed extensions and their updates."
        case .security: "HTTPS, website warnings and protected storage."
        case .passwords: "Where sign-in details are filled from."
        case .privacy: "Tracking protection and browsing data."
        case .imports: "Bookmarks, history and open tabs from another browser."
        case .about: "Version, updates and developer tools."
        }
    }
    static var navigationGroups: [[Self]] {
        [[.general, .search, .tabs], [.appearance, .toolbar, .extensions], [.security, .passwords, .privacy], [.imports, .about]]
    }
    var symbol: String {
        switch self {
        case .general: "gearshape"
        case .search: "magnifyingglass"
        case .toolbar: "slider.horizontal.3"
        case .appearance: "paintpalette"
        case .tabs: "square.on.square"
        case .extensions: "puzzlepiece.extension"
        case .security: "lock.shield"
        case .passwords: "key"
        case .privacy: "hand.raised"
        case .imports: "square.and.arrow.down"
        case .about: "info.circle"
        }
    }
}

/// Each category has its own page and scroll position; narrow windows use a category menu.
struct SettingsPage: View {
    @Bindable var state: BrowserState
    weak var commands: BrowserCommands?

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
                    PageScaffold(title: state.settingsCategory.title, colors: state.palette, subtitle: state.settingsCategory.detail) {
                        categoryContent
                    }.id(state.settingsCategory).recordLayout("settings-content")
                }
                .frame(width: max(0, geometry.size.width - navigationWidth), height: geometry.size.height)
            }
            .frame(width: geometry.size.width, height: geometry.size.height, alignment: .topLeading)
            .background(state.palette.pageBackground)
            .buttonStyle(.automatic)  // standard macOS controls, not the browser's glass
        }.recordLayout("settings")
    }

    private var navigation: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Text("Settings").font(.system(size: 20, weight: .semibold))
                    .padding(.leading, 10).padding(.top, 20).padding(.bottom, 4)
                ForEach(Array(SettingsCategory.navigationGroups.enumerated()), id: \.offset) { _, categories in
                    VStack(spacing: 2) {
                        ForEach(categories) { category in
                            SettingsNavigationRow(category: category, selected: state.settingsCategory == category, colors: state.palette) {
                                state.settingsCategory = category
                            }
                        }
                    }
                }
            }
            .padding(.horizontal, 12).padding(.vertical, 16)
        }
        .scrollIndicators(.never)
        .foregroundStyle(state.palette.text)
        .overlay(alignment: .trailing) { Color.primary.opacity(0.08).frame(width: 1) }
    }

    @ViewBuilder private var categoryContent: some View {
        switch state.settingsCategory {
        case .general:
            EngineSettingsSection(state: state)
            SiteEnginesSection(state: state)
            DefaultBrowserSection()
            PageSection(title: "Import") {
                PageRow(title: "Import from another browser", subtitle: "Bookmarks, history, open tabs and compatible cookies") {
                    Button("Import…") { state.settingsCategory = .imports }
                }
            }
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
        case .passwords:
            PasswordSettingsSection(state: state)
        case .privacy:
            TrackingProtectionSection(state: state)
            PrivacySettingsSection(state: state)
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
                Text(category.navigationTitle).font(.system(size: 13, weight: selected ? .medium : .regular)).lineLimit(1)
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
