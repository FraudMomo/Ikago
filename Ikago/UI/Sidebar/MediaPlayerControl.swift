import SwiftUI

/// Consistent hit targets and feedback inside the black media island. Only Play/Pause has a larger surface.
struct MediaPlayerControl: View {
    let symbol: String
    let label: String
    let font: CGFloat
    var prominent = false
    let action: () -> Void
    @Environment(\.isEnabled) private var enabled
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: font, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: prominent ? 44 : 36, height: prominent ? 44 : 36)
                .contentShape(Circle())
        }
        .buttonStyle(PressStyle(prominent: prominent, hovering: hovering && enabled))
        .opacity(enabled ? 1 : 0.3)
        .onHover { hovering = $0 }
        .animation(reduceMotion ? nil : .ikagoQuick, value: hovering)
        .help(label).accessibilityLabel(label)
    }

    private struct PressStyle: ButtonStyle {
        let prominent: Bool
        let hovering: Bool

        func makeBody(configuration: Configuration) -> some View {
            configuration.label
                .background(Circle().fill(.white.opacity(configuration.isPressed ? 0.2 : hovering ? 0.14 : prominent ? 0.08 : 0)))
        }
    }
}
