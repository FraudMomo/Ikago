import AppKit
import IKCEFBridge

@MainActor
final class AppDelegate: NSObject, IKCEFApplicationDelegate {
    private var hasStarted = false
    private var quitRequested = false
    private var state: BrowserState!
    private var windowController: BrowserWindowController?
    private var pendingURLs: [String] = []
    /// Pages continued from another device before the session loaded; kept only if Handoff is on.
    private var pendingHandoff: [String] = []
    private var pendingWebApps: [String] = []
    private var keyMonitor: Any?
    private var mouseButtonMonitor: Any?
    private var privateWindows: [BrowserWindowController] = []
    private var suspendedQuitEvent: NSAppleEventManager.SuspensionID?

    func applicationWillFinishLaunching(_ notification: Notification) {
        NSApp.mainMenu = MainMenu.build()
        _ = KeyBindings.commands  // remember the built-in shortcuts before the person's are applied
        // http(s) links opened from other apps (Ikago registers as a browser).
        NSAppleEventManager.shared().setEventHandler(
            self, andSelector: #selector(handleGetURL(_:reply:)),
            forEventClass: AEEventClass(kInternetEventClass), andEventID: AEEventID(kAEGetURL))
        // Quit events (Dock, logout, scripts) on Chromium: answer them ourselves once the quit is under
        // way. Through AppKit they could only be cancelled, which made a logout fail the first time.
        if BrowserRuntime.runs(.chromium) {
            NSAppleEventManager.shared().setEventHandler(
                self, andSelector: #selector(handleQuitEvent(_:reply:)),
                forEventClass: AEEventClass(kCoreEventClass), andEventID: AEEventID(kAEQuitApplication))
        }
    }

    @objc private func handleQuitEvent(_ event: NSAppleEventDescriptor, reply: NSAppleEventDescriptor) {
        guard !quitRequested else { return }  // An earlier quit is already finishing; a plain reply is right.
        suspendedQuitEvent = NSAppleEventManager.shared().suspendCurrentAppleEvent()
        cefApplicationRequestsQuit()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        guard !hasStarted else { return }
        hasStarted = true
        DefaultBrowserSetting.registerInstalledCopy()
        WebNotifications.shared.activate()
        FaviconCache.shared.removeMisattributedIconsOnce()
        PasswordExportReminder.shared.start()
        FaviconCache.shared.encryptExistingFiles()
        ThreatHosts.shared.start()  // both engines; WebKit also has Apple’s own fraud warnings
        // Extensions load first so their content scripts reach the first page load.
        Task { @MainActor in
            state = BrowserState()
            let profiles = Set(state.spaces.map(\.profileID))
            if BrowserRuntime.runs(.chromium) {
                while !IKCEFRuntime.ready { try? await Task.sleep(for: .milliseconds(10)) }
                ChromiumWindowGuard.install()
                // Pages Chromium opens by itself, such as an extension's tabs.create, become Ikago tabs.
                IKCEFNativeTools.setForeignPageHandler { url in self.openExternalURLs([url.absoluteString]) }  // the delegate lives as long as the app
                MediaTranslation.apply(state.browserPreferences.chromiumVideoTranslation ?? true)
            }
            // The whole-store copy follows the default engine; sites with rules move on their own.
            if BrowserRuntime.engine == .chromium { await EngineCookieSync.prepareChromium(profiles: profiles, preferences: state.browserPreferences) }
            else { EngineCookieSync.noteWebKitLaunch() }
            await EngineCookieSync.moveSiteLogins(profiles: profiles)
            if BrowserRuntime.runs(.webkit) { await BrowserSecurity.shared.prepare() }
            if BrowserRuntime.runs(.webkit) { await ExtensionManager.shared.loadInstalled() }
            openBrowserWindow()
        }
    }

