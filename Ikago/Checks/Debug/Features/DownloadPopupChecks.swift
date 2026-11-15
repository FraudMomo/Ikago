#if DEBUG
import AppKit
import SwiftUI

@MainActor
enum DownloadPopupChecks {
    static func run(_ browser: BrowserWindowController) async {
        var failures = 0
        func check(_ value: Bool, _ title: String) {
            print("IKTEST downloadpopup \(value ? "PASS" : "FAIL") \(title)")
            if !value { failures += 1 }
        }
        let folder = SessionStore.testDirectory.appending(path: "OpenDownloadFixture")
        defer { try? FileManager.default.removeItem(at: folder) }
        do {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            let file = folder.appending(path: "Example.txt")
            try Data("Download open fixture".utf8).write(to: file)
            var calls: [URL] = []
            let center = DownloadCenter(history: DownloadHistoryStore(directory: folder), openFile: { calls.append($0); return true })
            var item = DownloadCenter.Item(); item.name = file.lastPathComponent; item.fileURL = file; item.finished = true
            guard let window = browser.window, let root = window.contentView else { throw CocoaError(.coderInvalidValue) }
            window.makeKeyAndOrderFront(nil); NSApp.activate()
            for compact in [true, false] {
                let view = NSHostingView(rootView: DownloadRow(item: item, colors: browser.state.palette, center: center, compact: compact))
                view.frame = NSRect(x: 60, y: 180, width: 360, height: 92)
                root.addSubview(view, positioned: .above, relativeTo: nil)
                view.layoutSubtreeIfNeeded()
                try? await Task.sleep(for: .milliseconds(150))
                let point = view.convert(NSPoint(x: 120, y: view.bounds.midY), to: nil)
                let before = calls.count
                for type in [NSEvent.EventType.leftMouseDown, .leftMouseUp] {
                    if let event = NSEvent.mouseEvent(with: type, location: point, modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime,
                                                      windowNumber: window.windowNumber, context: nil, eventNumber: 1, clickCount: 1, pressure: 1) {
                        NSApp.postEvent(event, atStart: false)
                    }
                }
                try? await Task.sleep(for: .milliseconds(300))
                check(calls.count == before + 1 && calls.last == file, "single click opens exactly once in \(compact ? "popup" : "history") row")
                view.removeFromSuperview()
            }
            let before = calls.count
            var pending = item; pending.finished = false
            check(!center.open(pending), "unfinished download cannot open")
            var missing = item; missing.fileURL = folder.appending(path: "missing.txt")
            check(!center.open(missing), "missing file returns an actionable failure")
            var remote = item; remote.fileURL = URL(string: "https://example.com")
            check(!center.open(remote) && calls.count == before, "non-file URLs cannot launch from download history")
            check(FileManager.default.fileExists(atPath: file.path), "opening keeps the downloaded file")
        } catch { check(false, error.localizedDescription) }
        print("IKTEST downloadpopupchecks \(failures == 0 ? "PASS" : "FAIL") failures=\(failures)")
    }
}
#endif
