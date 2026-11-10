import SwiftUI

extension View {
    /// Debug driver checks the rendered geometry, including clipping that model-only checks miss.
    @ViewBuilder func recordLayout(_ name: String, enabled: Bool = true) -> some View {
        #if DEBUG
        onGeometryChange(for: LayoutSample.self) { LayoutSample(frame: $0.frame(in: .global), enabled: enabled) } action: {
            if $0.enabled { LayoutChecks.frames[name] = $0.frame }
        }
        #else
        self
        #endif
    }
}

#if DEBUG
private struct LayoutSample: Equatable {
    let frame: CGRect
    let enabled: Bool
}
#endif
