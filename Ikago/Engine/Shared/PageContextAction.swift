import AppKit

/// Browser-owned actions invoked by a real native context-menu click.
enum PageContextAction {
    case privateLink(String), search(String), translate, pictureInPicture(String)
}

extension TabController {
    func webTab(_ page: WebTab, perform action: PageContextAction) {
        guard page === self.page else { return }
        switch action {
        case .privateLink(let address):
            guard let url = URL(string: address), ["http", "https"].contains(url.scheme?.lowercased() ?? "") else { return }
            (NSApp.delegate as? AppDelegate)?.openPrivateWindow(url: url.absoluteString)
        case .search(let text):
            guard let state = browserState, !text.isEmpty else { return }
            (host as? BrowserCommands)?.openInNewTab(state.searchEngine.searchURL( String(text.prefix(4096))))
        case .translate:
            guard let url = URL(string: page.currentURL), ["http", "https"].contains(url.scheme ?? "") else { return }
            var components = URLComponents(string: "https://translate.google.com/translate")!
            components.queryItems = [.init(name: "sl", value: "auto"), .init(name: "tl", value: Locale.current.language.languageCode?.identifier ?? "en"), .init(name: "u", value: url.absoluteString)]
            if let address = components.url?.absoluteString { (host as? BrowserCommands)?.openInNewTab(address) }
        case .pictureInPicture(let address):
            NativePictureInPicture.shared.open(address, owner: page, window: hostView.window)
        }
    }
}

/// Native menu targets are retained by their page until the next menu.
@MainActor
final class PageMenuAction: NSObject {
    let perform: () -> Void
    init(_ perform: @escaping () -> Void) { self.perform = perform }
    @objc func invoke(_ sender: Any?) { perform() }
}
