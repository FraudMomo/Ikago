import SwiftUI

/// One top-bar tab. The active one shows the site, reload, site info and close on hover, and
/// turns into the address field when clicked. Regular tabs retain readable titles in the scrolling
/// strip; pinned tabs use their icon (with the title in the tooltip).
struct IslandTab: View {
    let tab: TabItem
    let isActive: Bool
    let width: CGFloat
    let compact: Bool
    let height: CGFloat
    let state: BrowserState
    let chrome: ChromeModel
    let palette: CommandPaletteModel
    let colors: Palette
    let selection: Namespace.ID
    weak var commands: BrowserCommands?
    @State private var hovering = false
    @State private var showInfo = false

    private var iconOnly: Bool { tab.pinned || (compact && !isActive) }

    var body: some View {
        Group {
            if isActive && chrome.isEditingAddress(of: tab.id) {
                InlineAddressField(model: palette, fontSize: 13, alignment: .left, commands: commands)
                    .padding(.horizontal, 12)
            } else {
                label
            }
        }
        .frame(width: width, height: height)
        .recordLayout("active-tab", enabled: isActive)
        .recordLayout("regular-tab-\(tab.id)", enabled: !tab.pinned)
        .recordLayout("topbar-pin-\(tab.id)", enabled: tab.pinned)
        .background {
            if isActive { Capsule().fill(chrome.isEditingAddress(of: tab.id)
                ? AddressAppearance.background(isDark: colors.isDark) : Color(nsColor: state.topBarAddressColor)) }
            if !isActive && hovering {
                RoundedRectangle(cornerRadius: 18, style: .continuous).fill(colors.hover.opacity(1.6))
            }
        }
        .clipShape(Capsule())
        .overlay {
            // Keep focus feedback inside the capsule: scroll clipping must not square its corners.
            if isActive && chrome.isEditingAddress(of: tab.id) {
                Capsule().strokeBorder(colors.text.opacity(0.28), lineWidth: 1).allowsHitTesting(false)
            }
        }
        .overlay(alignment: .bottom) {
            PageLoadProgress(tab: tab, colors: colors).padding(.horizontal, 10)
        }
        .contentShape(Capsule())
        .background(ActiveTabScrollAnchor(active: isActive))
        .anchorPreference(key: AddressAnchorKey.self, value: .bounds) { isActive ? $0 : nil }
        .onHover { hovering = $0 }
        .onTapGesture {
            // While editing, clicks belong to the field (cursor, selection), not the tab.
            if isActive { if !chrome.inlineAddress { commands?.showCommandPalette(newTab: false) } }
            else { withAnimation(.ikago) { state.select(tab.id) } }
        }
        .animation(.ikagoQuick, value: hovering)
        // Selection and the switch into the address field stay immediate; only the strip's open/close
        // motion (widths, slots) animates.
        .animation(nil, value: isActive)
        .animation(nil, value: chrome.isEditingAddress(of: tab.id))
        .help(isActive ? "Click to edit the address" : tab.displayTitle)
    }

    @ViewBuilder private var label: some View {
        if iconOnly {
            ZStack {
                if tab.isMuted || tab.isPlayingAudio {
                    TabAudioButton(tab: tab, colors: colors, commands: commands)
                } else if isActive && tab.isLoading {
                    PageLoadButton(tab: tab, colors: colors, commands: commands)
                } else {
                    FaviconView(tab: tab, size: 13).opacity(hovering && !tab.pinned ? 0 : tab.isLoading ? 0.4 : 1)
                    if hovering && !tab.pinned { closeButton }
                }
            }
            .frame(maxWidth: .infinity)
        } else {
            HStack(spacing: 5) {
                closeButton.opacity(hovering ? 1 : 0).allowsHitTesting(hovering)
                HStack(spacing: 5) {
                    if isActive { SecurityBadge(tab: tab, colors: colors, size: 9) }
                    else { FaviconView(tab: tab, size: 14).opacity(tab.isLoading ? 0.4 : 1) }
                    Text(isActive ? tab.addressLabel : tab.displayTitle)
                        .lineLimit(1).font(.system(size: 13, weight: .regular))
                }
                .foregroundStyle(isActive ? colors.text : colors.secondary)
                .frame(maxWidth: .infinity, alignment: .center)
                TabMediaIndicators(tab: tab, colors: colors, commands: commands)
                ZStack {
                    if isActive {
                        if tab.isLoading {
                            PageLoadButton(tab: tab, colors: colors, commands: commands)
                        } else {
                            SiteInfoButton(state: state, colors: colors, commands: commands, isPresented: $showInfo,
                                           symbol: "line.3.horizontal")
                                .opacity(hovering || showInfo ? 1 : 0).allowsHitTesting(hovering || showInfo)
                        }
                    }
                }.frame(width: 22, height: 24)
            }
            .padding(.horizontal, 9)
            .background(isActive ? AnyView(ExtensionPopupAnchor()) : AnyView(EmptyView()))
        }
    }

