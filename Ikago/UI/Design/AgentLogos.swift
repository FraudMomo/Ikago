import AppKit
import SwiftUI

/// The mark of the agent that's connected (Claude, OpenAI, Gemini…), from `Resources/agent-logos` (Simple Icons, see
/// THIRD_PARTY_NOTICES.md), tinted in the brand's color; sparkles for an agent Ikago doesn't know. Used only to show which
/// agent is driving.
struct AgentLogo: View {
    let brand: AgentIdentity.Brand
    var size: CGFloat = 16

    @MainActor private static var images: [AgentIdentity.Brand: NSImage] = [:]

    @MainActor static func image(_ brand: AgentIdentity.Brand) -> NSImage? {
        if let image = images[brand] { return image }
        guard brand != .generic,
              let url = Bundle.main.url(forResource: brand.rawValue, withExtension: "svg", subdirectory: "agent-logos"),
              let image = NSImage(contentsOf: url) else { return nil }
        image.isTemplate = true
        images[brand] = image
        return image
    }

    var body: some View {
        Group {
            if let image = Self.image(brand) {
                Image(nsImage: image).renderingMode(.template).resizable().interpolation(.high).aspectRatio(contentMode: .fit)
                    .foregroundStyle(brand.tint)
            } else {
                Image(systemName: "sparkles").resizable().aspectRatio(contentMode: .fit).fontWeight(.semibold)
                    .foregroundStyle(brand.tint)
            }
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}

extension AgentIdentity.Brand {
    /// The brand's own color; the black marks follow the text color so they read in dark mode.
    var tint: AnyShapeStyle {
        switch self {
        case .claude: AnyShapeStyle(Color(hex: 0xD97757))
        case .gemini: AnyShapeStyle(LinearGradient(colors: [Color(hex: 0x4285F4), Color(hex: 0x9B72CB), Color(hex: 0xD96570)],
                                                   startPoint: .topLeading, endPoint: .bottomTrailing))
        case .zed: AnyShapeStyle(Color(hex: 0x084CCF))
        case .generic: AnyShapeStyle(Color(hex: 0x7C3AED))
        case .openai, .cursor, .copilot, .windsurf: AnyShapeStyle(.primary)
        }
    }

    /// The pulse around a working badge.
    var accent: Color {
        switch self {
        case .claude: Color(hex: 0xD97757)
        case .gemini: Color(hex: 0x9B72CB)
        case .zed: Color(hex: 0x084CCF)
        case .generic: Color(hex: 0x7C3AED)
        case .openai: Color(hex: 0x10A37F)
        case .cursor, .copilot, .windsurf: Color.secondary
        }
    }
}

/// An agent's mark on a small disc: on a tab's icon while that agent drives it, in its bar, and in Settings. While it
/// works a soft ring pulses out of the disc.
struct AgentBadge: View {
    let agent: AgentIdentity
    var working = false
    /// The disc's diameter.
    var size: CGFloat = 12
    @State private var pulse = false

    var body: some View {
        AgentLogo(brand: agent.brand, size: size * (size < 16 ? 0.72 : 0.6))
            .frame(width: size, height: size)
            .background(Circle().fill(Color(nsColor: .textBackgroundColor)))
            .overlay(Circle().strokeBorder(Color.primary.opacity(0.12), lineWidth: 0.5))
            .shadow(color: .black.opacity(0.18), radius: 1, y: 0.5)
            .background {
                if working {
                    Circle().stroke(agent.brand.accent, lineWidth: 1.2)
                        .scaleEffect(pulse ? 1.55 : 1).opacity(pulse ? 0 : 0.7)
                        .animation(.easeOut(duration: 1.3).repeatForever(autoreverses: false), value: pulse)
                        .onAppear { pulse = true }
                        .onDisappear { pulse = false }
                }
            }
            .help("\(agent.name) is driving this tab")
            .accessibilityElement()
            .accessibilityLabel("\(agent.name) is driving this tab")
    }
}
