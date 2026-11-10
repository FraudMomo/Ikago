import SwiftUI

/// Chrome's three-color wheel, drawn in code, to identify the Chromium engine.
struct ChromiumLogo: View {
    var size: CGFloat = 56

    var body: some View {
        Canvas { context, canvas in
            let center = CGPoint(x: canvas.width / 2, y: canvas.height / 2)
            let radius = min(canvas.width, canvas.height) / 2
            let segments: [(Color, Double)] = [(Color(hex: 0xEA4335), -150), (Color(hex: 0xFBBC04), -30), (Color(hex: 0x34A853), 90)]
            for (color, start) in segments {
                var slice = Path()
                slice.move(to: center)
                slice.addArc(center: center, radius: radius, startAngle: .degrees(start), endAngle: .degrees(start + 120), clockwise: false)
                slice.closeSubpath()
                context.fill(slice, with: .color(color))
            }
            let hub = radius * 0.5
            context.fill(Path(ellipseIn: CGRect(x: center.x - hub, y: center.y - hub, width: hub * 2, height: hub * 2)), with: .color(.white))
            let core = radius * 0.39
            context.fill(Path(ellipseIn: CGRect(x: center.x - core, y: center.y - core, width: core * 2, height: core * 2)),
                         with: .linearGradient(Gradient(colors: [Color(hex: 0x86B7FE), Color(hex: 0x1A73E8)]),
                                               startPoint: CGPoint(x: center.x, y: center.y - core), endPoint: CGPoint(x: center.x, y: center.y + core)))
        }
        .frame(width: size, height: size)
        .shadow(color: .black.opacity(0.22), radius: size * 0.1, y: size * 0.05)
        .accessibilityLabel("Chromium")
    }
}

/// WebKit's compass, drawn in code.
struct WebKitLogo: View {
    var size: CGFloat = 56

    var body: some View {
        Canvas { context, canvas in
            let center = CGPoint(x: canvas.width / 2, y: canvas.height / 2)
            let radius = min(canvas.width, canvas.height) / 2
            let disc = CGRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2)
            context.fill(Path(ellipseIn: disc), with: .linearGradient(Gradient(colors: [Color(hex: 0x62D0FF), Color(hex: 0x0A6CFF)]),
                                                                      startPoint: CGPoint(x: center.x, y: disc.minY), endPoint: CGPoint(x: center.x, y: disc.maxY)))
            context.stroke(Path(ellipseIn: disc.insetBy(dx: radius * 0.1, dy: radius * 0.1)), with: .color(.white.opacity(0.92)), lineWidth: radius * 0.045)
            for tick in 0..<24 {
                let angle = Angle.degrees(Double(tick) * 15).radians
                let inner = radius * (tick % 6 == 0 ? 0.68 : 0.74), outer = radius * 0.84
                var line = Path()
                line.move(to: CGPoint(x: center.x + cos(angle) * inner, y: center.y + sin(angle) * inner))
                line.addLine(to: CGPoint(x: center.x + cos(angle) * outer, y: center.y + sin(angle) * outer))
                context.stroke(line, with: .color(.white.opacity(0.75)), lineWidth: radius * 0.025)
            }
            let tilt = Angle.degrees(45).radians
            let tip = CGPoint(x: center.x + cos(-tilt) * radius * 0.66, y: center.y + sin(-tilt) * radius * 0.66)
            let tail = CGPoint(x: center.x - cos(-tilt) * radius * 0.66, y: center.y - sin(-tilt) * radius * 0.66)
            let side = CGPoint(x: cos(tilt) * radius * 0.13, y: sin(tilt) * radius * 0.13)
            func needle(_ point: CGPoint, _ color: Color) {
                var shape = Path()
                shape.move(to: point)
                shape.addLine(to: CGPoint(x: center.x + side.x, y: center.y + side.y))
                shape.addLine(to: CGPoint(x: center.x - side.x, y: center.y - side.y))
                shape.closeSubpath()
                context.fill(shape, with: .color(color))
            }
            needle(tip, Color(hex: 0xFF3B30))
            needle(tail, .white)
        }
        .frame(width: size, height: size)
        .shadow(color: .black.opacity(0.22), radius: size * 0.1, y: size * 0.05)
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
