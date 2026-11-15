import AppKit
import SwiftUI

// MARK: - Media
extension BrowserWindowController {
    func togglePageAssistant() {
        guard state.browserPreferences.pageIntelligence == true else { chrome.showPageAssistant = false; return }
        withAnimation(.ikago) { chrome.showPageAssistant.toggle() }
    }
    @objc func askThisPage(_ sender: Any?) { togglePageAssistant() }

    func pictureInPicture(_ id: String) {
        guard let page = content.controller(for: id)?.page else { return }
        Task { @MainActor [weak self] in
            do { try await page.pictureInPicture() }
            catch {
                guard let window = self?.window else { return }
                let alert = NSAlert(error: error)
                alert.messageText = "Picture in Picture Unavailable"
                alert.beginSheetModal(for: window) { _ in }
            }
        }
    }

    func controlMedia(_ id: String, action: MediaPlaybackAction) {
        guard let page = content.controller(for: id)?.page else { return }
        Task { @MainActor in await page.controlMedia(action) }
    }
}

// MARK: - Performance
extension BrowserWindowController {
    @objc func showPerformance(_ sender: Any?) { openPage(.performance) }

    func performanceTabs() -> [TabPerformanceEntry] {
        state.tabs.map { tab in
            let controller = content.controller(for: tab.id)
            let page = controller?.page
            let parked = [controller?.handoff.previous, controller?.handoff.next].compactMap { $0 }.count
            return TabPerformanceEntry(id: tab.id, title: tab.displayTitle,
                engine: page?.engine.rawValue.capitalized ?? tab.engine?.rawValue.capitalized ?? "—",
                status: InternalPage(url: tab.url) != nil ? "Browser page" : page == nil ? "Unloaded"
                    : tab.isLoading ? "Loading" : state.visibleTabIDs.contains(tab.id) ? "Visible" : "Background",
                pid: page?.performanceProcessID, parked: parked)
        }
    }
}

// MARK: - Translation
extension BrowserWindowController {
    /// Translate Page: asks from and to which language (the page's own, and the last one chosen), then translates on
    /// this Mac; again, it puts the original back.
    @objc func translatePage(_ sender: Any?) {
        guard let controller = activeController, let page = controller.page, AddressResolver.isWebURL(page.currentURL) else { return }
        if controller.translation != nil || chrome.translationJob?.controller === controller && chrome.translationJob?.phase == .translating {
            return showOriginal()
        }
        let target = PageTranslation.target(state.browserPreferences)
        let address = page.currentURL
        Task { @MainActor [weak self] in
            guard let self else { return }
            let result = try? await page.evaluate(TranslationScript.collect) as? [String: Any]
            let texts = result?["texts"] as? [String] ?? []
            guard controller.page === page, page.currentURL == address else { return }
            let source = PageTranslation.detect(texts, declared: result?["lang"] as? String ?? "")
            let phase: TranslationJob.Phase = texts.isEmpty ? .failed("There is no text on this page to translate.") : .choosing
            withAnimation(.ikago) {
                self.chrome.translationJob = TranslationJob(source: source, target: target, texts: texts, controller: controller, phase: phase)
            }
        }
    }

    /// Remembers the language chosen in the card for the next page.
    func rememberTranslationTarget(_ language: Locale.Language) {
        state.browserPreferences.translationLanguage = language.minimalIdentifier
    }

    /// Closing the card before translating puts back the page's text references the collector left.
    func closeTranslation() {
        if let job = chrome.translationJob, job.phase == .choosing || job.phase == .translating, let page = job.controller?.page {
            job.phase = .failed("")  // a run still under way stops writing
            Task { @MainActor in _ = try? await page.evaluate(TranslationScript.restore) }
        }
        withAnimation(.ikago) { chrome.translationJob = nil }
    }

    func showOriginal() {
        let page = activeController?.page
        activeController?.translation = nil
        Task { @MainActor in _ = try? await page?.evaluate(TranslationScript.restore) }
        withAnimation(.ikago) { chrome.translationJob = nil }
    }
}

// MARK: - Web apps
extension BrowserWindowController {
    /// A web app keeps its own site; a link to another site opens in the regular window. True when it did.
    func opensOutsideWebApp(_ url: String) -> Bool {
        guard let app = state.webApp, !app.contains(url), let front = BrowserWindows.frontmost else { return false }
        front.state.newTab(url: url)
        front.window?.makeKeyAndOrderFront(nil)
        return true
    }

    /// File ▸ Add to Applications…: keeps the page's site as a web app, with a launcher in ~/Applications.
    @objc func installWebApp(_ sender: Any?) {
        guard state.webApp == nil, !state.isPrivate, let tab = state.activeTab, AddressResolver.isWebURL(tab.url),
              let url = URL(string: tab.url), let host = url.host else { return }
        let title = tab.title.trimmingCharacters(in: .whitespacesAndNewlines)
        let suggested = String((title.isEmpty || title.count > 40 ? host.replacingOccurrences(of: "www.", with: "") : title).prefix(60))
        let faviconURL = tab.faviconURL
        let address = tab.url
        withAnimation(.ikago) {
            chrome.textPrompt = IntegratedTextPrompt(title: "Add to Applications", placeholder: suggested) { [weak self] name in
                guard let self, let name else { return }
                Task { @MainActor in
                    let icon = faviconURL == nil ? nil : await FaviconCache.shared.image(for: faviconURL!, persist: false, dark: false)
                    do {
                        let app = try WebApps.install(name: name, url: address, state: self.state, icon: icon)
                        self.confirmInstalled(app)
                    } catch {
                        let alert = NSAlert()
                        alert.messageText = "The web app couldn’t be added"
                        alert.informativeText = error.localizedDescription
                        if let window = self.window { alert.beginSheetModal(for: window, completionHandler: nil) }
                    }
                }
            }
        }
    }

    private func confirmInstalled(_ app: WebApp) {
        guard let window else { return }
        let alert = NSAlert()
        alert.messageText = "“\(app.name)” was added to Applications"
        alert.informativeText = "Drag it to the Dock to keep it there, or find it in Launchpad. It opens in its own Ikago window."
        alert.addButton(withTitle: "Open")
        alert.addButton(withTitle: "Show in Finder")
        alert.addButton(withTitle: "Done")
        alert.beginSheetModal(for: window) { response in
            if response == .alertFirstButtonReturn { WebApps.open(app.id) }
            else if response == .alertSecondButtonReturn { NSWorkspace.shared.activateFileViewerSelecting([WebAppLauncher.url(for: app)]) }
        }
    }
}
