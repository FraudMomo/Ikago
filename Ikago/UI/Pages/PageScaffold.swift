import SwiftUI

/// Picks the SwiftUI page for a ikago:// tab.
struct InternalPageView: View {
    let page: InternalPage
    let state: BrowserState
    weak var commands: BrowserCommands?
    var tabID: String? = nil

    var body: some View {
        let colors = state.palette
        Group {
            switch page {
            case .performance: PerformancePage(state: state, commands: commands, tabID: tabID)
            case .splitEmpty: EmptySplitPage(state: state, tabID: tabID)
            case .bookmarks: BookmarksPage(state: state, commands: commands)
            case .settings: SettingsPage(state: state, commands: commands)
            case .history: HistoryPage(state: state, commands: commands)
            case .downloads: DownloadsPage(colors: colors)
            case .notes: NotesPage(state: state)
            case .welcome: WelcomePage(state: state, commands: commands, tabID: tabID)
            case .home: HomePage(state: state, commands: commands)
            }
        }
        .environment(\.colorScheme, colors.isDark ? .dark : .light)
        .environment(\.pagePalette, colors)
        .glassButtons(colors.glass)
        .tint(colors.accent)
    }
}

/// Shared page layout: a large title and a centred, readable-width column with generous space around it.
struct PageScaffold<Content: View>: View {
    let title: String
    let colors: Palette
    var subtitle: String? = nil
    var trailing: AnyView? = nil
    /// A `PageSection` title to scroll to, such as a Settings search result.
    var scrollTarget: String? = nil
    var settingsCategory: SettingsCategory? = nil
    /// Behind the page; the palette's page color when nil.
    var background: Color? = nil
    @ViewBuilder let content: Content

    var body: some View {
        GeometryReader { geometry in
            let inset: CGFloat = geometry.size.width < 480 ? 16 : 32
            let width = max(0, min(settingsCategory == nil ? 680 : 700, geometry.size.width - inset * 2))
            ScrollViewReader { proxy in
                ScrollView(.vertical) {
                    VStack(alignment: .leading, spacing: settingsCategory == nil ? 28 : 18) {
                        if let settingsCategory {
                            SettingsCategoryHeader(category: settingsCategory, colors: colors)
                        } else {
                            VStack(alignment: .leading, spacing: 6) {
                                HStack(alignment: .firstTextBaseline) {
                                    Text(title).font(.system(size: 26, weight: .semibold))
                                        .foregroundStyle(colors.text).minimumScaleFactor(0.7).lineLimit(1)
                                    Spacer(minLength: 8)
                                    trailing
                                }
                                if let subtitle {
                                    Text(subtitle).font(.system(size: 13)).foregroundStyle(colors.secondary)
                                        .fixedSize(horizontal: false, vertical: true)
                                }
                            }
                        }
                        content
                    }
                    .frame(width: width, alignment: .leading)
                    .padding(.top, 36).padding(.bottom, 48)
                    .frame(width: geometry.size.width, alignment: .top)
                }
                .onAppear { reveal(proxy) }
                .onChange(of: scrollTarget) { reveal(proxy) }
            }
            .frame(width: geometry.size.width, height: geometry.size.height)
            .background(background ?? colors.pageBackground)
        }
    }

    private func reveal(_ proxy: ScrollViewProxy) {
        guard let scrollTarget else { return }
        DispatchQueue.main.async { withAnimation(.ikago) { proxy.scrollTo(scrollTarget, anchor: .top) } }
    }
}

/// A group of rows under a small, quiet heading: on a soft panel in pages, as flat hairline-divided rows in Settings.
struct PageSection<Content: View>: View {
    let title: String
    var symbol: String? = nil
    var footer: String? = nil
    @ViewBuilder let content: Content
    @Environment(\.settingsHighlight) private var highlight
    @Environment(\.settingsSurface) private var settingsSurface
    @Environment(\.settingsVisibleSections) private var visibleSections
    @Environment(\.pagePalette) private var palette
    @Environment(\.colorScheme) private var scheme

    private var shape: RoundedRectangle { RoundedRectangle(cornerRadius: Radius.card, style: .continuous) }

    var body: some View {
        if let visibleSections, !visibleSections.contains(title) {
            EmptyView()  // on another sub-page (`SettingsSubpage`)
        } else if settingsSurface { card } else { panel }
    }

