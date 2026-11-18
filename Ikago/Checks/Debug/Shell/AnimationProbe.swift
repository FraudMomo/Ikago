#if DEBUG
import AppKit
import SwiftUI

/// Measures what Ikago's animations and transitions cost: CPU time of Ikago, WindowServer (which composites every frame)
/// and WebKit's page processes over phases of each kind of motion, and over idle before and after (anything still
/// moving at rest shows there). CPU times come from `ps`, which needs no special rights. Prints one line per phase.
@MainActor
enum AnimationProbe {
    static func run(_ browser: BrowserWindowController) async {
        let state = browser.state
        func pause(_ seconds: Double) async { try? await Task.sleep(for: .seconds(seconds)) }
        // A small, realistic window: two Spaces, a few tabs, two groups.
        let second = state.createSpace(name: "Work", symbol: "briefcase", isolated: false)
        state.switchSpace(state.spaces[0].id)
        for page in ["one", "two", "three", "four"] { _ = state.newTab(url: "about:blank#\(page)", select: false) }
        let group = state.createFolder(named: "Group")
        for page in ["g1", "g2"] { _ = state.newTab(url: "about:blank#\(page)", select: false, folderID: group.id) }
        _ = state.newTab(url: "about:blank#work", in: second.id)
        await pause(3)
        PageFrameCounter.watch(browser.activeController?.page?.contentView)

        func phase(_ name: String, repeat count: Int = 1, every gap: Double = 0, _ step: @MainActor () -> Void = {}) async {
            let before = cpuTimes(), start = Date(), resizes = ContentContainerView.resizes
            let frames = PageFrameCounter.count
            for _ in 0..<count { step(); if gap > 0 { await pause(gap) } }
            if count == 1 && gap == 0 { await pause(8) }
            let after = cpuTimes(), wall = Date().timeIntervalSince(start)
            func percent(_ key: String) -> Int { Int(((after[key] ?? 0) - (before[key] ?? 0)) / wall * 100) }
            print("IKTEST animation \(name) pageResizes=\(ContentContainerView.resizes - resizes) pageFrames=\(PageFrameCounter.count - frames) seconds=\(String(format: "%.1f", wall)) ikago=\(percent("ikago"))% windowserver=\(percent("windowserver"))% webcontent=\(percent("webcontent"))%")
            fflush(stdout)
        }

        await phase("idle-before")
        await phase("tab-switches", repeat: 16, every: 0.35) { withAnimation(.ikago) { state.selectAdjacent(1) } }
        await phase("group-open-close", repeat: 12, every: 0.4) { state.toggleFolder(group.id) }
        await phase("sidebar-states", repeat: 9, every: 0.5) { browser.cycleSidebar() }
        await phase("space-switches", repeat: 10, every: 0.5) {
            withAnimation(.ikago) { state.switchSpace(state.activeSpaceID == second.id ? state.spaces[0].id : second.id) }
        }
        await phase("command-bar", repeat: 10, every: 0.4) {
            if browser.isEditingAddress { browser.dismissCommandPalette() } else { browser.showCommandPalette(newTab: false) }
        }
        if browser.isEditingAddress { browser.dismissCommandPalette() }
        await phase("find-bar", repeat: 10, every: 0.4) {
            if browser.chrome.showFind { browser.closeFindBar() } else { browser.showFindBar() }
        }
        if browser.chrome.showFind { browser.closeFindBar() }
        await phase("idle-after")
        // Settings with its looping drawings on screen (tab highlight, page switch).
        state.settingsCategory = .appearance
        state.settingsSubpage[.appearance] = "Details"
        browser.openPage(.settings)
        await pause(2)
        await phase("idle-settings-details")
        print("IKTEST animationprobe done")
    }

    /// Seconds of CPU so far: this app, WindowServer, and every WebKit page process together.
    private static func cpuTimes() -> [String: Double] {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/ps")
        process.arguments = ["-axo", "pid=,time=,comm="]
        let pipe = Pipe()
        process.standardOutput = pipe
        try? process.run()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        let me = ProcessInfo.processInfo.processIdentifier
        var result: [String: Double] = [:]
        for line in String(decoding: data, as: UTF8.self).split(separator: "\n") {
            let parts = line.split(separator: " ", maxSplits: 2, omittingEmptySubsequences: true)
            guard parts.count == 3, let pid = Int32(parts[0]) else { continue }
            let seconds = parse(String(parts[1])), command = String(parts[2])
            if pid == me { result["ikago", default: 0] += seconds }
            else if command.hasSuffix("/WindowServer") { result["windowserver", default: 0] += seconds }
            else if command.contains("com.apple.WebKit.WebContent") { result["webcontent", default: 0] += seconds }
        }
        return result
    }

    /// `ps` time: "m:ss.cc" or "h:mm:ss".
    private static func parse(_ text: String) -> Double {
        text.split(separator: ":").reduce(0) { $0 * 60 + (Double($1) ?? 0) }
    }
}
/// Counts every size the visible page view is given (KVO on its frame), however it got there.
@MainActor
enum PageFrameCounter {
    static var count = 0
    private static var observation: NSKeyValueObservation?
    static func watch(_ view: NSView?) {
        observation = view?.observe(\.frame, options: [.old, .new]) { _, change in
            if change.oldValue?.size != change.newValue?.size { MainActor.assumeIsolated { count += 1 } }
        }
    }
}
#endif
