import SwiftUI

/// Shared window-integrated cards. With glass off they are solid, neutral sheets like a macOS panel: an opaque card,
/// a hairline rim and two layered shadows (a tight contact shadow and a soft ambient one), never a tinted wash.
extension View {
    func modalCard(_ colors: Palette, width: CGFloat) -> some View {
        padding(20).frame(width: width).modalSurface(colors)
    }

    /// `frosted`: with glass off, the frosted window's material instead of a solid sheet. `tint`: how much of the Space's
    /// color the glass takes (cards with many rows read better with little).
    func modalSurface(_ colors: Palette, radius: CGFloat = ModalMetrics.radius, frosted: Bool = false, tint: Double = 0.4) -> some View {
        let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)
        return Group {
            if colors.glass { surface(shape, colors, tintOpacity: tint) }
            else if frosted { background(shape.fill(.regularMaterial)) }
            else { background(shape.fill(ModalMetrics.card(colors))) }
        }
        .overlay(shape.strokeBorder(colors.isDark ? Color.white.opacity(0.1) : Color.black.opacity(0.08), lineWidth: 0.5).allowsHitTesting(false))
        .background {
            CardShadow(shape: shape, color: .black.opacity(colors.isDark ? 0.45 : 0.14), radius: 24, y: 12)
            CardShadow(shape: shape, color: .black.opacity(colors.isDark ? 0.3 : 0.06), radius: 1.5, y: 1)
        }
    }

    func modalInput(_ colors: Palette) -> some View {
        textFieldStyle(.plain).font(.system(size: 13))
            .padding(.horizontal, 10).frame(height: 32)
            .background(RoundedRectangle(cornerRadius: Radius.control, style: .continuous).fill(ModalMetrics.field(colors)))
            .overlay(RoundedRectangle(cornerRadius: Radius.control, style: .continuous)
                .strokeBorder(colors.isDark ? Color.white.opacity(0.1) : Color.black.opacity(0.1), lineWidth: 0.5))
    }
}

enum ModalMetrics {
    static let radius: CGFloat = Radius.sheet
    static func card(_ colors: Palette) -> Color { colors.isDark ? Color(hex: 0x252527) : .white }
    static func field(_ colors: Palette) -> Color { colors.isDark ? Color.white.opacity(0.05) : Color(hex: 0xFAFAFA) }
}

struct ModalHeading: View {
    let title: String
    var subtitle: String? = nil
    let colors: Palette
    let close: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.system(size: 15, weight: .semibold))
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
            Image(systemName: "xmark").font(.system(size: 10, weight: .semibold))
                .foregroundStyle(colors.secondary).frame(width: 24, height: 24)
                .background(Circle().fill(colors.hover.opacity(hovering ? 2 : 0)))
                .contentShape(Rectangle())
        }
        .buttonStyle(SiteCardPressStyle(scale: 0.88))
        .onHover { hovering = $0 }
        .animation(.ikagoQuick, value: hovering)
        .accessibilityLabel(label)
    }
}

/// Footer buttons, as in macOS sheets: an accent-filled default action and bordered secondary ones.
struct ModalButtonStyle: ButtonStyle {
    let colors: Palette
    var primary = false
    @Environment(\.isEnabled) private var enabled

    func makeBody(configuration: Configuration) -> some View {
        let shape = RoundedRectangle(cornerRadius: Radius.control, style: .continuous)
        return configuration.label.font(.system(size: 13, weight: .medium))
            .padding(.horizontal, 14).frame(minWidth: 72).frame(height: 30)
            .foregroundStyle(primary ? Color.white : colors.text)
            .background {
                if primary { shape.fill(colors.accent) }
                else {
                    shape.fill(colors.isDark ? Color.white.opacity(0.08) : .white)
                    shape.strokeBorder(colors.isDark ? Color.white.opacity(0.1) : Color.black.opacity(0.12), lineWidth: 0.5)
                }
            }
            .background {
                if !primary && !colors.isDark { CardShadow(shape: shape, color: .black.opacity(0.05), radius: 1, y: 0.5) }
            }
            .overlay(shape.fill(Color.black.opacity(configuration.isPressed ? 0.12 : 0)))
            .opacity(enabled ? 1 : 0.4)
            .contentShape(shape)
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(.spring(duration: 0.2, bounce: 0.3), value: configuration.isPressed)
    }
}
