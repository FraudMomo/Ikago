import SwiftUI

enum TabHighlightStyle: String, CaseIterable, Identifiable {
    case none, slide, fade, scale, spring
    var id: String { rawValue }
    var title: String {
        switch self {
        case .none: "None"
        case .slide: "Slide"
        case .fade: "Fade"
        case .scale: "Scale"
        case .spring: "Spring"
        }
    }
    var animation: Animation? {
        switch self {
        case .none: nil
        case .spring: .spring(response: 0.3, dampingFraction: 0.75)
        default: .ikago
        }
    }
}

extension BrowserState {
    var tabHighlightStyle: TabHighlightStyle {
        get { browserPreferences.tabHighlightStyle.flatMap(TabHighlightStyle.init(rawValue:)) ?? .slide }
        set { browserPreferences.tabHighlightStyle = newValue.rawValue }
    }
}

private struct TabHighlightStyleKey: EnvironmentKey {
    static let defaultValue = TabHighlightStyle.slide
}
extension EnvironmentValues {
    var tabHighlightStyle: TabHighlightStyle {
        get { self[TabHighlightStyleKey.self] }
        set { self[TabHighlightStyleKey.self] = newValue }
    }
}

/// One selection treatment shared by regular, pinned and split tabs in both layouts.
struct TabSelectionHighlight<S: Shape>: View {
    let shape: S
    let active: Bool
    let color: Color
    let selection: Namespace.ID
    let id: String
    @Environment(\.tabHighlightStyle) private var preference
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private var style: TabHighlightStyle { reduceMotion ? .none : preference }

    var body: some View {
        ZStack {
            if active {
                if style == .slide || style == .spring {
                    shape.fill(color).matchedGeometryEffect(id: id, in: selection)
                } else {
                    shape.fill(color).transition(style == .fade ? .opacity : style == .scale ? .scale(scale: 0.85).combined(with: .opacity) : .identity)
                }
            }
        }
        .animation(style.animation, value: active)
        .transaction { transaction in
            if style == .none { transaction.animation = nil; transaction.disablesAnimations = true }
        }
        .allowsHitTesting(false)
    }
}
