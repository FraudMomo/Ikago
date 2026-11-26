import SwiftUI
import WebKit

/// The two ways to arrange the window: every tab in the sidebar, or tabs and an address bar above the page with the
/// sidebar as a rail of icons (or hidden).
enum LayoutChoice: String, CaseIterable, Identifiable {
    case sidebar, sidebarTabs
    var id: String { rawValue }
    var name: String { self == .sidebar ? "Sidebar" : "Top Tabs" }

    @MainActor func isSelected(in state: BrowserState) -> Bool {
        (state.browserPreferences.sidebarTopTabs == true) == (self == .sidebarTabs)
    }

    @MainActor func apply(to state: BrowserState) {
        LayoutSwitch.set(tabs: self == .sidebarTabs, state: state)
    }
}

/// A small window drawing of a layout, with a selection ring.
struct LayoutCard: View {
    let choice: LayoutChoice
    let selected: Bool
    let colors: Palette
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 9) {
                LayoutPreview(choice: choice, colors: colors)
                    .frame(height: 92)
                    .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .strokeBorder(Color.primary.opacity(0.1), lineWidth: 0.5))
                    .padding(3)
                    .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .strokeBorder(selected ? Color.settingsAccent : .clear, lineWidth: 2))
                Text(choice.name).font(.system(size: 12, weight: selected ? .medium : .regular))
                    .foregroundStyle(selected ? .primary : .secondary)
            }
            .frame(maxWidth: .infinity)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .animation(.ikagoQuick, value: selected)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

private struct LayoutPreview: View {
    let choice: LayoutChoice
    let colors: Palette

    var body: some View {
        let line = colors.text.opacity(0.14)
        ZStack(alignment: .topLeading) {
            colors.tint
            switch choice {
            case .sidebar:
                HStack(alignment: .top, spacing: 6) {
                    VStack(alignment: .leading, spacing: 5) {
                        lights.padding(.bottom, 3)
                        ForEach(0..<4, id: \.self) { i in
                            RoundedRectangle(cornerRadius: 2).fill(i == 1 ? colors.selected : line).frame(width: i == 1 ? 34 : 28, height: 5)
                        }
                    }
                    .frame(width: 38, alignment: .leading)
                    RoundedRectangle(cornerRadius: 5).fill(colors.pageBackground)
                }
                .padding(7)
            case .sidebarTabs:
                VStack(alignment: .leading, spacing: 0) {
                    HStack(alignment: .bottom, spacing: 4) {
                        lights.frame(height: 9)
                        UnevenRoundedRectangle(topLeadingRadius: 3, topTrailingRadius: 3).fill(colors.pageBackground)
                            .frame(width: 26, height: 9)
                        ForEach(0..<2, id: \.self) { _ in
                            RoundedRectangle(cornerRadius: 1.5).fill(line).frame(width: 16, height: 3).padding(.bottom, 3)
                        }
                    }
                    HStack(alignment: .top, spacing: 5) {
                        VStack(spacing: 4) {
                            ForEach(0..<3, id: \.self) { _ in RoundedRectangle(cornerRadius: 2).fill(line).frame(width: 7, height: 7) }
                        }
                        .padding(.top, 4)
                        UnevenRoundedRectangle(bottomLeadingRadius: 5, bottomTrailingRadius: 5, topTrailingRadius: 5)
                            .fill(colors.pageBackground)
                            .overlay(alignment: .top) {
                                Capsule().fill(line).frame(width: 46, height: 5).padding(.top, 4)
                            }
                    }
                }
                .padding(7)
            }
        }
    }

    private var lights: some View {
        HStack(spacing: 3) {
            ForEach([Color(hex: 0xFF5F57), Color(hex: 0xFEBC2E), Color(hex: 0x28C840)], id: \.self) { Circle().fill($0).frame(width: 5, height: 5) }
        }
    }
}

/// Light- and dark-mode color pickers for the active Space.
struct SpaceColorEditor: View {
    let state: BrowserState

    private var selectedSpace: SpaceProfile { state.spaces.first { $0.id == state.themeEditingSpaceID } ?? state.activeSpace }

    var body: some View {
        PageRow(title: "Custom colors", subtitle: "Set light and dark colors for a Space") {
            VStack(alignment: .trailing, spacing: 8) {
                SettingsMenu(selection: Binding(get: { selectedSpace.id }, set: { state.themeEditingSpaceID = $0 }), options: state.spaces.map { space in (space.id, space.name) })
                HStack(spacing: 8) {
                    SpaceColorPopover(title: "Light", color: binding(\.light))
                    SpaceColorPopover(title: "Dark", color: binding(\.dark))
                    Button("Reset") { withAnimation(.ikago) { state.setColors(.standard, for: selectedSpace.id) } }
                        .controlSize(.small).disabled(selectedSpace.resolvedColors == .standard)
                }
            }.fixedSize()
        }
        .onAppear { if state.themeEditingSpaceID == nil { state.themeEditingSpaceID = state.activeSpaceID } }
    }

