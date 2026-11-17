import SwiftUI

/// Extensions that ask before reading a website, on the first visit there: which ones, and Allow / Allow for One Day /
/// Don't Allow. Nothing runs on the site until the person chooses; leaving the card asks again next visit.
struct ExtensionAccessOffer: Equatable, Identifiable {
    let id = UUID()
    let site: String
    let extensions: [ExtensionDescriptor]
    /// The tab that asked. In split view the card sits over its pane, not the focused one.
    var tabID: String? = nil
    /// Space from the window's top and trailing edges to that pane (zero when it fills the content area).
    var paneInset = EdgeInsets()
}

@MainActor
final class ExtensionAccessPresenter {
    static let shared = ExtensionAccessPresenter()
    /// "Not Now" for this launch: extension key + site.
    private var deferred = Set<String>()

    /// After a page commits: offer the extensions that ask and haven't been answered for this website.
    func pageCommitted(_ url: String, engine: BrowserEngine, in controller: TabController) {
        guard !controller.isPrivate, let window = controller.host as? BrowserWindowController,
              let address = URL(string: url), let site = ExtensionAccess.site(address) else { return }
        if window.chrome.extensionAccessOffer?.site != site { window.chrome.extensionAccessOffer = nil }
        Task { @MainActor [weak self, weak window, weak controller] in
            let descriptors = await Self.descriptors(engine, profile: controller?.profileID ?? "Default")
            guard let self, let window, let controller, controller.page?.currentURL == url else { return }
            let asking = descriptors.filter { ext in
                ExtensionAccess.shared.status(ext.key, site: site) == .ask && ext.wants(address) && !self.deferred.contains(ext.key + "|" + site)
            }
            guard !asking.isEmpty, Self.isOnScreen(controller, in: window) else { return }
            withAnimation(.ikago) { window.chrome.extensionAccessOffer = Self.offer(site: site, extensions: asking, for: controller) }
        }
    }

    /// The tab is the selected one, or a pane in the split it belongs to.
    static func isOnScreen(_ controller: TabController, in window: BrowserWindowController) -> Bool {
        guard let active = window.state.activeTabID else { return false }
        return active == controller.tab.id || window.state.splitGroup(of: active)?.contains(controller.tab.id) == true
    }

    static func offer(site: String, extensions: [ExtensionDescriptor], for controller: TabController) -> ExtensionAccessOffer {
        ExtensionAccessOffer(site: site, extensions: extensions, tabID: controller.tab.id, paneInset: paneInset(controller))
    }

    /// How far the tab's pane sits from the window's top-trailing corner, in SwiftUI's top-left coordinates.
    private static func paneInset(_ controller: TabController) -> EdgeInsets {
        let view = controller.hostView
        guard let window = view.window, let content = window.contentView else { return EdgeInsets() }
        let frame = content.convert(view.convert(view.bounds, to: nil), from: nil)
        let top = content.isFlipped ? frame.minY : content.bounds.height - frame.maxY
        let trailing = content.bounds.width - frame.maxX
        // Only a pane that doesn't reach the window's top-right needs moving; the card already clears the toolbar there.
        let split = trailing > 40 || top > 120
        return split ? EdgeInsets(top: max(0, top - 44), leading: 0, bottom: 0, trailing: max(0, trailing)) : EdgeInsets()
    }

    // MARK: Requests from a running extension (WebKit asks before it reads a website)

    /// Pending answers for a running extension's request, by extension key + site.
    private var pending: [String: [(Bool) -> Void]] = [:]

    /// A running WebKit extension asks to read `site` in `controller`'s tab: answered at once when the person already
    /// decided for that website, otherwise with Ikago's card over that tab's pane (never a system alert).
    func request(_ ext: ExtensionDescriptor, site: String, in controller: TabController) async -> Bool {
        switch ExtensionAccess.shared.status(ext.key, site: site) {
        case .everySite, .always, .oneDay: return true
        case .never: return false
        case .ask: break
        }
        guard let window = controller.host as? BrowserWindowController, Self.isOnScreen(controller, in: window) else { return false }
        return await withCheckedContinuation { continuation in
            pending[ext.key + "|" + site, default: []].append { continuation.resume(returning: $0) }
            var extensions = window.chrome.extensionAccessOffer.flatMap { $0.site == site ? $0.extensions : nil } ?? []
            if !extensions.contains(where: { $0.id == ext.id }) { extensions.append(ext) }
            withAnimation(.ikago) { window.chrome.extensionAccessOffer = Self.offer(site: site, extensions: extensions, for: controller) }
        }
    }

    /// The card went away (a choice, Not Now, another tab): answer what was waiting on it with what was chosen.
    func offerClosed(_ offer: ExtensionAccessOffer) {
        for ext in offer.extensions {
            let key = ext.key + "|" + offer.site
            guard let waiting = pending.removeValue(forKey: key) else { continue }
            let allowed: Bool
            switch ExtensionAccess.shared.status(ext.key, site: offer.site) {
            case .everySite, .always, .oneDay: allowed = true
            case .never, .ask: allowed = false
            }
            waiting.forEach { $0(allowed) }
        }
    }

