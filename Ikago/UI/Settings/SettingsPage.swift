import SwiftUI

enum SettingsCategory: String, CaseIterable, Identifiable {
    case general, appearance, toolbar, tabs, search, extensions, history, security, passwords, imports, about
    var id: String { rawValue }
    var title: String {
        switch self {
        case .general: "General"
        case .appearance: "Appearance"
        case .toolbar: "Sidebar & Toolbar"
        case .tabs: "Tabs & Links"
        case .search: "Search"
        case .extensions: "Extensions"
        case .history: "History"
        case .security: "Privacy & Security"
        case .passwords: "Passwords"
        case .imports: "Import"
        case .about: "About"
        }
    }
    static var navigationGroups: [[Self]] {
        [[.general, .appearance, .toolbar, .tabs, .search], [.security, .passwords, .extensions, .history], [.imports, .about]]
    }
    var symbol: String {
        switch self {
        case .general: "gearshape"
        case .appearance: "paintpalette"
        case .toolbar: "sidebar.left"
        case .tabs: "square.on.square"
        case .search: "magnifyingglass"
        case .extensions: "puzzlepiece.extension"
        case .history: "clock.arrow.circlepath"
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
                        HStack(spacing: 10) {
                            SettingsCategoryMenu(state: state)
                            Spacer(minLength: 0)
                        }
                        .padding(.horizontal, 16).padding(.top, 14).padding(.bottom, 2)
                    }
                    PageScaffold(title: state.settingsCategory.title, colors: state.palette, scrollTarget: target,
                                 settingsCategory: state.settingsCategory, background: SettingsColors.page(state.palette)) {
                        subpageContent
                    }
                    .environment(\.settingsSurface, true)
                    .environment(\.settingsHighlight, highlight)
                    .id(state.settingsCategory).recordLayout("settings-content")
                }
                .frame(width: max(0, geometry.size.width - navigationWidth), height: geometry.size.height)
            }
            .frame(width: geometry.size.width, height: geometry.size.height, alignment: .topLeading)
            .background(SettingsColors.page(state.palette))
            .buttonStyle(SettingsButtonStyle())  // Settings' own buttons, not the browser's glass or stock blue text
            .tint(SettingsColors.accent(state.palette))
            .environment(\.pagePalette, state.palette)
        }.recordLayout("settings")
        .onAppear(perform: openPending)
        .onChange(of: state.pendingSettingsSection) { _, _ in openPending() }
    }

    private var navigation: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Settings").font(.system(size: 15, weight: .semibold))
                .padding(.leading, 8).padding(.top, 22).padding(.bottom, 2)
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
        // A quieter column beside the page, as in Mail and Notes.
        .background(Color(nsColor: state.isDark ? NSColor(hex: 0x19191B) : NSColor(hex: 0xF7F7F8)))
        .overlay(alignment: .trailing) { Color.primary.opacity(0.07).frame(width: 1) }
    }

    private var categories: some View {
        VStack(alignment: .leading, spacing: 14) {
            ForEach(Array(SettingsCategory.navigationGroups.enumerated()), id: \.offset) { index, categories in
                VStack(alignment: .leading, spacing: 1) {
                    if let heading = SettingsCategory.navigationGroupTitles[safe: index], !heading.isEmpty {
                        Text(heading).font(.system(size: 11, weight: .semibold)).foregroundStyle(state.palette.tertiary)
                            .padding(.leading, 8).padding(.bottom, 4)
                    }
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

    /// A section the address field asked for (`BrowserState.pendingSettingsSection`), once.
    private func openPending() {
        guard let section = state.pendingSettingsSection else { return }
        state.pendingSettingsSection = nil
        if let entry = SettingsSearch.index.first(where: { $0.category == state.settingsCategory && $0.section == section }) { open(entry) }
    }

    /// Opens a result's page at its section and outlines the section for a moment.
    private func open(_ entry: SettingsSearchEntry) {
        state.settingsCategory = entry.category
        if let page = entry.category.subpage(containing: entry.section) { state.settingsSubpage[entry.category] = page.title }
        target = entry.section
        highlight = entry.section
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(1.4))
            if highlight == entry.section { highlight = nil }
        }
    }

    /// The category's sub-page bar, then the chosen sub-page's sections (all of them where there's only one page).
    @ViewBuilder private var subpageContent: some View {
        let category = state.settingsCategory
        let pages = category.subpages
        let current = pages.first { $0.title == state.settingsSubpage[category] } ?? pages.first
        if pages.count > 1, let current {
            SettingsSubnav(pages: pages, selection: Binding(get: { current.title }, set: { state.settingsSubpage[category] = $0 }),
                           colors: state.palette)
                .padding(.bottom, 6)
        }
        VStack(alignment: .leading, spacing: 22) { categoryContent }
            .environment(\.settingsVisibleSections, current?.sections)
            .id(current?.title ?? "")
            .transition(.opacity.combined(with: .offset(y: 6)))
    }

    @ViewBuilder private var categoryContent: some View {
        switch state.settingsCategory {
        case .general:
            EngineSettingsSection(state: state)
            SiteEnginesSection(state: state)
            DefaultBrowserSection()
            PageIntelligenceSection(state: state)
        case .search:
            SearchSettingsSection(state: state)
        case .appearance:
            PageSection(title: "Layout") {
                HStack(spacing: 14) {
                    ForEach(LayoutChoice.allCases) { choice in
                        LayoutCard(choice: choice, selected: choice.isSelected(in: state), colors: state.palette) { choice.apply(to: state) }
                    }
                }.padding(.vertical, 16)
            }
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
            PeekSettingsSection(state: state)
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
        case .history:
            HistoryBrowser(state: state, commands: commands)
        case .security:
            PageSection(title: "Status") { SecurityDashboard(state: state) }
            SecuritySettingsSection(state: state)
            TrackingProtectionSection(state: state)
            PrivacySettingsSection(state: state, commands: commands)
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
            HStack(spacing: 9) {
                Image(systemName: category.symbol).font(.system(size: 13, weight: .regular))
                    .frame(width: 18)
                    .foregroundStyle(selected ? colors.text : colors.secondary)
                Text(category.title).font(.system(size: 13, weight: selected ? .medium : .regular)).lineLimit(1)
                Spacer(minLength: 0)
            }
            .foregroundStyle(selected ? colors.text : colors.text.opacity(0.8))
            .padding(.horizontal, 8).frame(height: 32)
            .background(RoundedRectangle(cornerRadius: Radius.control, style: .continuous)
                .fill(Color.primary.opacity(selected ? 0.075 : hovering ? 0.04 : 0)))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}
