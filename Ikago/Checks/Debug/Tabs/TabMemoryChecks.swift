#if DEBUG
import Foundation

/// Injects memory pressure on disposable loopback pages; never stresses the real Mac's memory.
@MainActor
enum TabMemoryChecks {
    static func run(_ browser: BrowserWindowController, base: String) async {
        var failures = 0
        func check(_ passed: Bool, _ name: String) {
            print("IKTEST resources \(passed ? "PASS" : "FAIL") \(name)")
            if !passed { failures += 1 }
        }
        guard WebProfiles.isTestMode, let host = URL(string: base)?.host else { check(false, "disposable fixture URL required"); return }
        let state = browser.state
        for tab in Array(state.tabs) { state.closeTab(tab.id, removingPin: true) }
        browser.open(base, inNewTab: true)
        guard let visible = state.activeTab, let background = state.newTab(url: base + "?background", select: false) else { return }
        for _ in 0..<100 {
            if browser.content.controller(for: background.id)?.page != nil,
               !background.isLoading, !visible.isLoading { break }
            try? await Task.sleep(for: .milliseconds(50))
        }
        try? await Task.sleep(for: .milliseconds(250))
        guard let controller = browser.content.controller(for: background.id), let page = controller.page else { check(false, "background fixture loaded"); return }
        let memory = browser.content.memoryManagement
        state.browserPreferences.resourcePolicy = .responsive
        await memory.reclaim(.warning)
        check(controller.page != nil, "Responsive retains pages on warning")
        state.browserPreferences.resourcePolicy = .conservative
        await memory.reclaim(.normal)
        check(controller.page != nil, "normal pressure never expires pages")
        background.isPlayingAudio = true
        await memory.reclaim(.critical)
        check(controller.page != nil, "playing audio is protected")
        background.isPlayingAudio = false; background.cameraActive = true
        await memory.reclaim(.critical)
        check(controller.page != nil, "camera capture is protected")
        background.cameraActive = false; background.microphoneActive = true
        await memory.reclaim(.critical)
        check(controller.page != nil, "microphone capture is protected")
        background.microphoneActive = false; background.pinned = true
        await memory.reclaim(.critical)
        check(controller.page != nil, "protected pins stay resident")
        background.pinned = false
        state.browserPreferences.hibernationExceptions = host
        await memory.reclaim(.critical)
        check(controller.page != nil, "site exceptions stay resident")
        state.browserPreferences.hibernationExceptions = ""
        _ = try? await page.callAsync("const input=document.createElement('input');input.id='resource-draft';document.body.append(input);input.value='unsaved';return true;")
        await memory.reclaim(.critical)
        check(controller.page != nil, "unsaved form values stay resident")
        _ = try? await page.callAsync("document.getElementById('resource-draft').remove();const frame=document.createElement('iframe');frame.id='resource-frame';frame.sandbox='allow-scripts';frame.srcdoc='<p>Isolated frame</p>';document.body.append(frame);await new Promise(resolve=>frame.onload=resolve);return true;")
        await memory.reclaim(.critical)
        check(controller.page != nil, "uninspectable embedded documents are protected")
        _ = try? await page.callAsync("document.getElementById('resource-frame').remove();return true;")
        // Idle sleep, as Chrome's Memory Saver and Edge's sleeping tabs: never with Responsive; Balanced after 2 hours.
        state.browserPreferences.resourcePolicy = .responsive
        memory.sleepIdleTabs(now: Date().addingTimeInterval(10 * 3600))
        check(controller.page != nil, "Responsive never sleeps tabs on a timer")
        state.browserPreferences.resourcePolicy = .balanced
        memory.sleepIdleTabs(now: Date().addingTimeInterval(3600))
        check(controller.page != nil, "Balanced keeps a tab unused for an hour")
        memory.sleepIdleTabs(now: Date().addingTimeInterval(3 * 3600))
        check(controller.page == nil && background.isHibernating, "Balanced sleeps a tab unused for over 2 hours")
        check(browser.content.controller(for: visible.id)?.page != nil, "the visible tab never sleeps on a timer")
        state.select(background.id)
        for _ in 0..<100 {
            if controller.page != nil, !background.isLoading { break }
            try? await Task.sleep(for: .milliseconds(50))
        }
        state.select(visible.id)
        state.browserPreferences.resourcePolicy = .conservative
        await memory.reclaim(.warning)
        check(controller.page == nil && background.isHibernating, "Conservative releases a safe inactive page on warning")
        check(browser.content.controller(for: visible.id)?.page != nil, "visible page stays resident")
        state.select(background.id)
        for _ in 0..<100 {
            if controller.page != nil, !background.isLoading { break }
            try? await Task.sleep(for: .milliseconds(50))
        }
        check(controller.page != nil && !background.isHibernating, "selecting a released page restores it")
        controller.load(base + "?history")
        for _ in 0..<100 {
            if !background.isLoading, background.canGoBack { break }
            try? await Task.sleep(for: .milliseconds(50))
        }
        state.select(visible.id)
        state.browserPreferences.resourcePolicy = .responsive
        await memory.reclaim(.critical)
        check(controller.page != nil && background.canGoBack, "native navigation history stays intact under pressure")
        let fresh = state.newTab(url: base + "?critical", select: false)
        for _ in 0..<100 {
            if let fresh, browser.content.controller(for: fresh.id)?.page != nil, !fresh.isLoading { break }
            try? await Task.sleep(for: .milliseconds(50))
        }
        await memory.reclaim(.critical)
        check(fresh?.isHibernating == true, "Responsive releases safe inactive pages under critical pressure")
        if let data = try? JSONEncoder().encode(state.browserPreferences),
           let restored = try? JSONDecoder().decode(BrowserPreferences.self, from: data) {
            check(restored.resourcePolicy == .responsive, "resource preference round-trips")
        } else { check(false, "resource preference decodes") }
        print("IKTEST resourcechecks \(failures == 0 ? "PASS" : "FAIL") failures=\(failures)")
    }
}
#endif
