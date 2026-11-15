#if DEBUG
import AppKit
import SwiftUI

/// Measures a sidebar group opening or closing frame by frame: where each group's section is, the list's scroll offset
/// and document height, and how regular the frames are. `groupseed:<tabs per group>` then `groupprobe:<group number>`.
@MainActor
final class GroupDisclosureProbe: NSObject {
    static let shared = GroupDisclosureProbe()
    private var active = false
    private var start = CACurrentMediaTime()
    private var lines: [String] = []
    private weak var scroll: NSScrollView?
    private var link: CADisplayLink?
    private var lastFrame: CFTimeInterval = 0

    /// Called by every group section on each geometry change.
    func note(_ name: String, _ frame: CGRect) {
        guard active else { return }
        lines.append(String(format: "%7.1f geo %@ y=%.1f h=%.1f", ms, name, frame.minY, frame.height))
    }

    private var ms: Double { (CACurrentMediaTime() - start) * 1000 }

    static func seed(_ c: BrowserWindowController, perGroup: Int) {
        let state = c.state
        // The test session folder survives runs: start from no groups and no probe tabs.
        state.tabs.removeAll { $0.url.hasPrefix("about:blank#") }
        for folder in state.spaceFolders { state.deleteFolder(folder.id) }
        for name in ["Alpha", "Beta", "Gamma"] {
            let folder = state.createFolder(named: name)
            for i in 0..<perGroup { state.newTab(url: "about:blank#\(name)\(i)", select: false, folderID: folder.id) }
        }
        for i in 0..<4 { state.newTab(url: "about:blank#loose\(i)", select: false) }
    }

    /// Opens or closes the media island (`IkagoIslandToggle`) and logs the list above it frame by frame: it should give
    /// way smoothly, not jump.
    func runIsland(_ c: BrowserWindowController) async {
        guard let content = c.window?.contentView,
              let scroll = content.allSubviews(of: ListScrollView.self).max(by: { $0.frame.height < $1.frame.height }) else { return }
        self.scroll = scroll
        lines = []
        start = CACurrentMediaTime()
        lastFrame = 0
        active = true
        let link = scroll.displayLink(target: self, selector: #selector(tick(_:)))
        link.add(to: .main, forMode: .common)
        NotificationCenter.default.post(name: .init("IkagoIslandToggle"), object: nil)
        try? await Task.sleep(for: .milliseconds(700))
        link.invalidate()
        active = false
        for line in lines { print("IKTEST ip \(line)") }
    }

    func run(_ c: BrowserWindowController, group: Int, scrollTo: Double?) async {
        guard let window = c.window, let content = window.contentView,
              let scroll = content.allSubviews(of: ListScrollView.self).max(by: {
                  ($0.documentView?.frame.height ?? 0) < ($1.documentView?.frame.height ?? 0) }),
              c.state.spaceFolders.indices.contains(group - 1) else { print("IKTEST groupprobe no list"); return }
        self.scroll = scroll
        if let scrollTo, let document = scroll.documentView {
            let lowest = max(0, document.frame.height - scroll.contentView.bounds.height)
            scroll.contentView.scroll(to: NSPoint(x: 0, y: lowest * scrollTo))
            scroll.reflectScrolledClipView(scroll.contentView)
            try? await Task.sleep(for: .milliseconds(300))
        }
        let layer = scroll.layer
        print("IKTEST groupprobe layer flipped=\(layer?.contentsAreFlipped() ?? false) geometryFlipped=\(layer?.isGeometryFlipped ?? false) " +
              "superFlipped=\(scroll.superview?.isFlipped ?? false) visible=\(scroll.contentView.bounds.height) doc=\(scroll.documentView?.frame.height ?? 0)")
        lines = []
        start = CACurrentMediaTime()
        lastFrame = 0
        active = true
        let link = scroll.displayLink(target: self, selector: #selector(tick(_:)))
        link.add(to: .main, forMode: .common)
        self.link = link
        c.state.toggleFolder(c.state.spaceFolders[group - 1].id)
        try? await Task.sleep(for: .milliseconds(800))
        link.invalidate()
        active = false
        for line in lines { print("IKTEST gp \(line)") }
    }

    @objc private func tick(_ link: CADisplayLink) {
        guard let scroll else { return }
        let gap = lastFrame == 0 ? 0 : (link.timestamp - lastFrame) * 1000
        lastFrame = link.timestamp
        let mask = scroll.layer?.mask as? CAGradientLayer
        lines.append(String(format: "%7.1f frame gap=%.1f listH=%.1f clipY=%.1f doc=%.1f mask=%@", ms, gap, scroll.frame.height, scroll.contentView.bounds.minY,
                            scroll.documentView?.frame.height ?? 0,
                            mask.map { ($0.locations ?? []).map { String(format: "%.2f", $0.doubleValue) }.joined(separator: ",") } ?? "none"))
    }
}

private extension NSView {
    func allSubviews<T: NSView>(of type: T.Type) -> [T] {
        ((self as? T).map { [$0] } ?? []) + subviews.flatMap { $0.allSubviews(of: type) }
    }
}
#endif
