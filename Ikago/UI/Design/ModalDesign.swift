import SwiftUI

/// Shared window-integrated cards: a material surface, crisp rim and quiet native depth.
extension View {
    func modalCard(_ colors: Palette, width: CGFloat) -> some View {
        padding(24).frame(width: width).modalSurface(colors)
    }

    func modalSurface(_ colors: Palette) -> some View {
        let shape = RoundedRectangle(cornerRadius: 22, style: .continuous)
        return surface(shape, colors)
            .overlay(shape.strokeBorder(LinearGradient(colors: [
                .white.opacity(colors.isDark ? 0.16 : 0.8), colors.separator
            ], startPoint: .topLeading, endPoint: .bottomTrailing), lineWidth: 0.7).allowsHitTesting(false))
            .background {
                CardShadow(shape: shape, color: .black.opacity(colors.isDark ? 0.3 : 0.13), radius: 28, y: 14)
            }
    }

    func modalInput(_ colors: Palette) -> some View {
        textFieldStyle(.plain).font(.system(size: 15))
            .padding(.horizontal, 13).padding(.vertical, 12)
            .background(RoundedRectangle(cornerRadius: 11).fill(colors.hover))
            .overlay(RoundedRectangle(cornerRadius: 11).strokeBorder(colors.separator, lineWidth: 0.7))
    }
}

struct ModalHeading: View {
    let title: String
    var subtitle: String? = nil
    let colors: Palette
    let close: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            VStack(alignment: .leading, spacing: 5) {
                Text(title).font(.system(size: 21, weight: .semibold)).tracking(-0.45)
                    .foregroundStyle(colors.text)
                if let subtitle { Text(subtitle).font(.system(size: 12)).foregroundStyle(colors.secondary) }
            }
            Spacer(minLength: 0)
            ModalCloseButton(colors: colors, action: close)
        }
    }
}

struct ModalCloseButton: View {
    let colors: Palette
    let action: () -> Void
    var label = "Close"
    @State private var hovering = false
    var body: some View {
        Button(action: action) {
            Image(systemName: "xmark").font(.system(size: 11, weight: .semibold))
                .foregroundStyle(colors.secondary).frame(width: 30, height: 30)
                .background(Circle().fill(colors.hover.opacity(hovering ? 2 : 1)))
                .contentShape(Rectangle())
        }.buttonStyle(.plain).onHover { hovering = $0 }.accessibilityLabel(label)
    }
}

struct ModalButtonStyle: ButtonStyle {
    let colors: Palette
    var primary = false
    @Environment(\.isEnabled) private var enabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label.font(.system(size: 13, weight: .medium))
            .padding(.horizontal, 18).frame(height: 34)
            .foregroundStyle(primary ? colors.panel : colors.text)
            .background {
                Capsule().fill(primary ? colors.text : colors.hover)
                if !primary { Capsule().strokeBorder(colors.separator, lineWidth: 0.7) }
            }
            .opacity(enabled ? (configuration.isPressed ? 0.7 : 1) : 0.35)
            .contentShape(Capsule())
    }
}
