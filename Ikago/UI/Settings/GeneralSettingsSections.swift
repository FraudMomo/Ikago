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

    var body: some View {
        PageRow(title: "“\(state.activeSpace.name)” colors") {
            HStack(spacing: 12) {
                ColorPicker("Light", selection: binding(\.light), supportsOpacity: false)
                ColorPicker("Dark", selection: binding(\.dark), supportsOpacity: false)
                Button("Reset") { withAnimation(.ikago) { state.setColors(.standard, for: state.activeSpaceID) } }
                    .controlSize(.small).disabled(state.activeSpace.resolvedColors == .standard)
            }.fixedSize()
        }
    }

    private func binding(_ key: WritableKeyPath<SpaceColors, UInt32>) -> Binding<Color> {
        Binding(get: { Color(hex: state.activeSpace.resolvedColors[keyPath: key]) },
                set: { color in
                    var colors = state.activeSpace.resolvedColors
                    colors[keyPath: key] = color.hexValue
                    state.setColors(colors, for: state.activeSpaceID)
                })
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
            PageRow(title: "Focus address bar on new tabs", subtitle: "Sidebar only. Top Bar always focuses its address field when opening a new tab.") {
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
