import SwiftUI

/// An arched tab: generous rounded shoulders on top, and a bottom edge that curves out into the page below, as in
/// Chrome's and Safari's attached tabs. The flares sit outside the frame, so neighbouring slots keep their widths.
struct AttachedTabShape: Shape {
    var radius: CGFloat = Radius.card
    var flare: CGFloat = 10

    func path(in rect: CGRect) -> Path {
        var path = Path()
        let r = min(radius, rect.height / 2), f = min(flare, rect.height / 2)
        path.move(to: CGPoint(x: rect.minX - f, y: rect.maxY))
        path.addQuadCurve(to: CGPoint(x: rect.minX, y: rect.maxY - f), control: CGPoint(x: rect.minX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.minY + r))
        path.addQuadCurve(to: CGPoint(x: rect.minX + r, y: rect.minY), control: CGPoint(x: rect.minX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX - r, y: rect.minY))
        path.addQuadCurve(to: CGPoint(x: rect.maxX, y: rect.minY + r), control: CGPoint(x: rect.maxX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - f))
        path.addQuadCurve(to: CGPoint(x: rect.maxX + f, y: rect.maxY), control: CGPoint(x: rect.maxX, y: rect.maxY))
        path.closeSubpath()
        return path
    }
}

/// A small round control on a split pair in the tab row: close one tab, or separate the pair.
struct SplitTabButton: View {
    let symbol: String
    let label: String
    let colors: Palette
    var filled = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol).font(.system(size: filled ? 12 : 8.5, weight: filled ? .semibold : .bold))
                .foregroundStyle(filled ? colors.text : colors.secondary)
                .frame(width: filled ? 28 : 18, height: filled ? 28 : 18)
                .background { if filled { Circle().fill(colors.panel).overlay(Circle().strokeBorder(colors.separator, lineWidth: 0.5)) } }
                .contentShape(Circle())
        }
        .buttonStyle(CircleHoverButtonStyle(colors: colors))
        .help(label).accessibilityLabel(label)
    }
}
