import SwiftUI

/// Consistent hit targets and feedback inside the media island. Only Play/Pause has a larger surface; `compact` controls
/// sit in the island's resting row.
struct MediaPlayerControl: View {
    let symbol: String
    let label: String
    let font: CGFloat
    var prominent = false
    var compact = false
    let action: () -> Void
    @Environment(\.isEnabled) private var enabled
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: font, weight: .semibold))
                .foregroundStyle(.primary)
                .frame(width: compact ? 28 : prominent ? 40 : 32, height: compact ? 28 : prominent ? 40 : 32)
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
                .background(Circle().fill(.primary.opacity(configuration.isPressed ? 0.16 : hovering ? 0.1 : prominent ? 0.07 : 0)))
        }
    }
}