    private func binding(_ key: WritableKeyPath<SpaceColors, UInt32>) -> Binding<Color> {
        Binding(get: { Color(hex: selectedSpace.resolvedColors[keyPath: key]) },
                set: { color in
                    var colors = selectedSpace.resolvedColors
                    colors[keyPath: key] = color.hexValue
                    state.setColors(colors, for: selectedSpace.id)
                })
    }
}

private struct SpaceColorPopover: View {
    let title: String
    @Binding var color: Color
    @State private var showing = false
    @State private var hex = ""

    var body: some View {
        Button { hex = String(format: "%06X", color.hexValue); showing = true } label: {
            HStack(spacing: 6) {
                Circle().fill(color).frame(width: 16, height: 16)
                Text(title).font(.system(size: 12))
            }.padding(.horizontal, 9).frame(height: 28)
                .background(Capsule().fill(Color.primary.opacity(0.06)))
        }
        .buttonStyle(.plain).fixedSize()
        .popover(isPresented: $showing, arrowEdge: .bottom) {
            VStack(alignment: .leading, spacing: 12) {
                Text(title).font(.system(size: 13, weight: .medium))
                LazyVGrid(columns: Array(repeating: GridItem(.fixed(24), spacing: 7), count: 7), spacing: 7) {
                    ForEach(SpaceColors.presets) { preset in
                        let value = title == "Light" ? preset.colors.light : preset.colors.dark
                        Button { color = Color(hex: value); hex = String(format: "%06X", value) } label: {
                            Circle().fill(Color(hex: value)).frame(width: 22, height: 22)
                                .overlay(Circle().strokeBorder(Color.primary.opacity(0.25), lineWidth: 1))
                        }.buttonStyle(.plain).help(preset.name)
                    }
                }
                HStack(spacing: 6) {
                    Text("#").foregroundStyle(.secondary)
                    TextField("RRGGBB", text: $hex).textFieldStyle(.roundedBorder).frame(width: 90)
                        .onChange(of: hex) { _, value in
                            let cleaned = value.trimmingCharacters(in: CharacterSet(charactersIn: "# "))
                            if cleaned.count == 6, let number = UInt32(cleaned, radix: 16) { color = Color(hex: number) }
                        }
                    Button("Done") { showing = false }.keyboardShortcut(.defaultAction)
                }
            }.padding(14).frame(width: 230)
        }
    }
}

/// What ⌘T opens: the command bar, a homepage, or an extension's new-tab page (Momentum…).
struct NewTabSection: View {
    let state: BrowserState

    var body: some View {
        let providers = NewTabProviders.current
        PageSection(title: "New Tab", footer: footer(providers)) {
            PageRow(title: "New tabs open") {
                SettingsMenu(selection: Binding(get: { state.newTabMode },
                                              set: { mode in withAnimation(.ikago) { state.newTabMode = mode } }), options: NewTabMode.allCases.map { ($0, $0.name) })
            }
            PageDivider()
            PageRow(title: "Focus address bar on new tabs") {
                Toggle("Focus address bar on new tabs", isOn: Binding(get: { state.focusAddressBarOnNewTab },
                                                                     set: { state.focusAddressBarOnNewTab = $0 }))
                    .labelsHidden().toggleStyle(.switch)
            }
            if state.newTabMode == .homepage {
                PageDivider()
                PageRow(title: "Homepage") {
                    TextField("example.com", text: Binding(get: { state.homepage }, set: { state.homepage = $0 }))
                        .textFieldStyle(.roundedBorder)
                        .frame(maxWidth: 260)
                }
                .transition(.opacity)
            }
            if state.newTabMode == .extensionPage, !providers.isEmpty {
                PageDivider()
                PageRow(title: "Extension") {
                    SettingsMenu(selection: Binding(get: { providers.contains { $0.id == state.newTabExtensionID } ? state.newTabExtensionID ?? providers[0].id : providers[0].id },
                                                  set: { state.newTabExtensionID = $0 }), options: providers.map { provider in (provider.id, provider.name) })
                }
                .transition(.opacity)
                .onAppear { if state.newTabExtensionID == nil { state.newTabExtensionID = providers[0].id } }
            }
        }
    }

    private func footer(_ providers: [NewTabProviders.Provider]) -> String? {
        switch state.newTabMode {
        case .home: "Opens Ikago Home: your bookmarks and most visited pages as tiles."
        case .commandBar: "Opens the address field, ready to type."
        case .homepage: "⌘T opens this page. ⌘L edits its address."
        case .extensionPage where providers.isEmpty:
            "No installed extension replaces the new tab page. Add one such as Momentum from the Chrome Web Store."
        case .extensionPage: "New tabs show the extension's page. Until one is set, new tabs open ready for an address."
        }
    }
}
