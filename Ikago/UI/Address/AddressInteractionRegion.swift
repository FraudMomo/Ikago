import AppKit
import SwiftUI

/// Marks the field and its results as one interaction area without intercepting mouse input.
struct AddressInteractionRegion: FillingViewRepresentable {
    func makeNSView(context: Context) -> AddressRegionView { AddressRegionView() }
    func updateNSView(_ view: AddressRegionView, context: Context) {}
}

final class AddressRegionView: NSView {
    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    static func contains(_ location: NSPoint, in root: NSView) -> Bool {
        guard !root.isHiddenOrHasHiddenAncestor else { return false }
        // SwiftUI backgrounds can expose an ancestor-sized visibleRect; constrain it to the marked surface.
        if root is AddressRegionView || root is FocusingTextField,
           root.bounds.intersection(root.visibleRect).contains(root.convert(location, from: nil)) {
            return true
        }
        return root.subviews.contains { contains(location, in: $0) }
    }
}

extension View {
    func addressInteractionRegion() -> some View { background(AddressInteractionRegion()) }
}