    private func openBrowserWindow() {
        if state.browserPreferences.handoff == true { pendingURLs += pendingHandoff }
        pendingHandoff = []
        if state.tabs.isEmpty, pendingURLs.isEmpty {
            state.newTab(url: state.pendingWelcome ? InternalPage.welcome.url : state.startPageURL)
        }
        installInputMonitors()
        let controller = BrowserWindowController(state: state)
        windowController = controller
        BrowserWindows.primary = controller
        controller.showWindow(nil)
        HandoffAdvertiser.shared.start()
        // The session's other windows, each with its own tabs.
        BrowserWindows.restore(state.pendingWindows)
        state.pendingWindows = []
        controller.window?.makeKeyAndOrderFront(nil)
        // A downloaded copy updates through Sparkle; a build made on this Mac rebuilds Chromium itself.
        // Ikago Test is rebuilt by hand and never updates.
        if AppUpdates.isAvailable { AppUpdates.shared.start() } else if !AppIdentity.isTestBuild { ChromiumUpdates.shared.start(window: controller.window) }
        if BrowserRuntime.runs(.webkit) {
            ExtensionManager.shared.startUpdates()
            ExtensionSync.seedDefaults()
            Task { await ExtensionManager.shared.syncWithOtherEngine() }
        }
        if BrowserRuntime.runs(.chromium), !WebProfiles.isTestMode {
            let profile = state.activeSpace.profileID
            ExtensionSync.seedDefaults()
            Task { try? await Task.sleep(for: .seconds(3)); await ChromiumExtensions.shared.sync(profile: profile) }
        }
        pendingURLs.forEach { state.newTab(url: $0) }
        pendingURLs.removeAll()
        pendingWebApps.forEach { WebApps.open($0) }
        pendingWebApps.removeAll()
        #if DEBUG
        TestDriver.runIfRequested(controller: controller)
        #endif

        if let warning = state.restoreWarning {
            let alert = NSAlert()
            alert.messageText = "Session not restored"
            alert.informativeText = warning
            alert.beginSheetModal(for: controller.window!)
        }
    }

