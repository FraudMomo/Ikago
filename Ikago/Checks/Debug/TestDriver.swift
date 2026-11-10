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
            print("IKTEST sidebar visible=\(state.sidebarVisible) compact=\(String(describing: state.browserPreferences.sidebarCompact)) rail=\(state.showsSidebarRail) layout=\(state.tabLayout) immersive=\(state.isImmersive) peeking=\(c.chrome.peeking) lights=\(c.fullScreenControls.isShown) \(c.fullScreenControls.debugFrame)")
            if let w = c.window, let content = w.contentView {
                print("IKTEST frames window=\(w.frame) content=\(content.frame) shell=\(content.subviews.first?.frame ?? .zero) safe=\(content.safeAreaInsets)")
                if let page = c.activeController?.page?.contentView {
                    var v: NSView? = page
                    while let x = v, x !== content { print("IKTEST   \(type(of: x)) frame=\(x.frame) safe=\(x.safeAreaInsets)"); v = x.superview }
                    if let web = page as? WKWebView { print("IKTEST   obscured=\(web.obscuredContentInsets)") }
                }
            }
        case "layout": if let l = TabLayout(rawValue: arg) { withAnimation(.ikago) { state.tabLayout = l } }
        case "mode": if let m = ColorMode(rawValue: arg) { state.colorMode = m }
        case "preset": if let p = SpaceColors.presets.first(where: { $0.name.lowercased() == arg }) { state.setColors(p.colors, for: state.activeSpaceID) }
        case "peek": c.chrome.peek()
        case "relaunch": AppRelaunch.relaunch(URL(fileURLWithPath: arg))  // Opens this app instead of Ikago.
        case "engine":  // Chooses an engine in Settings without relaunching.
            if let engine = BrowserEngine(rawValue: arg) { state.browserPreferences.preferredEngine = engine; state.saveNow() }
        case "page": if let p = InternalPage(rawValue: arg) { c.openPage(p) }
        case "mute": c.toggleMuteTab(nil)
        case "zoomin": c.zoomInPage(nil)
        case "palette": c.showCommandPalette(newTab: arg == "new")
        case "palettequery": c.palette.userEdited(arg)
        case "palettecommit": c.palette.commit()
        case "palettedown": c.palette.moveSelection(1); c.palette.query = c.palette.query  // same text written back
        case "suggestions": print("IKTEST suggestions \(c.palette.selection) " + c.palette.suggestions.map(\.title).joined(separator: " | "))
        case "suggestionkinds": print("IKTEST suggestionkinds " + c.palette.suggestions.map { "\($0.source)" }.joined(separator: ","))
        case "find": c.showFindBar(); c.find.text = arg
        case "findclose": c.closeFindBar()
        case "js":  // function body in the isolated world (may await, must return); prints the result
            do {
                let result = try await c.activeController?.page?.callAsync(arg)
                print("IKTEST js \(result.map { "\($0)" } ?? "nil")")
            } catch { print("IKTEST js error \(error.localizedDescription)") }
        case "permission":  // answer the visible permission sheet: allow | deny
            c.finishPermission(arg == "allow" ? .allow : .deny)
        case "snapshot": snapshot(c.window, to: arg)
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
        case "settingscategory": if let category = SettingsCategory(rawValue: arg) { state.settingsCategory = category }
        case "downloads": c.toggleDownloads()
        case "overview": c.toggleSidebar()
        case "sidebartranslucency": state.browserPreferences.translucentSidebar = arg == "on"
        case "glass": state.useGlass = arg != "off"
        case "inset": state.frameInset = Double(arg) ?? 8
        case "chrome":  // place:<item>:<zone>[:<before>] | remove:<item>:top|side | reset
            let p = arg.split(separator: ":").map(String.init)
            if p.first == "reset" { state.chromeLayout = ChromeLayout() }
            if p.first == "place", p.count >= 3, let item = ChromeItem(rawValue: p[1]), let zone = ChromeZone(rawValue: p[2]) {
                state.chromeLayout.place(item, in: zone, before: p.count > 3 ? ChromeItem(rawValue: p[3]) : nil)
            }
            if p.first == "remove", p.count == 3, let item = ChromeItem(rawValue: p[1]) { state.chromeLayout.remove(item, fromTopBar: p[2] == "top") }
            print("IKTEST chrome \(state.chromeLayout.topBarLeading.map(\.rawValue)) \(state.chromeLayout.topBarTrailing.map(\.rawValue)) | \(state.chromeLayout.sidebarTop.map(\.rawValue)) \(state.chromeLayout.sidebarBottom.map(\.rawValue))")
        case "newtabfocus": state.focusAddressBarOnNewTab = arg == "on"
        case "newtab": c.newTab()
        case "newtabmode": if let m = NewTabMode(rawValue: arg) { state.newTabMode = m }
        case "homepage": state.homepage = arg
        case "separate": if let id = state.activeTabID { state.separate(id) }
        case "unsplitall": state.splits = []
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
        case "essentials": state.showsTopBarEssentials = arg != "off"
        case "topbarstyle": if let style = TopTabStyle(rawValue: arg) { state.topTabStyle = style }
        case "bargap": state.barGap = Double(arg) ?? 6
        case "barrounded": state.barRounded = arg != "off"
        case "barheight": state.barHeight = Double(arg) ?? 28
        case "toptoolbarheight": state.browserPreferences.topToolbarHeight = Double(arg)
        case "toptabbarheight": state.browserPreferences.topTabBarHeight = Double(arg)
        case "barborder": state.barBorder = Double(arg) ?? 0
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
        case "folder": state.createFolder(named: arg, with: state.activeTabID)
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
