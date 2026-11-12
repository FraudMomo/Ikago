import AppKit
import WebKit

extension FileDropWebView {
    func configurePageMenu(_ menu: NSMenu, event: NSEvent) {
        menuActions.removeAll()
        // Keep WebKit's editing, spelling, dictionary and native video commands.
        // Replace only the system Search Web action, which otherwise launches Safari.
        for item in menu.items {
            let identifier = item.identifier?.rawValue.lowercased() ?? ""
            if identifier.contains("searchweb") || identifier.contains("searchtheweb")
                || item.action.map({ NSStringFromSelector($0).lowercased().contains("searchweb") }) == true {
                let target = PageMenuAction { [weak self] in self?.searchSelection() }
                menuActions.append(target)
                item.target = target
                item.action = #selector(PageMenuAction.invoke(_:))
                item.title = "Search in Ikago"
            }
        }
        addPageItem("Translate Page…", to: menu) { [weak self] in self?.pageAction(.translate) }
        addPageItem("Search Selection in Ikago", to: menu) { [weak self] in self?.searchSelection() }
        let point = convert(event.locationInWindow, from: nil)
        let y = isFlipped ? point.y : bounds.height - point.y
        let script = """
        (() => {
          let e = document.elementFromPoint(\(point.x), \(y));
          const a = e?.closest('a[href]');
          const v = e?.closest('video') || (e?.closest('iframe') ? null : document.querySelector('video'));
          return {link: a?.href || '', video: v?.currentSrc || v?.src || ''};
        })()
        """
        evaluateJavaScript(script, in: nil, in: .defaultClient) { [weak self, weak menu] result in
            guard let self, let menu, case .success(let value) = result, let hit = value as? [String: String] else { return }
            if let link = hit["link"], AddressResolver.isWebURL(link) {
                self.addPageItem("Open Link in Private Window", to: menu) { [weak self] in self?.pageAction(.privateLink(link)) }
            }
            if let video = hit["video"], AddressResolver.isWebURL(video) {
                self.addPageItem("Float Video in Native Player", to: menu) { [weak self] in self?.pageAction(.pictureInPicture(video)) }
            }
        }
    }

    private func searchSelection() {
        evaluateJavaScript("window.getSelection()?.toString().slice(0,4096) || ''", in: nil, in: .defaultClient) { [weak self] result in
            if case .success(let value) = result, let text = value as? String, !text.isEmpty { self?.pageAction(.search(text)) }
        }
    }

    private func addPageItem(_ title: String, to menu: NSMenu, perform: @escaping () -> Void) {
        if menu.items.last?.isSeparatorItem != true { menu.addItem(.separator()) }
        let target = PageMenuAction(perform)
        menuActions.append(target)
        let item = NSMenuItem(title: title, action: #selector(PageMenuAction.invoke(_:)), keyEquivalent: "")
        item.target = target
        menu.addItem(item)
    }
}