    private func installInputMonitors() {
        // App shortcuts (Cmd+T, Cmd+L, …) win over the page; editing keys stay with it.
        // Both monitors serve whichever browser window (main or private) got the event.
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            // Settings is recording a shortcut: the press is the shortcut, not a command.
            if let recorder = KeyBindings.recorder, event.window != nil, event.window === KeyBindings.recordingWindow {
                recorder(event); return nil
            }
            guard let controller = event.window?.windowController as? BrowserWindowController else { return event }
            if event.keyCode == 53, controller.chrome.showDownloads {
                controller.chrome.showDownloads = false
                return nil
            }
            // Esc closes the find bar (and clears its highlights) wherever focus is: in its field, on the page after
            // Return/clicking a match, or on a toolbar button. A field editor can swallow Esc before SwiftUI sees it.
            if event.keyCode == 53, controller.chrome.showFind, !controller.chrome.showPalette {
                controller.closeFindBar()
                return nil
            }
            return ShortcutRouter.intercept(event) ? nil : event
        }
        // Mouse back/forward buttons (the extra buttons are 3 and 4).
        mouseButtonMonitor = NSEvent.addLocalMonitorForEvents(matching: .otherMouseUp) { event in
            guard let controller = event.window?.windowController as? BrowserWindowController else { return event }
            switch event.buttonNumber {
            case 3: controller.goBack()
            case 4: controller.goForward()
            default: return event
            }
            return nil
        }
    }

    /// A private window: no history, no saved session, in-memory website data, no extensions.
    /// Without a `url` it opens like ⌘N: whatever new tabs open (the command bar, the homepage or a new-tab page).
    func openPrivateWindow(url: String? = nil) {
        guard let state else { return }
        let privateState = BrowserState(privateFrom: state)
        if let url { privateState.newTab(url: url) }
        let controller = BrowserWindowController(state: privateState)
        privateWindows.append(controller)
        if let frame = windowController?.window?.frame { controller.window?.setFrame(frame.offsetBy(dx: 28, dy: -28), display: false) }
        controller.showWindow(nil)
        if url == nil { controller.newTab() }
    }

    func privateWindowClosed(_ controller: BrowserWindowController) {
        privateWindows.removeAll { $0 === controller }
    }

    @objc private func handleGetURL(_ event: NSAppleEventDescriptor, reply: NSAppleEventDescriptor) {
        guard let url = event.paramDescriptor(forKeyword: keyDirectObject)?.stringValue,
              AddressResolver.isWebURL(url) else { return }
        openExternalURLs([url])
    }

    // Finder sends document-open events, not kAEGetURL. Queue both kinds until startup
    // has finished preparing WebKit and extensions, including a cold launch from a file.
    func application(_ application: NSApplication, open urls: [URL]) {
        // A web app's launcher (`WebAppLauncher`): ikago-app://<id>.
        let apps = urls.filter { $0.scheme == WebApp.scheme }.compactMap(\.host)
        if !apps.isEmpty {
            if state != nil, windowController != nil { apps.forEach { WebApps.open($0) } } else { pendingWebApps += apps }
        }
        openExternalURLs(urls.map(\.absoluteString).filter { AddressResolver.isPageURL($0) })
    }

    func application(_ application: NSApplication, willContinueUserActivityWithType userActivityType: String) -> Bool {
        // Before the session loads its settings, accept and decide once they're known.
        userActivityType == NSUserActivityTypeBrowsingWeb && (state == nil || state.browserPreferences.handoff == true)
    }

    /// A page continued from another device (Handoff), when turned on in Settings.
    func application(_ application: NSApplication, continue userActivity: NSUserActivity,
                     restorationHandler: @escaping ([any NSUserActivityRestoring]) -> Void) -> Bool {
        NSLog("Ikago Handoff: continuing %@ (session loaded: %d)", userActivity.activityType, state != nil ? 1 : 0)
        guard let url = HandoffAdvertiser.webURL(of: userActivity) else {
            NSLog("Ikago Handoff: no web page in activity %@", userActivity.activityType)
            return false
        }
        guard state != nil, windowController != nil else {
            pendingHandoff.append(url)
            return true
        }
        guard state.browserPreferences.handoff == true else { return false }
        openExternalURLs([url])
        return true
    }

    private func openExternalURLs(_ urls: [String]) {
        guard !urls.isEmpty else { return }
        if state != nil, windowController != nil, let front = BrowserWindows.frontmost {
            urls.forEach { front.state.newTab(url: $0) }
            front.window?.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
        } else {
            pendingURLs.append(contentsOf: urls)
        }
    }

    func cefApplicationRequestsQuit() {
        guard !quitRequested else { return }
        NotesPage.flush()
        quitRequested = true
        beginQuit(NSApp)
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        // handleQuitEvent normally catches Apple Event quits first. Anything still landing here
        // can't use .terminateLater, whose nested loop CEF's message loop cannot exit, so
        // cancel AppKit's quit and finish through the CEF path.
        if BrowserRuntime.runs(.chromium) {
            cefApplicationRequestsQuit()
            return .terminateCancel
        }
        beginQuit(sender)
        return .terminateLater
    }

    private func beginQuit(_ sender: NSApplication) {
        DownloadCenter.shared.saveNow()
        let quit = {
            EngineCookieSync.exportIfSwitching(state: self.state) {
                WebProfiles.flushCookies {
                    CEFSessions.flush {
                        for controller in [self.windowController].compactMap({ $0 }) + BrowserWindows.others + self.privateWindows { controller.content.shutdown() }
                        ChromiumExtensions.shared.shutDown()
                        IKCEFNativeTools.closeAll()
                        if !WebProfiles.isTestMode && ProtectedStorage.isOnlyInstance { ProtectedStorage.removeTemporaryFiles() }
                        self.finishCEFQuit(sender)
                    }
                }
            }
        }
        guard let state, state.clearsDataOnQuit else {
            state?.freezeForShutdown()
            quit()
            return
        }
        // Settings ▸ Privacy: wipe history and website data first, then quit.
        Task { @MainActor in
            await state.clearBrowsingData()
            state.freezeForShutdown()
            quit()
        }
    }

    private func finishCEFQuit(_ sender: NSApplication) {
        if !BrowserRuntime.runs(.chromium) { sender.reply(toApplicationShouldTerminate: true); return }
        if IKCEFRuntime.canShutdown {
            if let suspendedQuitEvent { NSAppleEventManager.shared().resume(withSuspensionID: suspendedQuitEvent) }
            suspendedQuitEvent = nil
            BrowserRuntime.stopRunLoop()
        } else { DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { self.finishCEFQuit(sender) } }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }

    func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool { true }
}
