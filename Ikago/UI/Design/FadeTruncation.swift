import SwiftUI

extension View {
    /// One line that shows as much as fits and fades out at its trailing edge, instead of ending in "…". Short text is
    /// drawn as is.
    func fadeTruncated(fade: CGFloat = 18) -> some View { modifier(FadeTruncation(fade: fade)) }
}

private struct FadeTruncation: ViewModifier {
    let fade: CGFloat
    /// The text's own width and the room it has; the fade shows only while the first is larger.
    @State private var natural: CGFloat = 0
    @State private var available: CGFloat = 0

    func body(content: Content) -> some View {
        let overflows = natural > available + 0.5 && available > 0
        content
            .lineLimit(1)
            .fixedSize(horizontal: true, vertical: false)
            .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { natural = $0 }
            // A zero minimum, or the frame grows to the text's own width and nothing is clipped; never wider than the
            // text, so it hugs it like plain text (callers that want the row's width add their own frame).
            .frame(minWidth: 0, maxWidth: natural > 0 ? natural : .infinity, alignment: .leading)
            .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { available = $0 }
            .clipped()
            .mask {
                LinearGradient(stops: [.init(color: .black, location: 0),
                                       .init(color: .black, location: overflows ? max(0, 1 - fade / max(available, 1)) : 1),
                                       .init(color: overflows ? .clear : .black, location: 1)],
                               startPoint: .leading, endPoint: .trailing)
            }
    }
}
