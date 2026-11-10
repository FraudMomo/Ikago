import SwiftUI

struct SpaceThemePicker: View {
    let state: BrowserState
    var body: some View {
        PageRow(title: "Space theme", subtitle: "For “\(state.activeSpace.name)”") {
            ScrollView(.horizontal) {
                HStack(spacing: 8) {
                    ForEach(SpaceColors.presets) { preset in
                        Button { withAnimation(.ikago) { state.setColors(preset.colors, for: state.activeSpaceID) } } label: {
                            Circle().fill(Color(hex: state.isDark ? preset.colors.dark : preset.colors.light))
                                .frame(width: 28, height: 28)
                                .overlay(Circle().strokeBorder(state.activeSpace.resolvedColors == preset.colors ? state.palette.text : state.palette.separator, lineWidth: 2))
                                .padding(2)
                        }.buttonStyle(.plain).help(preset.name).accessibilityLabel(preset.name)
                    }
                }
            }.scrollIndicators(.never).frame(maxWidth: 260)
        }
    }
}
