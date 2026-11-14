import AppKit
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

/// The WebKit project's logo (webkit.org, © Apple Inc.), bundled as `webkit-logo.svg` with its colors converted to
/// sRGB, used only to identify the WebKit engine (see THIRD_PARTY_NOTICES.md). Its own shape on a clear background, like
/// Chromium's; a blue disc with a globe stands in if the file is missing.
struct WebKitLogo: View {
    var size: CGFloat = 56

    @MainActor static let image: NSImage? = {
        guard let url = Bundle.main.url(forResource: "webkit-logo", withExtension: "svg") else { return nil }
        return NSImage(contentsOf: url)
    }()

    var body: some View {
        Group {
            if let image = Self.image {
                Image(nsImage: image).resizable().interpolation(.high).aspectRatio(contentMode: .fit)
            } else {
                Circle()
                    .fill(LinearGradient(colors: [Color(hex: 0x5AC8FA), Color(hex: 0x0A6CFF)], startPoint: .top, endPoint: .bottom))
                    .overlay { Image(systemName: "globe").font(.system(size: size * 0.56, weight: .medium)).foregroundStyle(.white) }
            }
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
