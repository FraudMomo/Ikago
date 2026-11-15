import SwiftUI

// MARK: - Appearance mode picker

/// Small window previews make the appearance choice readable before selecting it.
struct AppearanceModePicker: View {
    let state: BrowserState
    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 10) {
                ForEach(ColorMode.allCases) { mode in
                    Button { state.colorMode = mode } label: {
                        VStack(spacing: 6) {
                            ZStack(alignment: .bottomLeading) {
                                preview(mode)
                                if state.colorMode == mode {
                                    Image(systemName: "checkmark.circle.fill").font(.system(size: 12, weight: .semibold))
                                        .foregroundStyle(.white, Color.settingsAccent).padding(4)
                                }
                            }.frame(width: 68, height: 45)
                                .clipShape(RoundedRectangle(cornerRadius: Radius.control))
                                .padding(3)
                                .overlay(RoundedRectangle(cornerRadius: Radius.row).strokeBorder(state.colorMode == mode ? Color.settingsAccent : Color.primary.opacity(0.12), lineWidth: state.colorMode == mode ? 1.5 : 0.7))
                            Text(mode.name).font(.system(size: 11, weight: state.colorMode == mode ? .medium : .regular))
                                .foregroundStyle(state.colorMode == mode ? .primary : .secondary)
                        }.contentShape(Rectangle())
                    }.buttonStyle(.plain).accessibilityLabel(mode.name)
                        .accessibilityAddTraits(state.colorMode == mode ? .isSelected : [])
                }
            }.fixedSize()
            SettingsMenu(selection: Binding(get: { state.colorMode }, set: { state.colorMode = $0 }), options: ColorMode.allCases.map { ($0, $0.name) })
        }
    }

    private func preview(_ mode: ColorMode) -> some View {
        HStack(spacing: 0) {
            if mode != .dark { window(dark: false) }
            if mode != .light { window(dark: true) }
        }
    }
    private func window(dark: Bool) -> some View {
        VStack(spacing: 3) {
            HStack(spacing: 2) {
                ForEach(0..<3) { _ in Circle().fill(Color.gray.opacity(0.5)).frame(width: 2, height: 2) }
                Spacer(minLength: 0)
            }.padding(.horizontal, 4).frame(height: 6)
            HStack(spacing: 3) {
                VStack(spacing: 3) {
                    ForEach(0..<3) { _ in Capsule().fill(Color.gray.opacity(0.3)).frame(height: 2) }
                    Spacer(minLength: 0)
                }.frame(width: 10)
                RoundedRectangle(cornerRadius: 3).fill(dark ? Color(white: 0.25) : .white)
            }.padding([.horizontal, .bottom], 4)
        }.background(dark ? Color(white: 0.16) : Color(white: 0.91))
    }
}

// MARK: - Space theme picker

struct SpaceThemePicker: View {
    let state: BrowserState

    private var selectedSpace: SpaceProfile { state.spaces.first { $0.id == state.themeEditingSpaceID } ?? state.activeSpace }

    var body: some View {
        PageRow(title: "Space theme", subtitle: "Choose colors for each Space") {
            VStack(alignment: .trailing, spacing: 8) {
                SettingsMenu(selection: Binding(get: { selectedSpace.id }, set: { state.themeEditingSpaceID = $0 }), options: state.spaces.map { space in (space.id, space.name) })
                ScrollView(.horizontal) {
                    HStack(spacing: 8) {
                        ForEach(SpaceColors.presets) { preset in
                            Button { withAnimation(.ikago) { state.setColors(preset.colors, for: selectedSpace.id) } } label: {
                                Circle().fill(Color(hex: state.isDark ? preset.colors.dark : preset.colors.light))
                                    .frame(width: 28, height: 28)
                                    .overlay(Circle().strokeBorder(selectedSpace.resolvedColors == preset.colors ? state.palette.text : state.palette.separator, lineWidth: 2))
                                    .padding(2)
                            }.buttonStyle(.plain).help(preset.name).accessibilityLabel(preset.name)
                        }
                    }
                }.scrollIndicators(.never).frame(maxWidth: 260)
            }
        }
        .onAppear { if state.themeEditingSpaceID == nil { state.themeEditingSpaceID = state.activeSpaceID } }
    }
}
