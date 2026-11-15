import AppKit

/// Install, open and remove web apps (`WebApp`). The list lives in the preferences, shared by every window.
@MainActor
enum WebApps {
    static func all(_ state: BrowserState) -> [WebApp] { state.browserPreferences.webApps ?? [] }

    /// Keeps the page's address and name as a new app and writes its launcher; the Dock is the person's to arrange.
    @discardableResult
    static func install(name: String, url: String, state: BrowserState, icon: NSImage?) throws -> WebApp {
        var apps = all(state)
        let name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        var app = WebApp(name: name.isEmpty ? (URL(string: url)?.host ?? "Web App") : String(name.prefix(60)), url: url, spaceID: state.activeSpaceID)
        // The same site again replaces its app instead of adding a twin.
        if let existing = apps.firstIndex(where: { $0.url == url }) { app.id = apps[existing].id; apps.remove(at: existing) }
        try WebAppLauncher.write(app, icon: icon)
        apps.append(app)
        state.browserPreferences.webApps = apps
        return app
    }

    static func remove(_ app: WebApp, state: BrowserState) {
        WebAppLauncher.remove(app)
        state.browserPreferences.webApps = all(state).filter { $0.id != app.id }
        for controller in BrowserWindows.all where controller.state.webApp?.id == app.id { controller.window?.close() }
    }

    /// The app's window: brought forward when open, else a new one on its Space.
    @discardableResult
    static func open(_ id: String) -> Bool {
        guard let primary = BrowserWindows.primary, let app = all(primary.state).first(where: { $0.id == id }) else { return false }
        if let open = BrowserWindows.all.first(where: { $0.state.webApp?.id == id }) {
            open.window?.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return true
        }
        guard let controller = BrowserWindows.open(webApp: app) else { return false }
        controller.window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        return true
    }
}
