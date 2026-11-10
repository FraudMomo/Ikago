import AppKit

/// View ▸ Performance Stats: frames per second, CPU and memory in a pill at the window's bottom-right corner.
///
/// Plain AppKit, so showing it adds nothing to the SwiftUI graphs it helps to judge. Frames are counted on the main
/// thread by a display link: the rate drops and the longest frame grows whenever the main thread is too busy to
/// serve the display, which is what choppy scrolling and animation are.
final class PerformanceOverlay: NSVisualEffectView {
    private let label = NSTextField(labelWithString: "")
    private let sampler = PerformanceSampler()
    private var link: CADisplayLink?
    private var frames = 0
    private var windowStart: CFTimeInterval = 0
    private var lastFrame: CFTimeInterval = 0
    private var longest: CFTimeInterval = 0
    private var frameText = "– fps"
    private var sample = PerformanceSample()
    private static let margin: CGFloat = 10
    private static let padding: CGFloat = 9
    private static let height: CGFloat = 24

    init() {
        super.init(frame: .zero)
        material = .hudWindow
        blendingMode = .withinWindow
        state = .active
        wantsLayer = true
        layer?.cornerRadius = 7
        layer?.cornerCurve = .continuous
        layer?.masksToBounds = true
        label.font = .monospacedDigitSystemFont(ofSize: 11, weight: .medium)
        label.textColor = .labelColor
        label.lineBreakMode = .byClipping
        addSubview(label)
        setAccessibilityElement(false)
    }

    @available(*, unavailable) required init?(coder: NSCoder) { fatalError() }

    /// Clicks and scrolling go to whatever is underneath.
    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        link?.invalidate()
        link = nil
        sampler.stop()
        NotificationCenter.default.removeObserver(self)
        guard window != nil, let superview else { return }
        NotificationCenter.default.addObserver(self, selector: #selector(place), name: NSView.frameDidChangeNotification, object: superview)
        let link = displayLink(target: self, selector: #selector(frame(_:)))
        link.add(to: .main, forMode: .common)
        self.link = link
        sampler.start { [weak self] in
            self?.sample = $0
            self?.render()
        }
        render()
    }

    @objc private func frame(_ link: CADisplayLink) {
        let now = link.timestamp
        if lastFrame > 0 { longest = max(longest, now - lastFrame) }
        lastFrame = now
        frames += 1
        if windowStart == 0 { windowStart = now; frames = 0; return }
        guard now - windowStart >= 1 else { return }
        frameText = "\(Int((Double(frames) / (now - windowStart)).rounded())) fps  ·  slowest \(Int((longest * 1000).rounded())) ms"
        windowStart = now
        frames = 0
        longest = 0
        render()
    }

    private func render() {
        let memory = ByteCountFormatter.string(fromByteCount: Int64(sample.memory), countStyle: .memory)
        let text = "\(frameText)      CPU \(Int(sample.cpu.rounded()))%      \(memory)  ·  \(sample.processes) processes"
        guard label.stringValue != text else { return }
        label.stringValue = text
        place()
    }

    @objc private func place() {
        guard let superview else { return }
        let width = ceil(label.intrinsicContentSize.width) + Self.padding * 2
        let y = superview.isFlipped ? superview.bounds.height - Self.height - Self.margin : Self.margin
        frame = NSRect(x: superview.bounds.width - width - Self.margin, y: y, width: width, height: Self.height)
        let textHeight = ceil(label.intrinsicContentSize.height)
        label.frame = NSRect(x: Self.padding, y: ((Self.height - textHeight) / 2).rounded(), width: width - Self.padding * 2, height: textHeight)
    }
}

extension BrowserWindowController {
    static let performanceStatsKey = "showPerformanceStats"

    private var performanceOverlay: PerformanceOverlay? {
        window?.contentView?.subviews.lazy.compactMap { $0 as? PerformanceOverlay }.first
    }

    var showsPerformanceStats: Bool { performanceOverlay != nil }

    @objc func togglePerformanceStats(_ sender: Any?) {
        let show = !showsPerformanceStats
        UserDefaults.standard.set(show, forKey: Self.performanceStatsKey)
        setPerformanceStats(show)
    }

    /// New windows follow the saved choice. Check runs never show it.
    func restorePerformanceStats() {
        guard ProcessInfo.processInfo.environment["IKAGO_TEST_MODE"] == nil else { return }
        setPerformanceStats(UserDefaults.standard.bool(forKey: Self.performanceStatsKey))
    }

    private func setPerformanceStats(_ show: Bool) {
        if !show { performanceOverlay?.removeFromSuperview(); return }
        guard performanceOverlay == nil, let content = window?.contentView else { return }
        content.addSubview(PerformanceOverlay(), positioned: .above, relativeTo: nil)
    }
}
