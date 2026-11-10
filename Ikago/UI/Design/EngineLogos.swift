import SwiftUI

/// The Chromium project's logo, drawn in code: three blue segments around a white ring and a blue center.
/// © The Chromium Authors, used under CC BY 2.5 (see THIRD_PARTY_NOTICES.md) to identify the engine.
struct ChromiumLogo: View {
    var size: CGFloat = 56

    var body: some View {
        Canvas { context, canvas in
            let center = CGPoint(x: canvas.width / 2, y: canvas.height / 2)
            let radius = min(canvas.width, canvas.height) / 2
            // Angles clockwise from 12 o'clock: top, bottom right, bottom left.
            let segments: [(Color, Double)] = [(Color(hex: 0x396BD7), -58), (Color(hex: 0x91B0E8), 62), (Color(hex: 0x6199F6), 183)]
            for (color, start) in segments {
                var slice = Path()
                slice.move(to: center)
                slice.addArc(center: center, radius: radius, startAngle: .degrees(start - 90),
                             endAngle: .degrees(start + 30), clockwise: false)
                slice.closeSubpath()
                context.fill(slice, with: .color(color))
            }
            func disc(_ fraction: CGFloat, _ color: Color) {
                let r = radius * fraction
                context.fill(Path(ellipseIn: CGRect(x: center.x - r, y: center.y - r, width: r * 2, height: r * 2)), with: .color(color))
            }
            disc(0.4696, .white)
            disc(0.3875, Color(hex: 0x4688F4))
        }
        .frame(width: size, height: size)
        .accessibilityLabel("Chromium")
    }
}

/// Ikago's own mark for the WebKit engine. WebKit's logo belongs to Apple and isn't free to use, so this is
/// an original design: a blue disc with a globe.
struct WebKitLogo: View {
    var size: CGFloat = 56

    var body: some View {
        Circle()
            .fill(LinearGradient(colors: [Color(hex: 0x5AC8FA), Color(hex: 0x0A6CFF)], startPoint: .top, endPoint: .bottom))
            .overlay {
                Image(systemName: "globe").font(.system(size: size * 0.56, weight: .medium)).foregroundStyle(.white)
            }
            .frame(width: size, height: size)
            .accessibilityLabel("WebKit")
    }
}

struct EngineLogo: View {
    let engine: BrowserEngine
    var size: CGFloat = 56
    var body: some View {
        switch engine {
        case .webkit: WebKitLogo(size: size)
        case .chromium: ChromiumLogo(size: size)
        }
    }
}