    private static func descriptors(_ engine: BrowserEngine, profile: String) async -> [ExtensionDescriptor] {
        guard engine == .chromium else { return ExtensionManager.shared.accessDescriptors }
        let chromium = ChromiumExtensions.shared
        if chromium.profile != profile { await chromium.refresh(profile: profile) }
        return chromium.accessDescriptors
    }

    func notNow(_ offer: ExtensionAccessOffer, in chrome: ChromeModel) {
        for ext in offer.extensions where ExtensionAccess.shared.status(ext.key, site: offer.site) == .ask {
            deferred.insert(ext.key + "|" + offer.site)
        }
        withAnimation(.ikago) { chrome.extensionAccessOffer = nil }
    }
}

struct ExtensionAccessCard: View {
    let offer: ExtensionAccessOffer
    let colors: Palette
    /// The page reloads once something was allowed, so the extension's scripts reach it.
    let reload: () -> Void
    let close: () -> Void
    @State private var allowedAny = false
    private var access: ExtensionAccess { .shared }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 10) {
                if let only { ExtensionIcon(image: only.icon, size: 28).frame(width: 32, height: 32) }
                else {
                    Image(systemName: "puzzlepiece.extension.fill").font(.system(size: 14, weight: .semibold)).foregroundStyle(.white)
                        .frame(width: 32, height: 32).background(Circle().fill(colors.accent.gradient))
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.system(size: 13, weight: .semibold)).fixedSize(horizontal: false, vertical: true)
                    Text(subtitle).font(.system(size: 11)).foregroundStyle(colors.secondary).fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 4)
                ChromeButton(symbol: "xmark", help: "Not Now", colors: colors, size: 22, glass: false, action: finish)
            }
            if let only {
                HStack(spacing: 8) {
                    Spacer(minLength: 0)
                    Button("Don’t Allow") { choose(.never, only) }.buttonStyle(SettingsButtonStyle()).fixedSize()
                    Button("Allow for One Day") { choose(.oneDay, only) }.buttonStyle(SettingsButtonStyle()).fixedSize()
                    Button("Always Allow") { choose(.always, only) }.buttonStyle(SettingsButtonStyle(prominent: true)).fixedSize()
                }
                .controlSize(.small)
                // A real button like the others (it read as a caption before), on its own row under them.
                HStack {
                    Spacer(minLength: 0)
                    Button { choose(.everySite, only) } label: {
                        Label("Allow on Every Website", systemImage: "globe")
                    }
                    .buttonStyle(SettingsButtonStyle()).fixedSize()
                }
                .controlSize(.small)
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(offer.extensions.enumerated()), id: \.element.id) { index, ext in
                        if index > 0 { Rectangle().fill(colors.separator).frame(height: 0.5).padding(.leading, 38) }
                        HStack(spacing: 10) {
                            ExtensionIcon(image: ext.icon, size: 18).frame(width: 22)
                            Text(ext.name).font(.system(size: 12.5)).lineLimit(1)
                            Spacer(minLength: 6)
                            CompactMenu(value: ExtensionAccessMenu.label(access.status(ext.key, site: offer.site)),
                                        choices: ExtensionAccessMenu.choices(ext, site: offer.site) { allowedAny = allowedAny || $0 != .never })
                        }
                        .padding(.horizontal, 10).frame(height: 38)
                    }
                }
                .background(RoundedRectangle(cornerRadius: Radius.control, style: .continuous).fill(colors.hover))
                HStack {
                    Spacer()
                    Button("Done", action: finish).buttonStyle(SettingsButtonStyle(prominent: true)).controlSize(.small)
                }
            }
        }
        .padding(14)
        .frame(width: 420)
        .foregroundStyle(colors.text)
        .modalSurface(colors, radius: Radius.card)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(title)
        .onDisappear { ExtensionAccessPresenter.shared.offerClosed(offer) }
    }

    private var only: ExtensionDescriptor? { offer.extensions.count == 1 ? offer.extensions[0] : nil }

    private var title: String {
        only.map { "Allow “\($0.name)” on \(offer.site)?" } ?? "\(offer.extensions.count) extensions want to read \(offer.site)"
    }

    private var subtitle: String {
        guard only != nil else { return "Choose for each one. Until you do, they don’t run on this website." }
        return "It wants to read and change this website. It won’t run here until you allow it."
    }

    private func choose(_ choice: ExtensionAccess.Choice, _ ext: ExtensionDescriptor) {
        access.choose(choice, key: ext.key, site: offer.site)
        if choice != .never { allowedAny = true }
        finish()
    }

    private func finish() {
        if allowedAny { reload() }
        close()  // undecided ones are asked again next visit (the presenter's Not Now)
    }
}
