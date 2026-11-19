#if DEBUG
import AppKit
import SwiftUI
import WebKit

/// Debug-only scripted driver for unattended smoke tests. Active only with
/// IKAGO_TEST_MODE=1 (in-memory website data, temporary session) and IKAGO_TEST_ACTIONS, e.g.
///   "wait:4;dump;close;wait:1;dump;reopen;split;pin;layout:horizontal;mode:dark;dump;quit"
/// Actions go through the same command paths as menus/shortcuts; `dump` prints one
/// `IKTEST {json}` line with model + live page state.
@MainActor
enum TestDriver {
    static func runIfRequested(controller: BrowserWindowController) {
        let env = ProcessInfo.processInfo.environment
        guard env["IKAGO_TEST_MODE"] != nil, let script = env["IKAGO_TEST_ACTIONS"] else { return }
        setvbuf(stdout, nil, _IOLBF, 0)  // keep output if the process dies
        let actions = script.split(separator: ";").map { $0.trimmingCharacters(in: .whitespaces) }
        Task { @MainActor in
            for action in actions { await perform(action, controller) }
        }
    }

    private static func perform(_ action: String, _ c: BrowserWindowController) async {
        let parts = action.split(separator: ":", maxSplits: 1).map(String.init)
        let arg = parts.count > 1 ? parts[1] : ""
        let state = c.state
        print("IKTEST action \(action)")
        switch parts[0] {
        case "wait": try? await Task.sleep(for: .seconds(Double(arg) ?? 1))
        case "dragprobe":  // <seconds>: selects two tabs, prints screen points to drag the first below the fifth (a real drag
                           // needs posted mouse events from outside, e.g. a CGEvent script), then prints the order
            let s = c.state
            let made = (1...5).compactMap { s.newTab(url: "https://example.com/?drag\($0)") }
            try? await Task.sleep(for: .seconds(1.5))
            c.chrome.selectedTabIDs = [made[0].id, made[1].id]
            try? await Task.sleep(for: .milliseconds(500))
            func point(_ id: String) -> String {
                guard let f = LayoutChecks.frames["sidebar-tab-\(id)"], let w = c.window, let content = w.contentView else { return "none" }
                let p = w.convertPoint(toScreen: content.convert(NSPoint(x: f.midX, y: content.isFlipped ? f.midY : content.bounds.height - f.midY), to: nil))
                let h = NSScreen.screens[0].frame.height
                return "\(Int(p.x)),\(Int(h - p.y))"
            }
            NSApp.activate(ignoringOtherApps: true); c.window?.makeKeyAndOrderFront(nil)
            print("IKTEST dragfrom \(point(made[0].id)) dragto \(point(made[4].id)) order=\(s.regularTabs.map(\.url).joined(separator: " "))")
            fflush(stdout)
            try? await Task.sleep(for: .seconds(Double(arg) ?? 8))
            print("IKTEST dragafter order=\(s.regularTabs.map(\.url).joined(separator: " ")) selected=\(c.chrome.selectedTabIDs.count)")
        case "groupdragprobe":  // <seconds>: three groups; prints screen points to drag the last group's header onto the
                                // first one's top edge (before) and onto the middle one's centre (inside), for posted drags
            let s = c.state
            let groups = ["GA", "GB", "GC"].map { name in
                let folder = s.createFolder(named: name)
                _ = s.newTab(url: "https://example.com/?\(name)", select: false, folderID: folder.id)
                s.toggleFolder(folder.id)  // shut, so headers sit one under another
                return folder
            }
            try? await Task.sleep(for: .seconds(1.5))
            func point(_ id: String, dy: CGFloat) -> String {
                guard let f = LayoutChecks.frames["sidebar-folder-\(id)"], let w = c.window, let content = w.contentView else { return "none" }
                let y = f.minY + dy
                let p = w.convertPoint(toScreen: content.convert(NSPoint(x: f.midX, y: content.isFlipped ? y : content.bounds.height - y), to: nil))
                return "\(Int(p.x)),\(Int(NSScreen.screens[0].frame.height - p.y))"
            }
            NSApp.activate(ignoringOtherApps: true); c.window?.makeKeyAndOrderFront(nil)
            func describe() -> String {
                s.orderedSpaceFolders.map { f in f.name + (f.parentID.flatMap { p in s.folders.first { $0.id == p }?.name }.map { "<" + $0 } ?? "") }
                    .joined(separator: " ")
            }
            print("IKTEST groupdrag from \(point(groups[2].id, dy: 17)) before \(point(groups[0].id, dy: 4)) into \(point(groups[1].id, dy: 17)) order=\(describe())")
            fflush(stdout)
            var sawDrag = false
            for _ in 0..<Int((Double(arg) ?? 8) * 10) {
                try? await Task.sleep(for: .milliseconds(100))
                if c.chrome.draggingFolderID != nil { sawDrag = true }
            }
            print("IKTEST groupdragafter order=\(describe()) dragStarted=\(sawDrag) window=\(c.window?.frame ?? .zero)")
        case "newtabprobe":  // ⌘T, type an address and press Return in every layout and address style, fast and slow;
                             // prints whether the new tab exists, is selected, is in the Top Bar row, and shows its page
            let s = c.state
            s.newTabMode = .commandBar
            var n = 0
            for layout in ["tabs", "sidebar"] {
                LayoutSwitch.set(tabs: layout == "tabs", state: s)
                for style in [AddressStyle.integrated, .floating] {
                    s.addressStyle = style
                    try? await Task.sleep(for: .milliseconds(600))
                    for delay in [0, 30, 400] {
                        n += 1
                        let url = "https://example.com/?newtab\(n)"
                        let before = Set(s.tabs.map(\.id))
                        c.newTab()
                        if delay > 0 { try? await Task.sleep(for: .milliseconds(delay)) }
                        c.palette.query = url
                        c.palette.commit()
                        try? await Task.sleep(for: .milliseconds(1500))
                        let added = s.tabs.filter { !before.contains($0.id) }
                        let target = s.tabs.first { $0.url.contains("newtab\(n)") }
                        let active = s.activeTab
                        let inRow = target.map { t in s.looseTabs.contains { $0.id == t.id } } ?? false
                        let shown = c.activeController?.tab.id == active?.id && c.activeController?.page != nil
                        print("IKTEST newtab layout=\(layout) style=\(style.rawValue) delay=\(delay) added=\(added.count) found=\(target != nil) selected=\(target?.id == active?.id) inRow=\(inRow) shown=\(shown) activeURL=\(active?.url ?? "nil") blanks=\(s.tabs.filter { $0.url == "about:blank" }.count)")
                        fflush(stdout)
                    }
                }
            }
        case "perfstats":
            // Shows the performance overlay and prints what it reads after a few seconds.
            c.togglePerformanceStats(nil)
            try? await Task.sleep(for: .seconds(Double(arg) ?? 3))
            func labels(_ view: NSView) -> [String] { ((view as? NSTextField).map { [$0.stringValue] } ?? []) + view.subviews.flatMap(labels) }
            let overlay = c.window?.contentView?.subviews.first { $0 is PerformanceOverlay }
            print("IKTEST perfstats pid=\(getpid()) frame=\(overlay?.frame ?? .zero) text=\(overlay.map(labels) ?? [])")
        case "new": state.newTab(url: arg)
        case "open": c.open(arg, inNewTab: false)
        case "close": c.closeCurrentTab(nil)
        case "reopen": c.reopenClosedTab(nil)
        case "split": c.splitView(nil)
        case "unsplit": c.unsplitView(nil)
        case "rotate": c.toggleSplitOrientation(nil)
        case "pin": c.togglePinTab(nil)
        case "next": c.nextTab(nil)
        case "select": state.selectTab(at: (Int(arg) ?? 1) - 1)
        case "sidebar": c.toggleSidebar()
        case "rail": c.toggleCompactSidebar(nil)
        case "notch": state.browserPreferences.fullScreenUnderNotch = arg == "on" ? true : nil
        case "frames":  // window, shell and active page geometry
            print("IKTEST sidebar visible=\(state.sidebarVisible) compact=\(String(describing: state.browserPreferences.sidebarCompact)) rail=\(state.showsSidebarRail) immersive=\(state.isImmersive) peeking=\(c.chrome.peeking) lights=\(c.fullScreenControls.isShown) \(c.fullScreenControls.debugFrame)")
            if let w = c.window, let content = w.contentView {
                print("IKTEST frames window=\(w.frame) content=\(content.frame) shell=\(content.subviews.first?.frame ?? .zero) safe=\(content.safeAreaInsets)")
                if let page = c.activeController?.page?.contentView {
                    var v: NSView? = page
                    while let x = v, x !== content { print("IKTEST   \(type(of: x)) frame=\(x.frame) safe=\(x.safeAreaInsets)"); v = x.superview }
                    if let web = page as? WKWebView { print("IKTEST   obscured=\(web.obscuredContentInsets)") }
                }
            }
        case "layout": LayoutSwitch.set(tabs: arg == "tabs", state: state)  // sidebar | tabs
        case "mode": if let m = ColorMode(rawValue: arg) { state.colorMode = m }
        case "preset": if let p = SpaceColors.presets.first(where: { $0.name.lowercased() == arg }) { state.setColors(p.colors, for: state.activeSpaceID) }
        case "peek": c.chrome.peek()
        case "movetowindow": if let id = state.activeTabID { c.moveToNewWindow(id) }  // Move Tab to New Window
        case "closewindow": BrowserWindows.others.last?.window?.close()  // the most recent window after the first
        case "windows":  // every regular window: its tabs and frame
            for (i, w) in BrowserWindows.all.enumerated() {
                print("IKTEST window \(i) tabs=\(w.state.tabs.map(\.url)) active=\(w.state.activeTab?.url ?? "-") frame=\(w.window.map { NSStringFromRect($0.frame) } ?? "-")")
            }
        case "peeklink": c.peekLink(arg)  // the Shift-click link preview
        case "layoutprobe": await LayoutSwitchProbe.run(c, switches: Int(arg) ?? 4)
        case "relaunch": AppRelaunch.relaunch(URL(fileURLWithPath: arg))  // Opens this app instead of Ikago.
        case "engine":  // Chooses an engine in Settings without relaunching.
            if let engine = BrowserEngine(rawValue: arg) { state.browserPreferences.preferredEngine = engine; state.saveNow() }
        case "page": if let p = InternalPage(rawValue: arg) { c.openPage(p) }
        case "mute": c.toggleMuteTab(nil)
        case "zoomin": c.zoomInPage(nil)
        case "palette": c.showCommandPalette(newTab: arg == "new")
        case "palettecommit": c.palette.query = arg; c.palette.commit()  // <text>: types into the open address field and presses Return
        case "palettequery": c.palette.userEdited(arg)
        case "palettecommit": c.palette.commit()
        case "palettescope": _ = c.palette.toggleScope(Int(arg) ?? 0)
        case "palettedown": c.palette.moveSelection(1); c.palette.query = c.palette.query  // same text written back
        case "suggestions": print("IKTEST suggestions \(c.palette.selection) " + c.palette.suggestions.map(\.title).joined(separator: " | "))
        case "suggestionkinds": print("IKTEST suggestionkinds " + c.palette.suggestions.map { "\($0.source)" }.joined(separator: ","))
        case "find": c.showFindBar(); c.find.text = arg; c.find.search()
        case "findclose": c.closeFindBar()
        case "js":  // function body in the isolated world (may await, must return); prints the result
            do {
                let result = try await c.activeController?.page?.callAsync(arg)
                print("IKTEST js \(result.map { "\($0)" } ?? "nil")")
            } catch { print("IKTEST js error \(error.localizedDescription)") }
        case "pip":  // the media island's PiP button on the active tab, then the page's video presentation
            if let id = state.activeTabID {
                let tab = state.tab(id)
                print("IKTEST pip before hasVideo=\(tab?.playback.hasVideo ?? false) playing=\(tab?.playback.playing ?? false) engine=\(tab?.engine.map { "\($0)" } ?? "-")")
                if let web = (c.activeController?.page as? WebKitTab)?.webView {
                    let names = ["_updateMediaPlaybackControlsManager", "_canTogglePictureInPicture", "_togglePictureInPicture", "_isPictureInPictureActive"]
                    web.perform(NSSelectorFromString(names[0]))
                    try? await Task.sleep(for: .milliseconds(300))
                    var can = "n/a"
                    if let imp = web.method(for: NSSelectorFromString(names[1])), web.responds(to: NSSelectorFromString(names[1])) {
                        typealias Getter = @convention(c) (AnyObject, Selector) -> Bool
                        can = "\(unsafeBitCast(imp, to: Getter.self)(web, NSSelectorFromString(names[1])))"
                    }
                    let prefs = web.configuration.preferences
                    let keys = ["allowsPictureInPictureMediaPlayback", "_allowsPictureInPictureMediaPlayback", "pictureInPictureAPIEnabled", "_pictureInPictureAPIEnabled"]
                    print("IKTEST pip prefs " + keys.map { key in prefs.responds(to: NSSelectorFromString(key)) ? "\(key)=\(prefs.value(forKey: key) ?? "nil")" : "\(key)=-" }.joined(separator: " "))
                    let enabled = try? await c.activeController?.page?.callAsync("return String(document.pictureInPictureEnabled) + ' supports=' + String(document.querySelector('video')?.webkitSupportsPresentationMode?.('picture-in-picture'))")
                    print("IKTEST pip document \(enabled.map { "\($0)" } ?? "nil")")
                    print("IKTEST pip spi responds=\(names.map { web.responds(to: NSSelectorFromString($0)) }) canToggle=\(can)")
                }
                _ = try? await c.activeController?.page?.callAsync("""
                    window.__ikModes = []; const v = document.querySelector('video');
                    v?.addEventListener('webkitpresentationmodechanged', () => window.__ikModes.push(v.webkitPresentationMode));
                    v?.addEventListener('enterpictureinpicture', () => window.__ikModes.push('enter'));
                    v?.addEventListener('leavepictureinpicture', () => window.__ikModes.push('leave'));
                    return true
                    """)
                if arg == "script", let page = c.activeController?.page {
                    do { try MediaPictureInPicture.finish(try await page.callAsync(MediaPictureInPicture.source), page: page) }
                    catch { print("IKTEST pip script error \(error.localizedDescription)") }
                } else if arg == "standard" {
                    let r = try? await c.activeController?.page?.callAsync("try { await document.querySelector('video').requestPictureInPicture(); return 'ok' } catch (e) { return 'error ' + e.name + ': ' + e.message }")
                    print("IKTEST pip standard \(r.map { "\($0)" } ?? "nil")")
                } else {
                    c.pictureInPicture(id)
                }
                try? await Task.sleep(for: .seconds(2))
                let modes = try? await c.activeController?.page?.callAsync("return JSON.stringify(window.__ikModes)")
                print("IKTEST pip events \(modes.map { "\($0)" } ?? "nil")")
                let mode = try? await c.activeController?.page?.callAsync("const v = document.querySelector('video'); return v ? String(v.webkitPresentationMode ?? '') + ' pipElement=' + String(document.pictureInPictureElement === v) + ' src=' + (v.currentSrc || '').slice(0, 30) : 'no video'")
                let sheet = c.window?.attachedSheet.map { _ in "alert" } ?? "none"
                print("IKTEST pip after \(mode.map { "\($0)" } ?? "nil") sheet=\(sheet) windows=\(NSApp.windows.filter(\.isVisible).map { $0.title })")
            }
        case "permission":  // answer the visible permission prompt: visit | day | always | block | dismiss (allow = always)
            let grant = arg == "allow" ? .always : PermissionGrant(rawValue: arg)
            c.finishPermission(grant.map { .allow($0) } ?? (arg == "block" ? .block : .dismiss))
        case "snapshot": snapshot(c.window, to: arg)
        case "updatecard":  // security | features | download | off: a sample update card in the frontmost window
            let notes = arg == "security" ? ["**Chromium 157.0.8123.45:** the latest security and stability fixes from the Chromium project."]
                : arg == "download" ? ["**Download needed:** copies before 0.5.1 can't install this update by themselves. [Download Ikago 0.5.1 from GitHub](https://github.com/FraudMomo/Ikago/releases/latest), open the DMG and drag Ikago to Applications to replace your copy."]
                : ["**Top Tabs:** the toolbar has its own controls, and the bar's height is yours to choose.",
                   "**Downloads:** Download Image and Download Linked File work in every page's menu."]
            let summary = UpdateSummary(version: arg == "security" ? "0.4.2" : "0.5.0", security: arg == "security",
                                        chromium: arg == "security" ? "157.0.8123.45" : nil, notes: notes,
                                        downloadPage: arg == "download" ? URL(string: "https://github.com/FraudMomo/Ikago/releases/latest") : nil)
            AppUpdates.shared.prompt.phase = arg == "off" ? nil : .found(summary, downloaded: false)
            NSApp.activate(); c.window?.makeKeyAndOrderFront(nil)
        case "windowshot":  // <png>: the window as it appears on screen, glass and pages included
            if let window = c.window, let content = window.contentView { _ = PeekShot.measure(content, window: window, save: arg) }
        case "grabheader":  // <png>: drops the page-edge header at the page's middle and captures the window
            state.browserPreferences.pageGrab = .header
            c.pageWindowGrab?.header.show(in: c.content.view, at: c.content.view.bounds.midX)
            try? await Task.sleep(for: .milliseconds(500))
            if let window = c.window, let content = window.contentView { _ = PeekShot.measure(content, window: window, save: arg) }
        case "corners": corners(c, to: arg)
        case "fullscreen":  // toggles window full screen, then reports every window of the app (arg "notch": on a notched screen)
            if arg == "notch", let screen = NSScreen.screens.first(where: { $0.safeAreaInsets.top > 0 }), let w = c.window {
                w.setFrame(NSRect(x: screen.frame.midX - 600, y: screen.frame.midY - 380, width: 1200, height: 760), display: true)
                try? await Task.sleep(for: .seconds(1))
            }
            c.window?.toggleFullScreen(nil)
            try? await Task.sleep(for: .seconds(2))
            for w in NSApp.windows where w.isVisible {
                print("IKTEST window \(type(of: w)) frame=\(w.frame) alpha=\(w.alphaValue) fs=\(w.styleMask.contains(.fullScreen)) main=\(w === c.window) ikagoFS=\(w.isInFullScreen) band=\((w as? BrowserWindow)?.fullScreenTopBand ?? -1) screen=\(w.screen?.frame ?? .zero) onSpace=\(w.isOnActiveSpace) occluded=\(!w.occlusionState.contains(.visible)) content=\(w.contentView.map { "\($0.frame) hidden=\($0.isHidden) alpha=\($0.alphaValue)" } ?? "nil")")
            }
        case "pageshot":  // the page itself, rendered by WebKit
            if let image = try? await c.activeController?.page?.snapshot(), let tiff = image.tiffRepresentation,
               let png = NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:]) {
                try? png.write(to: URL(fileURLWithPath: arg))
                print("IKTEST pageshot \(arg) \(Int(image.size.width))x\(Int(image.size.height))")
            }
        case "settings": c.showSettings()
        case "cleardata": c.showClearData()
        case "back": c.goBack()
        case "scrollprobe":  // <seconds>: scrolls the page smoothly while sampling CPU (app + its WebKit processes)
            let seconds = Double(arg) ?? 8
            let sampler = PerformanceSampler()
            var samples: [PerformanceSample] = []
            sampler.start { samples.append($0) }
            let page = c.activeController?.page
            Task { _ = try? await page?.callAsync("const end = Date.now() + \(Int(seconds * 1000)); while (Date.now() < end) { window.scrollBy(0, 24); await new Promise(r => requestAnimationFrame(r)); } return true") }
            try? await Task.sleep(for: .seconds(seconds + 1))
            sampler.stop()
            let cpu = samples.dropFirst().map(\.cpu)
            let app = samples.dropFirst().map { $0.rows.filter { $0.name.hasPrefix("Ikago") }.reduce(0) { $0 + $1.cpu } }
            let web = samples.dropFirst().map { $0.rows.filter { $0.name.contains("WebContent") }.reduce(0) { $0 + $1.cpu } }
            func avg(_ v: [Double]) -> Int { v.isEmpty ? 0 : Int(v.reduce(0, +) / Double(v.count)) }
            print("IKTEST scrollprobe total avg=\(avg(cpu))% max=\(Int(cpu.max() ?? 0))% app=\(avg(app))% webcontent=\(avg(web))%")
        case "siteinfoclick":  // hovers the Top Tabs address bar, clicks its site button, reports the card
            guard let window = c.window, let field = c.chrome.addressFieldFrame, let height = window.contentView?.bounds.height else {
                print("IKTEST siteinfoclick no address frame"); break
            }
            let point = NSPoint(x: field.maxX - 15, y: height - field.midY)
            func send(_ type: NSEvent.EventType) {
                if let event = NSEvent.mouseEvent(with: type, location: point, modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime,
                                                  windowNumber: window.windowNumber, context: nil, eventNumber: 0, clickCount: 1, pressure: type == .mouseMoved ? 0 : 1) {
                    window.sendEvent(event)
                }
            }
            send(.mouseMoved)
            try? await Task.sleep(for: .milliseconds(400))
            send(.leftMouseDown); send(.leftMouseUp)
            try? await Task.sleep(for: .milliseconds(500))
            print("IKTEST siteinfoclick shown=\(c.chrome.showSiteInfo) palette=\(c.chrome.showPalette) editing=\(c.chrome.inlineAddress)")
        case "settingsshot":  // <category>[/<section page>][@<w>[x<h>]]|<png>: Settings drawn offscreen at a window's size
            let parts = arg.split(separator: "|", maxSplits: 1).map(String.init)
            guard parts.count == 2 else { break }
            let sized = parts[0].split(separator: "@").map(String.init)
            let names = sized[0].split(separator: "/").map(String.init)
            // @<width> or @<width>x<height>, for long pages.
            let size = (sized.dropFirst().first ?? "").split(separator: "x").compactMap { Double($0) }
            let width = CGFloat(size.first ?? 1180), height = CGFloat(size.count > 1 ? size[1] : 820)
            if let category = SettingsCategory(rawValue: names[0]) { state.settingsCategory = category }
            if names.count > 1 { state.settingsSubpage[state.settingsCategory] = names[1] }
            let colors = state.palette
            let host = NSHostingView(rootView: SettingsPage(state: state, commands: c)
                .environment(\.colorScheme, colors.isDark ? .dark : .light).environment(\.pagePalette, colors).tint(colors.accent))
            host.frame = NSRect(x: 0, y: 0, width: width, height: height)
            let window = NSWindow(contentRect: host.frame, styleMask: [.borderless], backing: .buffered, defer: false)
            window.contentView = host
            try? await Task.sleep(for: .milliseconds(600))
            host.layoutSubtreeIfNeeded()
            if let rep = host.bitmapImageRepForCachingDisplay(in: host.bounds) {
                host.cacheDisplay(in: host.bounds, to: rep)
                try? rep.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: parts[1]))
            }
            window.contentView = nil
        case "typefast":  // new|current[,delay ms]: ⌘T or ⌘L, two letters, more after the field's re-focus; prints the text
            let typeArgs = arg.split(separator: ",").map(String.init)
            c.showCommandPalette(newTab: typeArgs.first != "current")
            func typeKeys(_ text: String) async {
                guard let window = c.window else { return }
                for ch in text {
                    for type: NSEvent.EventType in [.keyDown, .keyUp] {
                        if let event = NSEvent.keyEvent(with: type, location: .zero, modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime,
                                                        windowNumber: window.windowNumber, context: nil, characters: String(ch),
                                                        charactersIgnoringModifiers: String(ch), isARepeat: false, keyCode: 0) {
                            window.sendEvent(event)
                        }
                    }
                    try? await Task.sleep(for: .milliseconds(40))
                }
            }
            try? await Task.sleep(for: .milliseconds(Int(typeArgs.dropFirst().first ?? "") ?? 20))
            await typeKeys("go")
            print("IKTEST typefast early query=\(c.palette.query) responder=\(c.window?.firstResponder.map { String(describing: Swift.type(of: $0)) } ?? "nil")")
            try? await Task.sleep(for: .milliseconds(600))
            await typeKeys("ogle")
            try? await Task.sleep(for: .milliseconds(200))
            print("IKTEST typefast \(arg) query=\(c.palette.query)")
        case "peekshot":  // <dir>: Open as Tab on a page with a red top strip and blue bottom strip; captures the window
            for (label, keep) in [("normal", false), ("kept", true)] {
                let url = "https://example.com/?peekshot-\(label)"
                if keep {
                    c.peekLink(url)
                    for _ in 0..<60 where c.peekController?.page?.isLoading != false { try? await Task.sleep(for: .milliseconds(100)) }
                    try? await Task.sleep(for: .milliseconds(500))
                    c.openPeek()
                } else {
                    c.open(url, inNewTab: true)
                }
                try? await Task.sleep(for: .seconds(2))
                guard let page = c.activeController?.page else { continue }
                _ = try? await page.callAsync("""
                    for (const [id, css] of [['ik-top', 'top:0'], ['ik-bottom', 'bottom:0']]) {
                      let el = document.getElementById(id) || document.body.appendChild(Object.assign(document.createElement('div'), {id}));
                      el.style.cssText = 'position:fixed;left:0;right:0;height:12px;z-index:2147483647;' + css + ';background:' + (id === 'ik-top' ? '#ff0000' : '#0000ff');
                    }
                    return true
                    """)
                try? await Task.sleep(for: .milliseconds(600))
                print("IKTEST peekshot \(label) \(PeekShot.measure(page.contentView, window: c.window, save: arg.isEmpty ? nil : arg + "/peek-\(label).png"))")
            }
        case "passwordlist":  // <png>: the login list under a sample field over the current page, captured with the window
            if let window = c.window, let content = window.contentView {
                let logins = ["sam@example.com", "work@example.com", "test.account"].map {
                    PasswordVault.Login(id: UUID(), site: "example.com", title: nil, username: $0, secret: Data(), created: 0)
                }
                let field = NSRect(x: content.bounds.midX - 160, y: content.bounds.height - 260, width: 320, height: 36)
                Task { _ = await PasswordSuggestionsPresenter.shared.present(logins, site: "example.com", anchor: field, in: window) }
                try? await Task.sleep(for: .milliseconds(400))
                PasswordSuggestionsPresenter.shared.select(1)
                try? await Task.sleep(for: .milliseconds(600))
                print("IKTEST passwordlist \(PeekShot.measure(content, window: window, save: arg))")
                PasswordSuggestionsPresenter.shared.dismiss()
            }
        case "devices":  // [<png>]: reads Safari's synced tabs (counts only), then shows the list and captures the window
            let model = SafariSyncedTabsModel.shared
            await model.refresh()
            let tabs = model.tabs
            print("IKTEST devices denied=\(model.denied) devices=\(tabs.devices.map { "\($0.kind):\($0.tabs.count)" }) groups=\(tabs.groups.map { "\($0.tabs.count)\($0.profile == nil ? "" : "p")" }) updated=\(tabs.updated.map { "\($0)" } ?? "nil")")
            if !arg.isEmpty, let window = c.window, let content = window.contentView {
                state.browserPreferences.safariDeviceTabs = true
                if !state.chromeLayout.contains(.devices) { state.chromeLayout.place(.devices, in: .sidebarTop) }
                try? await Task.sleep(for: .milliseconds(300))
                c.toggleDevices()
                try? await Task.sleep(for: .milliseconds(1200))
                print("IKTEST devicesshot \(PeekShot.measure(content, window: window, save: arg))")
            }
        case "savecard":  // <png>: the "Save password?" card over the current page, captured with the window
            if let window = c.window, let content = window.contentView {
                PasswordSavePresenter.shared.offer(site: "appstoreconnect.apple.com", username: "sam@example.com",
                                                   password: "sample", update: false, in: c)
                try? await Task.sleep(for: .milliseconds(900))
                print("IKTEST savecard \(PeekShot.measure(content, window: window, save: arg))")
                PasswordSavePresenter.shared.dismiss()
            }
        case "railhit":  // what receives a click on each of the rail's drawn traffic lights
            if let host = c.fullScreenControls.hostView, let frame = c.window?.contentView?.superview {
                for i in 0..<3 {
                    let size = host.bounds.width, spacing = (host.bounds.height - size) / 2
                    let y = host.isFlipped ? size / 2 + CGFloat(i) * spacing : host.bounds.height - size / 2 - CGFloat(i) * spacing
                    let p = frame.convert(NSPoint(x: size / 2, y: y), from: host)
                    var chain: [String] = []
                    var v = frame.hitTest(p)
                    while let view = v, chain.count < 6 { chain.append(String(describing: type(of: view))); v = view.superview }
                    print("IKTEST railhit \(i) host=\(host.frame) hit=\(chain.joined(separator: " < "))")
                }
                if arg == "click", let window = c.window {
                    // A real click on Minimize (the second light).
                    let size = host.bounds.width, spacing = (host.bounds.height - size) / 2
                    let local = NSPoint(x: size / 2, y: host.isFlipped ? size / 2 + spacing : host.bounds.height - size / 2 - spacing)
                    let point = host.convert(local, to: nil)
                    for type: NSEvent.EventType in [.mouseMoved, .leftMouseDown, .leftMouseUp] {
                        if let event = NSEvent.mouseEvent(with: type, location: point, modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime,
                                                          windowNumber: window.windowNumber, context: nil, eventNumber: 0, clickCount: 1, pressure: 1) {
                            window.sendEvent(event)
                        }
                        try? await Task.sleep(for: .milliseconds(150))
                    }
                    try? await Task.sleep(for: .milliseconds(800))
                    print("IKTEST railhit minimized=\(window.isMiniaturized)")
                    window.deminiaturize(nil)
                }
                print("IKTEST railhit subviews=\(c.window?.contentView?.subviews.map { "\(type(of: $0))" } ?? [])")
            } else { print("IKTEST railhit none") }
        case "siteinfoshot":  // <png>: the site popover's content, drawn on the page color
            let colors = state.palette
            let host = NSHostingView(rootView: SiteInfoPopoverPreview.view(state: state, commands: c)
                .background(colors.pageBackground).environment(\.colorScheme, colors.isDark ? .dark : .light))
            host.frame = NSRect(origin: .zero, size: host.fittingSize)
            try? await Task.sleep(for: .milliseconds(300))
            host.layoutSubtreeIfNeeded()
            if let rep = host.bitmapImageRepForCachingDisplay(in: host.bounds) {
                host.cacheDisplay(in: host.bounds, to: rep)
                try? rep.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: arg))
            }
        case "resizeprobe":  // install: record the first tab's resizes and scroll it; report: print them
            guard let page = c.content.controller(for: state.sidebarOrder.first { !$0.pinned }?.id ?? "")?.page else { break }
            if arg == "install" {
                _ = try? await page.callAsync("document.body.style.height = '20000px'; window.scrollTo(0, 5000); window.__ikSizes = []; addEventListener('resize', () => window.__ikSizes.push(innerWidth + 'x' + innerHeight)); return true")
            } else {
                let report = try? await page.callAsync("return JSON.stringify({sizes: window.__ikSizes, scroll: scrollY})")
                print("IKTEST resizeprobe \(report.map { "\($0)" } ?? "nil")")
            }
        case "searchselection":  // selects the page's heading, runs the menu's Search in Ikago, prints the tabs
            guard let web = (c.activeController?.page as? WebKitTab)?.webView as? FileDropWebView else { break }
            _ = try? await c.activeController?.page?.callAsync("const r = document.createRange(); r.selectNodeContents(document.querySelector('h1') || document.body); getSelection().removeAllRanges(); getSelection().addRange(r); return getSelection().toString()")
            let menu = NSMenu()
            let item = NSMenuItem(title: "Search With Google", action: NSSelectorFromString("_searchWeb:"), keyEquivalent: "")
            item.identifier = NSUserInterfaceItemIdentifier("WKMenuItemIdentifierSearchWeb")
            menu.addItem(item)
            let event = NSEvent.mouseEvent(with: .rightMouseDown, location: NSPoint(x: 100, y: 100), modifierFlags: [], timestamp: 0,
                                           windowNumber: c.window?.windowNumber ?? 0, context: nil, eventNumber: 0, clickCount: 1, pressure: 1)!
            web.configurePageMenu(menu, event: event)
            print("IKTEST searchselection items=\(menu.items.map(\.title))")
            if let index = menu.items.firstIndex(where: { $0.title == "Search in Ikago" }) { menu.performActionForItem(at: index) }
            try? await Task.sleep(for: .seconds(1))
            print("IKTEST searchselection tabs=\(state.tabs.map(\.url))")
        case "downloadmenu":  // <image|link>: WebKit's Download item for the element at (100, 100), then the downloads
            guard let web = (c.activeController?.page as? WebKitTab)?.webView as? FileDropWebView else { break }
            let menu = NSMenu()
            let item = NSMenuItem(title: "Download", action: NSSelectorFromString("_downloadImage:"), keyEquivalent: "")
            item.identifier = NSUserInterfaceItemIdentifier(arg == "link" ? "WKMenuItemIdentifierDownloadLinkedFile" : "WKMenuItemIdentifierDownloadImage")
            menu.addItem(item)
            let event = NSEvent.mouseEvent(with: .rightMouseDown, location: NSPoint(x: 100, y: web.bounds.height - 100), modifierFlags: [],
                                           timestamp: 0, windowNumber: c.window?.windowNumber ?? 0, context: nil, eventNumber: 0, clickCount: 1, pressure: 1)!
            web.configurePageMenu(menu, event: event)
            menu.performActionForItem(at: 0)
            try? await Task.sleep(for: .seconds(3))
            print("IKTEST downloadmenu \(DownloadCenter.shared.items.map { "\($0.name) finished=\($0.finished) failed=\($0.failed)" })")
        case "seedhistory":  // <count> visits to made-up sites, spread over the last 30 days
            let now = Date().timeIntervalSince1970
            state.history = (0..<(Int(arg) ?? 300)).map { i in
                Visit(url: "https://site\(i % 40).example/page/\(i)", title: "Page \(i) on site \(i % 40)",
                      time: UInt64((now - Double(i) * 4300) * 1000))
            }
        case "settingscategory": if let category = SettingsCategory(rawValue: arg) { state.settingsCategory = category }
        case "settingssubpage":  // <category>:<subpage title>
            let p = arg.split(separator: ":", maxSplits: 1).map(String.init)
            if p.count == 2, let category = SettingsCategory(rawValue: p[0]) { state.settingsCategory = category; state.settingsSubpage[category] = p[1] }
        case "downloads": c.toggleDownloads()
        case "overview": c.toggleSidebar()
        case "assistant": state.browserPreferences.pageIntelligence = true; c.chrome.showPageAssistant = arg != "off"
        case "newspace": c.chrome.showNewSpace = arg != "off"
        case "groupeditor": c.chrome.editFolderID = arg == "off" ? nil : state.spaceFolders.first?.id
        case "hover":  // <loose tab number>: shows the hover card beside the sidebar, as resting on that tab would
            if let tab = state.looseTabs[safe: (Int(arg) ?? 1) - 1], let content = c.window?.contentView {
                c.chrome.hoverTabAnchor = CGRect(x: 20, y: content.bounds.height - 260, width: CGFloat(state.sidebarWidth) - 20, height: 34)
                c.chrome.hoverImage = await c.previewImage(tab.id)
                c.chrome.hoverTabID = tab.id
            }
        case "sidebarshortcuts": state.browserPreferences.sidebarShortcuts = arg == "on" ? true : nil
        case "labelstyle": if let style = GroupLabelStyle(rawValue: arg) { state.groupLabelStyle = style }
        case "sidebartoptabs": state.browserPreferences.sidebarTopTabs = arg == "on" ? true : nil
        case "sidebargroups": state.browserPreferences.sidebarGroupStyle = SidebarGroupStyle(rawValue: arg)
        case "sidebartranslucency": state.browserPreferences.translucentSidebar = arg == "on"
        case "glass": state.useGlass = arg != "off"
        case "inset": state.frameInset = Double(arg) ?? 8
        case "tabsbar": state.browserPreferences.tabsBarHeight = Double(arg)  // Top Tabs bar height, points
        case "addressbuttons":  // <reload|site>:<on|off>
            let p = arg.split(separator: ":").map(String.init)
            if p.first == "reload" { state.chromeLayout.addressShowsReload = p.last == "on" }
            if p.first == "site" { state.chromeLayout.addressShowsSiteInfo = p.last == "on" }
        case "chrome":  // place:<item>:<zone>[:<before>] | remove:<item>:top|side | reset
            let p = arg.split(separator: ":").map(String.init)
            if p.first == "reset" { state.chromeLayout = ChromeLayout() }
            if p.first == "place", p.count >= 3, let item = ChromeItem(rawValue: p[1]), let zone = ChromeZone(rawValue: p[2]) {
                state.chromeLayout.place(item, in: zone, before: p.count > 3 ? ChromeItem(rawValue: p[3]) : nil)
            }
            if p.first == "remove", p.count >= 2, let item = ChromeItem(rawValue: p[1]) { state.chromeLayout.remove(item) }
            print("IKTEST chrome \(state.chromeLayout.sidebarTop.map(\.rawValue)) \(state.chromeLayout.sidebarBottom.map(\.rawValue))")
        case "newtabfocus": state.focusAddressBarOnNewTab = arg == "on"
        case "newtab": c.newTab()
        case "newtabmode": if let m = NewTabMode(rawValue: arg) { state.newTabMode = m }
        case "homepage": state.homepage = arg
        case "separate": if let id = state.activeTabID { state.separate(id) }
        case "unsplitall": state.splits = []
        case "panes":  // each visible pane's size, in pane order
            print("IKTEST panes layout=\(state.splitLayout) " + state.visibleTabIDs.map { id in
                c.content.controller(for: id).map { NSStringFromSize($0.hostView.frame.size) } ?? "-" }.joined(separator: " "))
        case "address": c.showCommandPalette(newTab: false)
        case "dropedge":  // <tab number in sidebar>:<left|right|top|bottom>
            let parts = arg.split(separator: ":").map(String.init)
            let edges: [String: SplitEdge] = ["left": .left, "right": .right, "top": .top, "bottom": .bottom]
            if parts.count == 2, let tab = state.sidebarOrder[safe: (Int(parts[0]) ?? 1) - 1], let edge = edges[parts[1]] {
                state.splitWithDropped(tab.id, edge: edge)
            }
        case "foldercolor": if let f = state.spaceFolders.first { state.setFolderTag(f.id, to: FolderTag(rawValue: arg)) }
        case "groupstyle": if let style = GroupLabelStyle(rawValue: arg) { withAnimation(.ikago) { state.groupLabelStyle = style } }
        case "bookmarkbar": state.showsBookmarksBar = arg != "off"
        case "bookmarkdrawer": state.sidebarBookmarksExpanded = arg != "off"
        case "addressstyle": if let s = AddressStyle(rawValue: arg) { state.addressStyle = s }
        case "inspector":
            c.toggleDevTools(nil)
            try? await Task.sleep(for: .seconds(1.5))
            print("IKTEST inspector visible=\(c.activeController?.page?.isInspectorVisible ?? false) extras=\(c.activeController?.page?.webView.configuration.preferences.value(forKey: "developerExtrasEnabled") ?? "nil")")
        case "responder": print("IKTEST responder \(c.window?.firstResponder.map { "\(type(of: $0))" } ?? "nil") query='\(c.palette.query)'")
        case "inline": print("IKTEST inline \(c.chrome.inlineAddress) palette=\(c.chrome.showPalette) query=\(c.palette.query)")
        case "space":  // name|symbol|isolated
            let p = arg.split(separator: "|").map(String.init)
            state.createSpace(name: p[0], symbol: p.count > 1 ? p[1] : "star", isolated: p.count > 2 && p[2] == "1")
        case "switchspace": if let i = Int(arg), state.spaces.indices.contains(i - 1) { state.switchSpace(state.spaces[i - 1].id) }
        case "deletespace": if let i = Int(arg), state.spaces.indices.contains(i - 1) { state.deleteSpace(state.spaces[i - 1].id) }
        case "groupdemo":  // groups for screenshots: Work (blue, open), Reading (orange, collapsed), Old (green, hidden), loose tabs
            func group(_ name: String, _ tag: FolderTag, _ pages: [String]) -> TabFolder {
                let folder = state.createFolder(named: name)
                state.setFolderTag(folder.id, to: tag)
                for page in pages { _ = state.newTab(url: "https://example.com/?\(page)", select: false, folderID: folder.id) }
                return folder
            }
            _ = group("Work", .blue, ["mail", "docs", "plan"])
            let reading = group("Reading", .orange, ["news", "blog"])
            state.toggleFolder(reading.id)
            let old = group("Old", .green, ["archive"])
            for page in ["one", "two", "three"] { _ = state.newTab(url: "https://example.com/?\(page)", select: false) }
            c.hideGroup(old.id)
            if let first = state.tabs(in: state.folders.first { $0.name == "Work" }!).dropFirst().first { state.select(first.id) }
        case "chipprobe":  // <seconds>: prints the Work chip's screen point (for a posted click), then whether it collapsed
            guard let work = state.folders.first(where: { $0.name == "Work" }), let w = c.window, let content = w.contentView,
                  let f = LayoutChecks.frames["top-chip-\(work.id)"] else { print("IKTEST chip none"); break }
            let p = w.convertPoint(toScreen: content.convert(NSPoint(x: f.midX, y: content.isFlipped ? f.midY : content.bounds.height - f.midY), to: nil))
            NSApp.activate(ignoringOtherApps: true); w.makeKeyAndOrderFront(nil)
            print("IKTEST chip at \(Int(p.x)),\(Int(NSScreen.screens[0].frame.height - p.y)) open=\(work.isOpen)"); fflush(stdout)
            try? await Task.sleep(for: .seconds(Double(arg) ?? 5))
            print("IKTEST chipafter open=\(state.folders.first { $0.id == work.id }?.isOpen ?? false)")
        case "railhover": state.browserPreferences.railHover = RailHoverEffect(rawValue: arg)  // magnify | expand | off
        case "railpointer":  // y in window points from the top, over the rail's middle; "off" lets the real pointer back
            RailHoverChecks.point(arg == "off" ? nil : Double(arg).map { CGFloat($0) }, browser: c)
        case "railpointtile": RailHoverChecks.pointTile(arg, browser: c)  // <index from the top> | folder
        case "raildemo": RailHoverChecks.seed(c, base: arg)  // <fixture base URL>
        case "hitat":  // x,y in window points from the top-left: which view takes the click there
            let parts = arg.split(separator: ",").compactMap { Double($0) }
            if parts.count == 2, let view = c.window?.contentView {
                let hit = view.hitTest(NSPoint(x: parts[0], y: view.bounds.height - parts[1]))
                print("IKTEST hitat \(arg) \(hit.map { String(describing: type(of: $0)) } ?? "nil")")
            }
        case "tabsaddress": state.browserPreferences.tabsAddressStyle = TabsAddressStyle(rawValue: arg)  // centered | wide | title
        case "edgepeek": state.browserPreferences.sidebarEdgePeek = arg == "off" ? false : nil
        case "pingrid": state.browserPreferences.showPinnedGrid = arg != "off"
        case "flashscrollers":  // shows every scroll bar in the window (the sidebar's overlay ones hide at rest), for a windowshot
            func flash(_ view: NSView) {
                if let scroll = view as? NSScrollView { scroll.flashScrollers(); scroll.verticalScroller?.alphaValue = 1 }
                view.subviews.forEach(flash)
            }
            if let root = c.window?.contentView { flash(root) }
            // A web page keeps its scroll bar inside; a small scroll makes WebKit show it.
            if let view = c.activeController?.page?.contentView, let window = c.window,
               let cg = CGEvent(scrollWheelEvent2Source: nil, units: .pixel, wheelCount: 1, wheel1: Int32(arg.isEmpty ? -40 : Int(arg) ?? -40), wheel2: 0, wheel3: 0) {
                let center = view.convert(NSPoint(x: view.bounds.midX, y: view.bounds.midY), to: nil)
                let screen = window.convertPoint(toScreen: center)
                cg.location = CGPoint(x: screen.x, y: (NSScreen.screens.first?.frame.height ?? 0) - screen.y)
                if let event = NSEvent(cgEvent: cg) { (view.hitTest(view.convert(center, from: nil)) ?? view).scrollWheel(with: event) }
            }
        case "exportdemo":  // <zip path>: exports this profile's bookmarks and history like Settings ▸ Export
            let zip = BrowserExport.archive(bookmarks: BrowserExport.bookmarksHTML(state.bookmarks, folders: state.bookmarkFolders),
                                            history: BrowserExport.historyJSON(state.history), passwords: nil)
            try? BrowserExport.save(zip, to: URL(fileURLWithPath: arg))
        case "importfile":  // <path>: imports a file the way Import an Exported File does, then prints the report
            await state.importer.importFile(URL(fileURLWithPath: arg), into: state)
            for item in state.importer.report?.items ?? [] { print("IKTEST importreport \(item.kind): \(item.summary)") }
            print("IKTEST importresult \(state.importer.result ?? "-")")
        case "groupplacement": state.browserPreferences.groupPlacement = GroupPlacement(rawValue: arg)  // both | topBar | sidebar
        case "folder": state.createFolder(named: arg, with: state.activeTabID)
        case "nestfolder":  // <child index>:<parent index> among the Space's groups
            let parts = arg.split(separator: ":").compactMap { Int($0) }, f = state.spaceFolders
            if parts.count == 2, f.indices.contains(parts[0]), f.indices.contains(parts[1]) { state.moveFolder(f[parts[0]].id, into: f[parts[1]].id) }
        case "togglefolder": if let f = state.spaceFolders.first { state.toggleFolder(f.id) }
        case "unfolder": if let id = state.activeTabID { state.moveToFolder(id, folderID: nil) }
        case "tospace": if let i = Int(arg), let id = state.activeTabID, state.spaces.indices.contains(i - 1) {
            state.moveTab(id, toSpace: state.spaces[i - 1].id)
        }
        case "droptab": if let tab = state.sidebarOrder[safe: (Int(arg) ?? 1) - 1] { state.splitWithDropped(tab.id, leading: false) }
        case "extstatus": print("IKTEST extstatus \(arg) \(await ExtensionStoreStatus.shared.status(arg))")
        case "extinstall": c.installFromWebStore(arg)  // needs IKAGO_TEST_AUTO_APPROVE=1
        case "extaction":  // click the extension's toolbar button
            ExtensionManager.shared.contexts[arg]?.performAction(for: c.activeController)
        case "popupjs":  // function body in the open extension popup's page (chrome.* available)
            guard let webView = ExtensionManager.shared.presentedPopover?.contentViewController?.view
                .firstSubview(of: WKWebView.self) else { print("IKTEST popupjs no popup"); break }
            do {
                let result = try await webView.callAsyncJavaScript(arg, arguments: [:], in: nil, contentWorld: .page)
                print("IKTEST popupjs \(result.map { "\($0)" } ?? "nil")")
            } catch { print("IKTEST popupjs error \(error)") }
        case "extlist":
            for record in ExtensionManager.shared.records {
                let context = ExtensionManager.shared.contexts[record.id]
                let ext = context?.webExtension
                let errors = ((ext?.errors ?? []) + (context?.errors ?? [])).map(\.localizedDescription)
                print("IKTEST ext \(record.id) name=\(ext?.displayName ?? "-") v=\(ext?.displayVersion ?? "-") " +
                      "mv=\(ext?.manifestVersion ?? 0) loaded=\(context?.isLoaded ?? false) " +
                      "allHosts=\(context?.hasAccessToAllHosts ?? false) popup=\(context?.action(for: nil)?.presentsPopup ?? false) " +
                      "badge='\(context?.action(for: c.activeController)?.badgeText ?? "")' errors=\(errors)")
            }
            print("IKTEST popover shown=\(ExtensionManager.shared.presentedPopover?.isShown ?? false)")
        case "windowsize":
            let size = arg.split(separator: ",").compactMap { Double($0) }
            if size.count == 2 { c.window?.setContentSize(NSSize(width: size[0], height: size[1])) }
        case "frame":  // window frame in screen coordinates (top-left origin), for synthetic events
            if let w = c.window, let screen = w.screen {
                print("IKTEST frame \(Int(w.frame.minX)) \(Int(screen.frame.maxY - w.frame.maxY)) \(Int(w.frame.width)) \(Int(w.frame.height))")
            }
        case "bookmark": c.bookmarkPage(nil)
        case "pagescroll":
            if let scroll = c.activeController?.hostView.firstSubview(of: NSScrollView.self), let document = scroll.documentView {
                let fraction = min(1, max(0, Double(arg) ?? 0))
                let maximum = max(0, document.bounds.height - scroll.contentView.bounds.height)
                scroll.contentView.scroll(to: NSPoint(x: 0, y: (document.isFlipped ? fraction : 1 - fraction) * maximum))
                scroll.reflectScrolledClipView(scroll.contentView)
            }
        case "pingrid": state.browserPreferences.showPinnedGrid = arg != "off"
        case "importprobe":  // every detected browser profile: what an import reads (counts and notes only, no contents)
            let home = FileManager.default.homeDirectoryForCurrentUser
            for profile in BrowserProfileDiscovery.discover(home: home, installedBrowsers: BrowserProfileDiscovery.installedBrowsers()) {
                let started = Date()
                do {
                    let data = try BrowserProfileImporter.read(profile.directory, kind: profile.kind, decryptWith: nil)
                    let encrypted = data.notes.first { $0.contains("encrypted cookies") } ?? ""
                    print("IKTEST importprobe \(profile.browser) [\(profile.name)] bookmarks=\(data.bookmarks.count) history=\(data.history.count) tabs=\(data.tabs.count) cookies=\(data.cookies.count) access=\(data.accessIssues) \(String(format: "%.1fs", Date().timeIntervalSince(started))) \(encrypted)")
                    for note in data.notes where !note.contains("encrypted cookies") { print("IKTEST importprobe   note: \(note)") }
                } catch { print("IKTEST importprobe \(profile.browser) [\(profile.name)] ERROR \(error.localizedDescription)") }
            }
        case "bookmarksmenu":  // the menu bar's Bookmarks menu as it would open: each item, submenus one level deep
            if let menu = NSApp.mainMenu?.items.first(where: { $0.title == "Bookmarks" })?.submenu {
                BookmarksMenu.shared.menuNeedsUpdate(menu)
                for item in menu.items {
                    print("IKTEST bookmarksmenu \(item.isSeparatorItem ? "—" : item.title)\(item.submenu != nil ? " ▸" : "")")
                    if let sub = item.submenu, sub.delegate === BookmarksMenu.shared {
                        BookmarksMenu.shared.menuWillOpen(sub)
                        for child in sub.items { print("IKTEST bookmarksmenu     \(child.isSeparatorItem ? "—" : child.title)\(child.submenu != nil ? " ▸" : "")") }
                    }
                }
            }
        case "reimportcheck":  // an earlier flat import moves into folders on re-import; importing again adds nothing
            let url = "https://reimport.example/page"
            // Start clean: the test session keeps bookmarks between runs.
            state.bookmarks.removeAll { $0.url.hasPrefix("https://reimport.example") }
            let probeRoots = Set(state.bookmarkFolders.filter { $0.name == "Imported from Probe" }.map(\.id))
            state.bookmarkFolders.removeAll { probeRoots.contains($0.id) || $0.parentID.map(probeRoots.contains) == true
                || ($0.name == "Work" && $0.parentID == nil) }
            let remaining = Set(state.bookmarkFolders.map(\.id))
            state.bookmarkFolders.removeAll { folder in folder.parentID.map { !remaining.contains($0) } ?? false }
            state.bookmarks.append(Bookmark(url: url, title: "Flat"))
            var data = BrowserImportData(bookmarks: [ImportedBookmark(url: url, title: "Flat", folders: ["Bar", "Work"]),
                                                     ImportedBookmark(url: url + "2", title: "New", folders: ["Bar"])])
            data.sourceName = "Probe"
            _ = await state.applyImport(data, selection: ImportSelection(), to: state.activeSpaceID)
            let count1 = state.bookmarks.filter { $0.url.hasPrefix("https://reimport.example") }.count
            let work = state.bookmarkFolders.first { $0.name == "Work" }
            let moved = state.bookmarks.first { $0.url == url }?.folderID == work?.id && work != nil
            _ = await state.applyImport(data, selection: ImportSelection(), to: state.activeSpaceID)
            let count2 = state.bookmarks.filter { $0.url.hasPrefix("https://reimport.example") }.count
            let roots = state.bookmarkFolders.filter { $0.name == "Imported from Probe" }.count
            print("IKTEST reimportcheck \(moved && count1 == 2 && count2 == 2 && roots == 1 ? "PASS" : "FAIL") moved=\(moved) first=\(count1) again=\(count2) roots=\(roots)")
        case "shortcutitems":  // comma-separated SidebarShortcut names; "default" resets
            state.browserPreferences.sidebarShortcutItems = arg == "default" ? nil : arg.split(separator: ",").map(String.init)
        case "gridabove": state.browserPreferences.pinnedGridAboveShortcuts = arg == "off" ? nil : true
        case "pinnedstay": state.browserPreferences.pinnedRowsStayInView = arg == "off" ? nil : true
        case "dump": dump(c)
        // Quit from the run loop like a menu does: inside this task the main queue is busy, so
        // `.terminateLater` work (clearing data, flushing cookies) could never finish.
        case "quit": RunLoop.main.perform(inModes: [.default]) { MainActor.assumeIsolated { NSApp.terminate(nil) } }
        default:
            if await !performCheck(parts[0], arg, c) { print("IKTEST unknown action \(action)") }
        }
    }
}
#endif
