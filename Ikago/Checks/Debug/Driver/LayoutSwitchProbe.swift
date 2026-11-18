#if DEBUG
import AppKit
import SwiftUI

/// Measures switching between Sidebar and Top Tabs as Settings does: the main thread's synchronous cost of the
/// switch, then every frame for 600 ms (the slowest and how many missed 60 Hz). `layoutprobe:<switches>`.
@MainActor
final class LayoutSwitchProbe: NSObject {
    private var intervals: [Double] = []
    private var last: CFTimeInterval = 0
    private var link: CADisplayLink?

    @objc private func tick(_ link: CADisplayLink) {
        let now = CACurrentMediaTime()
        if last > 0 { intervals.append((now - last) * 1000) }
        last = now
    }

    static func run(_ c: BrowserWindowController, switches: Int) async {
        guard let view = c.window?.contentView else { return }
        let probe = LayoutSwitchProbe()
        for index in 0..<switches {
            let tabs = c.state.browserPreferences.sidebarTopTabs != true
            probe.intervals = []; probe.last = 0
            probe.link = view.displayLink(target: probe, selector: #selector(tick(_:)))
            probe.link?.add(to: .main, forMode: .common)
            let start = CACurrentMediaTime()
            LayoutSwitch.set(tabs: tabs, state: c.state)
            let sync = (CACurrentMediaTime() - start) * 1000
            try? await Task.sleep(for: .milliseconds(600))
            probe.link?.invalidate()
            let slow = probe.intervals.max() ?? 0
            let missed = probe.intervals.filter { $0 > 20 }.count
            print(String(format: "IKTEST layoutprobe %d to=%@ sync=%.1fms frames=%d slowest=%.1fms over20ms=%d total=%.0fms",
                         index, tabs ? "tabs" : "sidebar", sync, probe.intervals.count, slow, missed,
                         probe.intervals.reduce(0, +)))
        }
    }
}
#endif