    /// Settings: a heading above a card lifted off the page, rows divided by hairlines inside it; the footer under it.
    /// The headings sit outside the cards, larger than the rows, so a page can be scanned by them.
    private var card: some View {
        let dark = scheme == .dark
        let shape = RoundedRectangle(cornerRadius: 14, style: .continuous)
        return VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.system(size: 15, weight: .semibold)).foregroundStyle(.primary)
                .padding(.leading, 4)
                .accessibilityAddTraits(.isHeader)
            VStack(alignment: .leading, spacing: 0) {
                VStack(spacing: 0) { content }
            }
            .padding(.horizontal, 18).padding(.vertical, 2)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(shape.fill(palette.map(SettingsColors.card) ?? (dark ? Color(hex: 0x222325) : .white)))
            .overlay(shape.strokeBorder(dark ? Color.white.opacity(0.06) : Color.black.opacity(0.06), lineWidth: 0.5))
            .shadow(color: .black.opacity(dark ? 0.25 : 0.05), radius: 6, y: 2)
            .overlay(shape.strokeBorder(Color.settingsAccent, lineWidth: 2).opacity(highlight == title ? 1 : 0))
            .animation(.easeOut(duration: 0.6), value: highlight == title)
            if let footer {
                Text(footer).font(.system(size: 12)).foregroundStyle(.secondary).lineSpacing(1)
                    .fixedSize(horizontal: false, vertical: true).padding(.horizontal, 4)
            }
        }
        .padding(.top, 4)
        .id(title)
    }

    private var panel: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                if let symbol = symbol ?? Self.symbol(for: title) {
                    Image(systemName: symbol).font(.system(size: 10, weight: .medium)).frame(width: 12)
                }
                Text(title).font(.system(size: 12, weight: .medium))
            }
            .foregroundStyle(.secondary).padding(.leading, 4)
            VStack(spacing: 0) { content }
                .background(shape.fill(Color.primary.opacity(0.045)))
                .clipShape(shape)
                .overlay(shape.strokeBorder(Color.accentColor, lineWidth: 2).opacity(highlight == title ? 1 : 0))
                .animation(.easeOut(duration: 0.6), value: highlight == title)
            if let footer {
                Text(footer).font(.system(size: 12)).foregroundStyle(.secondary).lineSpacing(1)
                    .fixedSize(horizontal: false, vertical: true).padding(.horizontal, 4)
            }
        }
        .id(title)
    }

    private static func symbol(for title: String) -> String? {
        switch title {
        case "Search & Address Bar", "Suggestions": "magnifyingglass"
        case "Browsing Data", "History": "clock.arrow.circlepath"
        case "Ikago", "About": "info.circle"
        case "Developer": "hammer"
        case "Extension Updates", "Extensions", "Add Extensions", "Installed": "puzzlepiece.extension"
        case "Layout": "rectangle.split.2x1"
        case "Status": "checkmark.shield"
        case "Color & Theme", "Space theme": "paintpalette"
        case "Materials": "square.3.layers.3d"
        case "Tab Animations": "arrow.left.arrow.right"
        case "Full Screen": "arrow.up.left.and.arrow.down.right"
        case "Secure Connections": "lock.shield"
        case "Website Safety": "exclamationmark.shield"
        case "Tracking Protection": "eye.slash"
        case "Downloads": "arrow.down.circle"
        case "AutoFill", "Saved in Ikago": "key"
        case "Import", "Import Complete": "square.and.arrow.down"
        case "Default Browser": "globe"
        case "Engine by Site", "Browser Engine", "Chromium": "globe"
        case "Customize", "Sidebar Essentials", "Pinned Essentials", "Bookmarks Bar": "slider.horizontal.3"
        case "New Tab", "Tab Placement", "Opening Bookmarks", "Background Tabs": "plus.square.on.square"
        case "Tab Groups": "folder"
        default: nil
        }
    }
}

/// One row in a PageSection: label on the left, a small control on the right.
struct PageRow<Trailing: View>: View {
    let title: String
    var subtitle: String? = nil
    /// A drawing of what the setting changes, in the same place on every row: before the title (`SettingFigures`).
    var figure: AnyView? = nil
    @ViewBuilder let trailing: Trailing
    @Environment(\.settingsSurface) private var settingsSurface

    var body: some View {
        // Label beside the control; in a narrow window the control drops under the label.
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 12) {
                // A small ideal width lets long subtitles wrap instead of pushing the control below.
                label.frame(minWidth: 200, idealWidth: 200, maxWidth: .infinity, alignment: .leading)
                trailing.controlSize(.small)
            }
            VStack(alignment: .leading, spacing: 6) {
                label
                trailing.controlSize(.small)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, settingsSurface ? 0 : 16)
        .padding(.vertical, settingsSurface ? 14 : 10)
        .frame(minHeight: settingsSurface ? 56 : 44)
    }

    private var label: some View {
        HStack(spacing: 14) {
            if let figure { figure }
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.system(size: 13, weight: settingsSurface ? .medium : .regular))
                if let subtitle { Text(subtitle).font(.system(size: 12)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true) }
            }
        }
    }
}

/// A row with a slider, its value and a Reset button that appears once it differs from the default.
struct SliderRow: View {
    let title: String
    var subtitle: String? = nil
    @Binding var value: Double
    let range: ClosedRange<Double>
    let defaultValue: Double
    var step = 1.0
    var format: (Double) -> String = { "\(Int($0)) pt" }
    /// A drawing of what the value changes (Settings), before the slider.
    var figure: AnyView? = nil

    var body: some View {
        PageRow(title: title, subtitle: subtitle, figure: figure) {
            HStack(spacing: 10) {
                Slider(value: Binding(get: { value }, set: { value = ($0 / step).rounded() * step }), in: range)
                    .frame(minWidth: 140, maxWidth: 240)
                Text(format(value)).font(.system(size: 12).monospacedDigit()).foregroundStyle(.secondary)
                    .frame(width: 48, alignment: .trailing)
                if value != defaultValue {
                    Button("Reset") { withAnimation(.ikago) { value = defaultValue } }
                        .controlSize(.small)
                        .transition(.opacity)
                }
            }
        }
    }
}

struct PageDivider: View {
    @Environment(\.settingsSurface) private var settingsSurface
    var body: some View {
        Rectangle().fill(Color.primary.opacity(settingsSurface ? 0.06 : 0.08)).frame(height: 1).padding(.leading, settingsSurface ? 0 : 16)
    }
}
