import SwiftUI
import WebKit

/// A selectable miniature of the Sidebar or Top Bar layout.
struct LayoutCard: View {
    let layout: TabLayout
    let selected: Bool
    let colors: Palette
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 10) {
                ZStack {
                    RoundedRectangle(cornerRadius: 10, style: .continuous).fill(colors.tint)
                    if layout == .vertical {
                        HStack(spacing: 5) {
                            VStack(spacing: 4) {
                                ForEach(0..<4, id: \.self) { i in
                                    RoundedRectangle(cornerRadius: 3).fill(i == 1 ? colors.selected : colors.hover.opacity(2)).frame(height: 8)
                                }
                                Spacer()
                            }
                            .frame(width: 40)
                            RoundedRectangle(cornerRadius: 6).fill(colors.pageBackground)
                        }
                        .padding(7)
                    } else {
                        VStack(spacing: 4) {
                            RoundedRectangle(cornerRadius: 4).fill(colors.hover).frame(height: 18)
                                .overlay(alignment: .leading) {
                                    RoundedRectangle(cornerRadius: 3).fill(colors.selected).frame(width: 48, height: 10).padding(.leading, 18)
                                }
                            HStack(spacing: 3) {
                                ForEach(0..<3, id: \.self) { i in RoundedRectangle(cornerRadius: 3).fill(i == 1 ? colors.selected : colors.hover).frame(height: 10) }
                            }
                            RoundedRectangle(cornerRadius: 6).fill(colors.pageBackground)
                        }
                        .padding(7)
                    }
                }
                .frame(height: 96)
                .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(selected ? colors.accent : Color.primary.opacity(0.08), lineWidth: selected ? 2 : 1)
                    .padding(-3))
                Text(layout.name).font(.system(size: 13, weight: selected ? .semibold : .regular))
            }
            .frame(maxWidth: .infinity)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .animation(.ikagoQuick, value: selected)
    }
}

/// Light- and dark-mode color pickers for the active Space.
struct SpaceColorEditor: View {
    let state: BrowserState
    @State private var selectedSpaceID: UUID?

    private var selectedSpace: SpaceProfile { state.spaces.first { $0.id == selectedSpaceID } ?? state.activeSpace }

    var body: some View {
        PageRow(title: "Custom colors", subtitle: "Set light and dark colors for a Space") {
            VStack(alignment: .trailing, spacing: 8) {
                Picker("Space", selection: Binding(get: { selectedSpace.id }, set: { selectedSpaceID = $0 })) {
                    ForEach(state.spaces) { space in Text(space.name).tag(space.id) }
                }
                .labelsHidden().pickerStyle(.menu).fixedSize()
                HStack(spacing: 8) {
                    SpaceColorPopover(title: "Light", color: binding(\.light))
                    SpaceColorPopover(title: "Dark", color: binding(\.dark))
                    Button("Reset") { withAnimation(.ikago) { state.setColors(.standard, for: selectedSpace.id) } }
                        .controlSize(.small).disabled(selectedSpace.resolvedColors == .standard)
                }
            }.fixedSize()
        }
        .onAppear { if selectedSpaceID == nil { selectedSpaceID = state.activeSpaceID } }
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
        .buttonStyle(.plain)
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
                Picker("", selection: Binding(get: { state.newTabMode },
                                              set: { mode in withAnimation(.ikago) { state.newTabMode = mode } })) {
                    ForEach(NewTabMode.allCases) { Text($0.name).tag($0) }
                }
                .pickerStyle(.menu).labelsHidden()
            }
            PageDivider()
            PageRow(title: "Focus address bar on new tabs", subtitle: "Sidebar layout only") {
                Toggle("Focus address bar on new tabs", isOn: Binding(get: { state.focusAddressBarOnNewTab },
                                                                     set: { state.focusAddressBarOnNewTab = $0 }))
                    .labelsHidden().toggleStyle(.switch).disabled(state.tabLayout.usesTopTabs)
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
                    Picker("", selection: Binding(get: { providers.contains { $0.id == state.newTabExtensionID } ? state.newTabExtensionID ?? providers[0].id : providers[0].id },
                                                  set: { state.newTabExtensionID = $0 })) {
                        ForEach(providers) { provider in Text(provider.name).tag(provider.id) }
                    }
                    .labelsHidden().fixedSize()
                }
                .transition(.opacity)
                .onAppear { if state.newTabExtensionID == nil { state.newTabExtensionID = providers[0].id } }
            }
        }
    }

    private func footer(_ providers: [NewTabProviders.Provider]) -> String? {
        switch state.newTabMode {
        case .commandBar: "Sidebar opens the command bar. Top Bar creates a new tab with the address field ready to type."
        case .homepage: "⌘T opens this page. ⌘L edits its address."
        case .extensionPage where providers.isEmpty:
            "No installed extension replaces the new tab page. Add one such as Momentum from the Chrome Web Store."
        case .extensionPage: "New tabs show the extension's page. Until one is set, new tabs open ready for an address."
        }
    }
}