    private var closeButton: some View {
        Button { withAnimation(.ikago) { commands?.closeTab(tab.id) } } label: {
            Image(systemName: "xmark").font(.system(size: 10, weight: .medium)).frame(width: 18, height: 24)
        }
        .buttonStyle(.plain).foregroundStyle(colors.secondary).help("Close Tab (⌘W)")
    }
}

/// The address field that replaces the active tab while editing (Integrated style).
struct InlineAddressField: View {
    @Bindable var model: CommandPaletteModel
    var fontSize: CGFloat = 12
    var alignment: NSTextAlignment = .center
    weak var commands: BrowserCommands?

    var body: some View {
        HStack(spacing: 4) {
            AddressTextField(text: $model.query, fontSize: fontSize, weight: .regular, alignment: alignment,
                             onSubmit: { model.commit() },
                             onMove: { delta in model.moveSelection(delta) },
                             onCancel: { model.cancel() }, onComplete: { model.focusNext(forward: true) },
                             completion: model.inlineCompletion, temporary: model.temporaryText,
                             onEdit: { model.userEdited($0) }, onBacktab: { model.focusNext(forward: false) },
                             onRemove: { model.removeSelected() })
            if !model.query.isEmpty { ClearButton { model.query = "" }.scaleEffect(0.85) }
            if model.mode == .currentTab, let tab = model.state.activeTab, tab.isLoading {
                PageLoadButton(tab: tab, colors: model.state.barPalette, commands: commands)
            }
        }
        .focusEffectDisabled()
        .addressInteractionRegion()
    }
}

/// A split group: one capsule with a chip per tab; glows when it is the one on screen.
struct IslandGroup: View {
    let tabs: [TabItem]
    let chipWidth: CGFloat
    let compact: Bool
    let height: CGFloat
    let state: BrowserState
    let chrome: ChromeModel
    let colors: Palette
    let selection: Namespace.ID
    weak var commands: BrowserCommands?
    @State private var hovering = false

    var body: some View {
        let shown = tabs.contains { $0.id == state.activeTabID }
        HStack(spacing: 2) {
            ForEach(tabs) { tab in
                SplitChip(tab: tab, focused: tab.id == state.activeTabID, colors: colors, compact: compact, commands: commands)
                    .frame(width: chipWidth, height: height - 2)
                    .onTapGesture { withAnimation(.ikago) { state.select(tab.id) } }
                    .tabInteractions(tab, state: state, chrome: chrome, commands: commands)
            }
        }
        .padding(.horizontal, 3)
        .frame(height: height)
        .background {
            TabSelectionHighlight(shape: Capsule(), active: shown, color: colors.selected.opacity(colors.isDark ? 1 : 0.9),
                                  selection: selection, id: "island-active")
            if !shown {
                Capsule().fill(colors.hover)
            }
        }
        .overlay {
            // Hover: an unlink button in the middle of the group.
            if hovering {
                Button { withAnimation(.ikago) { state.unsplitGroup(containing: tabs[0].id) } } label: {
                    Image(systemName: "rectangle.split.2x1.slash").font(.system(size: 10, weight: .semibold))
                        .padding(.horizontal, 7).frame(height: height - 4)
                        .background(Capsule().fill(colors.selected))
                        .overlay(Capsule().strokeBorder(colors.separator, lineWidth: 0.5))
                }
                .buttonStyle(.plain).foregroundStyle(colors.text).help("Unlink Split View")
                .transition(.scale(scale: 0.85).combined(with: .opacity))
            }
        }
        // After the overlay, so the button counts as part of the hovered area (else it flickers).
        .background(ActiveTabScrollAnchor(active: shown))
        .onHover { hovering = $0 }
        .animation(.ikagoQuick, value: hovering)
        .contextMenu {
            Button("Separate Tabs") { withAnimation(.ikago) { state.unsplitGroup(containing: tabs[0].id) } }
            Button("Rotate Split") { withAnimation(.ikago) { state.toggleSplitOrientation() } }
        }
    }
}

