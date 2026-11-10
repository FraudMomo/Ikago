import SwiftUI

/// A drop shadow cast by a card's outline alone, drawn behind the card with its inside cut out, so glass and
/// translucent materials stay clear.
///
/// Use it instead of `.shadow` on a card. SwiftUI casts `.shadow` from the alpha of everything inside the view,
/// so a shadowed container is rendered again into one bitmap whenever anything in it changes: every scroll frame,
/// progress tick or hover fade. This view depends only on the shape, so it renders once.
struct CardShadow<S: Shape>: View {
    let shape: S
    let color: Color
    let radius: CGFloat
    var x: CGFloat = 0
    var y: CGFloat = 0

    var body: some View {
        shape.fill(.black)
            .shadow(color: color, radius: radius, x: x, y: y)
            .overlay(shape.fill(.black).blendMode(.destinationOut))
            .compositingGroup()
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }
}
