#if DEBUG
import AppKit

/// Exercises WebKit's actual download delegate and progress notifications on a loopback server.
@MainActor
enum DownloadChecks {
    static func run(_ c: BrowserWindowController, base: String) async {
        guard WebProfiles.isTestMode, let url = URL(string: base), url.host == "127.0.0.1" else {
            print("IKTEST downloadchecks FAIL requires isolated profile and loopback fixture"); return
        }
        var failures = 0
        func check(_ value: Bool, _ title: String) {
            print("IKTEST downloads \(value ? "PASS" : "FAIL") \(title)")
            if !value { failures += 1 }
        }
        let center = DownloadCenter.shared
        center.clearFinished()
        c.open(base + "/slow-page", inNewTab: false)
        let loading = await until { c.state.activeTab?.isLoading == true && (c.state.activeTab?.progress ?? 0) > 0.1 }
        check(loading && (c.state.activeTab?.progress ?? 1) < 1, "WebKit reports intermediate page-load progress")
        c.reloadOrStop()
        let stopped = await until { c.state.activeTab?.isLoading == false && c.activeController?.page?.webView.isLoading == false }
        check(stopped && c.activeController?.page?.webView.isLoading == false, "address Stop command stops actual page loading")
        c.open(base + "/download", inNewTab: false)
        let progressing = await until { center.items.contains { $0.inProgress && $0.received > 0 && $0.received < $0.total } }
        check(progressing && center.activeCount == 1 && center.showsToolbarButton, "real download reports byte progress and shows toolbar control")
        check((center.overallFraction ?? 0) > 0 && (center.overallFraction ?? 1) < 1, "toolbar reports aggregate download progress")
        c.toggleDownloads()
        check(c.chrome.showDownloads && c.downloadsPresented, "toolbar and menu open the downloads dropdown")
        c.toggleDownloads()
        let completed = await until { center.items.first?.finished == true }
        let first = center.items.first
        check(completed && center.activeCount == 0 && center.showsToolbarButton, "completion keeps entry and recent-download button")
        let expectedBytes = Int64("Ikago download fixture\n".utf8.count * 1024 * 80)
        check(first?.received == expectedBytes && first?.total == expectedBytes, "completed download records actual file size")
        check(first?.fileURL.map { FileManager.default.fileExists(atPath: $0.path) } == true, "WebKit writes the downloaded file")
        center.saveNow()
        let restored = DownloadCenter(history: .standard)
        check(restored.items == center.items, "download history restores after relaunch")
        check(!center.shouldShowToolbarButton(at: Date().addingTimeInterval(90_000)), "automatic toolbar button expires while history remains")
        center.dismissToolbarButton()
        check(!center.showsToolbarButton && center.items.first?.id == first?.id,
              "dismissing temporary control keeps download history")
        c.open(base + "/download-unknown", inNewTab: false)
        let unknown = await until { center.items.first?.inProgress == true && (center.items.first?.received ?? 0) > 0 }
        check(unknown && center.overallFraction == nil, "unknown-size download reports bytes with indeterminate progress")
        check(center.showsToolbarButton, "a new download restores the dismissed temporary control")
        center.dismissToolbarButton()
        check(center.showsToolbarButton, "dismissing the dropdown cannot hide live download progress")
        let second = center.items.first
        check(first?.fileURL != second?.fileURL, "repeated filenames cannot overwrite an earlier download")
        if let id = second?.id { center.cancel(id) }
        check(center.items.first?.cancelled == true && center.activeCount == 0, "cancel immediately stops progress and keeps cancelled entry")
        check(!center.showsToolbarButton && center.items.count == 2, "dismissed control hides after active work ends without clearing history")
        do {
            let history = DownloadHistoryStore(directory: SessionStore.testDirectory.appending(path: "RestoreCheck"))
            var interrupted = DownloadCenter.Item(); interrupted.received = 128; interrupted.total = 1024
            try history.save([interrupted])
            let interruptedCenter = DownloadCenter(history: history)
            check(interruptedCenter.items.first?.interrupted == true && interruptedCenter.activeCount == 0,
                  "unfinished history restores as interrupted rather than a phantom active download")
            try history.save(first.map { [$0] } ?? [])
            try Data("corrupt".utf8).write(to: history.directory.appending(path: "downloads.json"))
            check(history.load().first?.id == interrupted.id, "corrupt history recovers the previous atomic backup")
        } catch { check(false, "history persistence: \(error.localizedDescription)") }
        center.clearFinished()
        check(center.items.isEmpty && first?.fileURL.map { FileManager.default.fileExists(atPath: $0.path) } == true,
              "clearing history preserves downloaded files")
        check(DownloadCenter(history: .standard).items.isEmpty, "cleared history stays cleared after relaunch")
        print("IKTEST downloadchecks \(failures == 0 ? "PASS" : "FAIL") failures=\(failures)")
    }

    private static func until(_ predicate: () -> Bool) async -> Bool {
        for _ in 0..<500 {
            if predicate() { return true }
            try? await Task.sleep(for: .milliseconds(20))
        }
        return predicate()
    }
}
#endif
