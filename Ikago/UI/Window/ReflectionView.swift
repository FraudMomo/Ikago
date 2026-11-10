import AppKit
import CoreImage

/// Floating island: the strip above a page at its top is a flipped, blurred and faded copy of the
/// content just below it, so the page seems to continue under the island. Scrolling reveals the
/// real content over it.
final class ReflectionView: NSView {
    private let imageLayer = CALayer()
    private let fade = CAGradientLayer()

    init() {
        super.init(frame: .zero)
        wantsLayer = true
        autoresizingMask = [.width, .minYMargin]
        imageLayer.contentsGravity = .resize
        layer?.addSublayer(imageLayer)
        // Faint at the top edge, solid where it meets the page.
        fade.colors = [NSColor.black.withAlphaComponent(0.45).cgColor, NSColor.black.cgColor]
        fade.startPoint = CGPoint(x: 0.5, y: 1)
        fade.endPoint = CGPoint(x: 0.5, y: 0)
        layer?.mask = fade
        isHidden = true
    }

    @available(*, unavailable) required init?(coder: NSCoder) { fatalError() }

    override func layout() {
        super.layout()
        imageLayer.frame = bounds
        fade.frame = bounds
    }

    private static let context = CIContext()

    /// Shows the mirrored, smeared version of `snapshot` (the page rows just below the strip).
    func show(_ snapshot: NSImage?) {
        guard let cg = snapshot?.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return clear() }
        let source = CIImage(cgImage: cg)
        let smeared = source.oriented(.downMirrored).clampedToExtent()
            .applyingGaussianBlur(sigma: 9).cropped(to: source.extent)
        imageLayer.contents = Self.context.createCGImage(smeared, from: smeared.extent)
        isHidden = false
    }

    func clear() {
        imageLayer.contents = nil
        isHidden = true
    }
}
