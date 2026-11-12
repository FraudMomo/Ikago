import SwiftUI

struct SpaceThemePicker: View {
    let state: BrowserState
    @State private var selectedSpaceID: UUID?

    private var selectedSpace: SpaceProfile { state.spaces.first { $0.id == selectedSpaceID } ?? state.activeSpace }

    var body: some View {
        PageRow(title: "Space theme", subtitle: "Choose colors for each Space") {
            VStack(alignment: .trailing, spacing: 8) {
                Picker("Space", selection: Binding(get: { selectedSpace.id }, set: { selectedSpaceID = $0 })) {
                    ForEach(state.spaces) { space in Text(space.name).tag(space.id) }
                }
                .labelsHidden().pickerStyle(.menu).fixedSize()
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
        .onAppear { if selectedSpaceID == nil { selectedSpaceID = state.activeSpaceID } }
    }
}
