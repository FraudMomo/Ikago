import AppKit
import WebKit

extension FileDropWebView {
    func configurePageMenu(_ menu: NSMenu, event: NSEvent) {
        menuActions.removeAll()
        // Keep WebKit's editing, spelling, dictionary and native video commands.
        // Replace only the system Search Web action, which otherwise launches Safari.
        let point = convert(event.locationInWindow, from: nil)
        let y = isFlipped ? point.y : bounds.height - point.y
        for item in menu.items {
            let identifier = item.identifier?.rawValue.lowercased() ?? ""
            // WebKit's own Download Image / Linked File / Video items hand their download to a private delegate
            // call and otherwise do nothing; download the same address through the public API instead.
            if let kind = DownloadTarget(identifier: identifier) {
                let target = PageMenuAction { [weak self] in self?.download(kind, atX: point.x, y: y) }
                menuActions.append(target)
                item.target = target
                item.action = #selector(PageMenuAction.invoke(_:))
                continue
            }
            if identifier.contains("searchweb") || identifier.contains("searchtheweb")
                || item.action.map({ let action = NSStringFromSelector($0).lowercased(); return action.contains("searchweb") || action.contains("searchtheweb") }) == true {
                let target = PageMenuAction { [weak self] in self?.searchSelection() }
                menuActions.append(target)
                item.target = target
                item.action = #selector(PageMenuAction.invoke(_:))
                item.title = "Search in Ikago"
            }
        }
        addPageItem("Translate Page", to: menu) { [weak self] in self?.pageAction(.translate) }
        addPageItem("Save Page…", to: menu, separated: false) { [weak self] in self?.pageAction(.savePage) }
        let script = """
        (() => {
          let e = document.elementFromPoint(\(point.x), \(y));
          const a = e?.closest('a[href]');
          const v = e?.closest('video');
          return {link: a?.href || '', video: v?.currentSrc || v?.src || '', selection: window.getSelection()?.toString() || ''};
        })()
        """
        evaluateJavaScript(script, in: nil, in: .defaultClient) { [weak self, weak menu] result in
            guard let self, let menu, case .success(let value) = result, let hit = value as? [String: String] else { return }
            if hit["selection"]?.isEmpty == false, !menu.items.contains(where: { $0.title == "Search in Ikago" }) {
                self.addPageItem("Search Selection in Ikago", to: menu) { [weak self] in self?.searchSelection() }
            }
            if let link = hit["link"], AddressResolver.isWebURL(link) {
                self.addPageItem("Open Link in Private Window", to: menu) { [weak self] in self?.pageAction(.privateLink(link)) }
            }
            if let video = hit["video"], !video.isEmpty, !menu.items.contains(where: { $0.title.localizedCaseInsensitiveContains("Picture in Picture") }) {
                self.addPageItem("Picture in Picture", to: menu) { [weak self] in self?.pageAction(.pictureInPicture(video)) }
            }
        }
    }

    private func download(_ kind: DownloadTarget, atX x: CGFloat, y: CGFloat) {
        let script = """
        (() => {
          const e = document.elementFromPoint(\(x), \(y));
          const pick = {link: () => e?.closest('a[href]')?.href,
                        image: () => { const i = e?.closest('img'); return i?.currentSrc || i?.src; },
                        media: () => { const m = e?.closest('video, audio'); return m?.currentSrc || m?.src; }};
          return pick['\(kind.rawValue)']() || '';
        })()
        """
        evaluateJavaScript(script, in: nil, in: .defaultClient) { [weak self] result in
            guard let self, case .success(let value) = result, let text = value as? String, let url = URL(string: text),
                  ["http", "https", "data", "blob"].contains(url.scheme?.lowercased() ?? "") else { return }
            let isPrivate = WebProfiles.isPrivateStore(self.configuration.websiteDataStore)
            self.startDownload(using: URLRequest(url: url)) { download in
                DownloadCenter.shared.track(download, isPrivate: isPrivate)
            }
        }
    }

    private func searchSelection() {
        evaluateJavaScript("window.getSelection()?.toString().slice(0,4096) || ''", in: nil, in: .defaultClient) { [weak self] result in
            if case .success(let value) = result, let text = value as? String, !text.isEmpty { self?.pageAction(.search(text)) }
        }
    }

    private func addPageItem(_ title: String, to menu: NSMenu, separated: Bool = true, perform: @escaping () -> Void) {
        if separated, menu.items.last?.isSeparatorItem != true { menu.addItem(.separator()) }
        let target = PageMenuAction(perform)
        menuActions.append(target)
        let item = NSMenuItem(title: title, action: #selector(PageMenuAction.invoke(_:)), keyEquivalent: "")
        item.target = target
        menu.addItem(item)
    }
}

/// Which of WebKit's download items was picked, from its menu identifier.
private enum DownloadTarget: String {
    case link, image, media

    init?(identifier: String) {
        if identifier.contains("downloadlinkedfile") { self = .link }
        else if identifier.contains("downloadimage") { self = .image }
        else if identifier.contains("downloadmedia") { self = .media }
        else { return nil }
    }
}
