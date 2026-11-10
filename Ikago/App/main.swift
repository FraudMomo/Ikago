import AppKit
import IKCEFBridge

let app = IKCEFApplication.shared

/// A locked or denied Keychain must never look like lost data, or start a new empty session over it.
@MainActor func unlockLocalData() {
    while true {
        do { return try SealedStorage.prepare() } catch {
            let alert = NSAlert()
            alert.messageText = "Ikago can’t unlock your browsing data"
            alert.informativeText = "\(error.localizedDescription) Your history and tabs are safe. Unlock your Keychain and try again."
            alert.addButton(withTitle: "Try Again")
            alert.addButton(withTitle: "Quit")
            if alert.runModal() != .alertFirstButtonReturn { exit(0) }
        }
    }
}

#if IKAGO_CHECKS
if CommandLine.arguments.contains("--cef-smoke") {
    CEFSmoke.runAndExit(app)
}
#endif

/// Data moved into protected storage that this build can't open must never look like a fresh start.
@MainActor func openProtectedStorage() {
    guard !WebProfiles.isTestMode else { return }
    do { try ProtectedStorage.prepare() } catch {
        let alert = NSAlert()
        alert.messageText = "Ikago can’t open your data"
        alert.informativeText = "\(error.localizedDescription) Nothing was changed. Install a signed copy of Ikago to continue."
        alert.addButton(withTitle: "Quit")
        alert.runModal()
        exit(0)
    }
}

openProtectedStorage()
unlockLocalData()
let delegate = AppDelegate()
app.setActivationPolicy(.regular)
app.delegate = delegate

// The default engine and the engines site rules need are fixed for this launch; changes apply after a relaunch.
if case .loaded(let session) = SessionStore.standard.load() {
    let preferences = session.browser ?? BrowserPreferences()
    BrowserRuntime.engine = preferences.preferredEngine
    // WebKit is always available; only Chromium has to start at launch.
    BrowserRuntime.running = SiteEngines.engines(for: preferences).union([.webkit])
}

do {
    if BrowserRuntime.runs(.chromium) {
        try CEFGoogleServices.prepare()
        try CEFSessions.clearScheduledData()
        try IKCEFRuntime.start(withArgc: CommandLine.argc, argv: CommandLine.unsafeArgv, root: CEFSessions.root,
                               helper: BrowserRuntime.helperExecutable, ready: {
            delegate.applicationWillFinishLaunching(Notification(name: NSApplication.willFinishLaunchingNotification))
            delegate.applicationDidFinishLaunching(Notification(name: NSApplication.didFinishLaunchingNotification))
        })
        IKCEFRuntime.runMessageLoop()
        // Everything is saved by now, but CefShutdown can take about 10 seconds, so leave the Dock first.
        app.setActivationPolicy(.prohibited)
        try IKCEFRuntime.shutdown()
    } else {
        app.run()
        app.reply(toApplicationShouldTerminate: true)
    }
} catch {
    let alert = NSAlert()
    alert.messageText = "Ikago could not start"
    alert.informativeText = error.localizedDescription
    alert.runModal()
}
