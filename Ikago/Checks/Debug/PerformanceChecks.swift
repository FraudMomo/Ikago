#if DEBUG
import Foundation

@MainActor
enum PerformanceChecks {
    static func run(_ browser: BrowserWindowController) async {
        var failures = 0
        func check(_ ok: Bool, _ name: String) {
            print("IKTEST performance \(ok ? "PASS" : "FAIL") \(name)")
            if !ok { failures += 1 }
        }
        let canary = PageLifetimeCanary()
        var object: NSObject? = NSObject()
        weak let weakObject = object
        let start = Date()
        canary.watch(object!, label: "Fixture", now: start)
        canary.check(now: start.addingTimeInterval(29))
        check(canary.warnings.isEmpty, "canary allows asynchronous teardown")
        canary.check(now: start.addingTimeInterval(31))
        check(canary.warnings.count == 1, "canary detects a deliberately retained object")
        object = nil
        canary.check(now: start.addingTimeInterval(32))
        check(weakObject == nil && canary.warnings.isEmpty, "canary holds only weak references and clears resolved warnings")

        let monitor = PerformanceMonitor.shared
        let before = monitor.listenerCount
        let first = monitor.subscribe(), second = monitor.subscribe()
        check(monitor.listenerCount == before + 2, "multiple diagnostics share subscriptions")
        try? await Task.sleep(for: .seconds(2.5))
        let sample = monitor.sample
        check(sample.rows.contains { $0.id == getpid() && $0.owner == .app }, "main app has its own shared bucket")
        check(sample.memory == sample.rows.reduce(0) { $0 + $1.memory }, "process footprint is counted once")
        check(sample.memory == PerformanceOwner.allCases.reduce(0) { $0 + sample.memory(for: $1) }, "engine buckets equal total footprint")
        check(sample.cpu.isFinite && sample.cpu >= 0 && sample.cpuAvailable, "CPU interval is valid")
        if let page = browser.activeController?.page, page.engine == .webkit {
            check(page.performanceProcessID != nil, "WebKit renderer mapping is available")
        }
        monitor.unsubscribe(first); monitor.unsubscribe(second)
        check(monitor.listenerCount == before, "closing diagnostics releases subscriptions")
        let loaded = browser.performanceTabs().filter { $0.pid != nil }
        check(!loaded.isEmpty, "tab rows expose renderer identity")
        browser.openPage(.performance)
        try? await Task.sleep(for: .seconds(2))
        check(monitor.listenerCount == before + 1, "Performance page samples only while visible")
        browser.open("about:blank", inNewTab: true)
        try? await Task.sleep(for: .milliseconds(500))
        check(monitor.listenerCount == before, "background Performance page stops sampling")
        print("IKTEST performancechecks \(failures == 0 ? "PASS" : "FAIL") failures=\(failures)")
    }
}
#endif
