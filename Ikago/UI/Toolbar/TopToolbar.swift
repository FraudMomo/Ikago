import SwiftUI

/// The toolbar keeps the address field centered whenever the controls leave room.
struct TopToolbar: View {
    let state: BrowserState
    let chrome: ChromeModel
    let palette: CommandPaletteModel
    weak var commands: BrowserCommands?

    var body: some View {
        let colors = state.topBarPalette
        let height = state.topToolbarHeight
        let capsule = BrowserState.topBarControlHeight(in: height)
        GeometryReader { geometry in
            let automatic = (DownloadCenter.shared.showsToolbarButton || chrome.showDownloads)
                && !state.chromeLayout.contains(.downloads, inTopBar: true)
            let layout = TopToolbarLayout(leading: state.chromeLayout.topBarOuterLeading + state.chromeLayout.topBarLeading,
                trailing: state.chromeLayout.topBarTrailing + state.chromeLayout.topBarOuterTrailing + (automatic ? [.downloads] : []),
                available: geometry.size.width)
            ZStack {
                HStack(spacing: 2) {
                    Color.clear.frame(width: 80, height: capsule)
                    if !layout.leading.isEmpty {
                        GlassControlGroup(colors: colors, height: capsule) {
                            HStack(spacing: 2) { ForEach(layout.leading) { item in control(item, colors: colors) } }
                        }
                    }
                    WindowDragArea().frame(minWidth: 0, maxWidth: .infinity)
                    if !layout.trailing.isEmpty {
                        GlassControlGroup(colors: colors, height: capsule) {
                            HStack(spacing: 2) { ForEach(layout.trailing) { item in control(item, colors: colors) } }
                        }
                    }
                    if !layout.overflow.isEmpty {
                        ChromeOverflowMenu(items: layout.overflow, state: state, colors: colors, size: 28, commands: commands)
                    }
                }.padding(.horizontal, 8)
                TopAddressField(state: state, chrome: chrome, palette: palette, colors: colors, commands: commands)
                    .frame(width: layout.addressWidth)
                    .position(x: layout.addressCenter, y: height / 2)
            }
            .frame(width: geometry.size.width, height: height)
        }
        .frame(height: height)
        .recordLayout("top-toolbar")
        .recordLayout("connected-tab-row", enabled: !state.topBarShowsTabStrip)
        // Like the sidebar: every bit of empty toolbar behind the controls moves the window.
        .background(WindowDragArea())
    }

    private func control(_ item: ChromeItem, colors: Palette) -> some View {
        ChromeItemView(item: item, state: state, colors: colors, commands: commands, size: 28).frame(width: 28, height: 28)
    }
}

struct TopToolbarLayout {
    var leading: [ChromeItem]
    var trailing: [ChromeItem]
    var overflow: [ChromeItem] = []
    let available: CGFloat
    private var left: CGFloat { 96 + CGFloat(leading.count) * 30 }
    private var right: CGFloat { 16 + CGFloat(trailing.count + (overflow.isEmpty ? 0 : 1)) * 30 }
    var addressWidth: CGFloat { max(0, min(500, available - left - right - 8)) }
    var addressCenter: CGFloat { min(max(available / 2, left + 4 + addressWidth / 2), available - right - 4 - addressWidth / 2) }

    init(leading: [ChromeItem], trailing: [ChromeItem], available: CGFloat) {
        self.leading = leading; self.trailing = trailing; self.available = available
        while addressWidth < min(180, max(120, available * 0.34)) && (!self.leading.isEmpty || !self.trailing.isEmpty) {
            if let item = self.trailing.popLast() { overflow.insert(item, at: 0) }
            else if let item = self.leading.popLast() { overflow.insert(item, at: 0) }
        }
    }
}

/// The top-bar address field: centred domain at rest; page menu and reload fade in on hover;
/// editing left-aligns the full address on an opaque field with a subtle inset focus outline.
struct TopAddressField: View {
    let state: BrowserState
    let chrome: ChromeModel
    let palette: CommandPaletteModel
    let colors: Palette
    weak var commands: BrowserCommands?
    @State private var hovering = false
    @State private var showInfo = false

    private var editing: Bool { chrome.isEditingAddress(of: state.activeTabID) }

    var body: some View {
        let controls = (hovering || showInfo) && !editing
        HStack(spacing: 4) {
            PrivateBadge(state: state, colors: colors)
            SiteInfoButton(state: state, colors: colors, commands: commands, isPresented: $showInfo, symbol: "line.3.horizontal")
                .opacity(controls ? 1 : 0).allowsHitTesting(controls)
            if editing {
                InlineAddressField(model: palette, fontSize: 13, alignment: .left, commands: commands)
            } else {
                Button { commands?.showCommandPalette(newTab: false) } label: {
                    HStack(spacing: 5) {
                        Spacer(minLength: 0)
                        if let tab = state.activeTab { SecurityBadge(tab: tab, colors: colors, size: 9) }
                        Text(state.activeTab?.addressLabel ?? "Search or enter website name").lineLimit(1)
                            .font(.system(size: 13, weight: .regular))
                            .foregroundStyle(state.activeTab == nil ? colors.secondary : colors.text)
                        Spacer(minLength: 0)
                    }.frame(maxWidth: .infinity, maxHeight: .infinity).contentShape(Rectangle())
                }.buttonStyle(.plain).accessibilityLabel("Address field")
            }
            if let tab = state.activeTab, !editing {
                PageLoadButton(tab: tab, colors: colors, commands: commands).frame(width: 22)
                    .opacity(controls || tab.isLoading ? 1 : 0).allowsHitTesting(controls || tab.isLoading)
            }
        }
        .padding(.horizontal, 6).frame(height: 32)
        .background(Capsule().fill(fill))
        .overlay(Capsule().strokeBorder(colors.separator.opacity(editing ? 0 : 0.7), lineWidth: 0.5))
        .clipShape(Capsule())
        .overlay { if editing { Capsule().strokeBorder(colors.text.opacity(0.28), lineWidth: 1).allowsHitTesting(false) } }
        .overlay(alignment: .bottom) { PageLoadProgress(tab: state.activeTab, colors: colors).padding(.horizontal, 12) }
        .background(ExtensionPopupAnchor())
        .anchorPreference(key: AddressAnchorKey.self, value: .bounds) { $0 }
        .onHover { hovering = $0 }
        .animation(.easeOut(duration: 0.15), value: controls)
        .animation(.easeOut(duration: 0.15), value: editing)
        .addressInteractionRegion()
        .recordLayout("top-address")
        .help("Search or enter website name (⌘L)")
    }

    private var fill: Color {
        if editing { return AddressAppearance.background(isDark: colors.isDark) }
        let base = state.topBarAddressColor
        let rest = base.blended(withFraction: colors.isDark ? 0.25 : 0.35, of: state.topBarChromeTint) ?? base
        return Color(nsColor: hovering ? base : rest)
    }
}
