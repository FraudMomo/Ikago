import AppKit

/// Offers to save or update a login after the person signs in, on either engine. The key script notices a sign-in
/// (a submitted form, Return or a button with a filled password) and confirms it once the password field goes away or
/// the page moves on, so a rejected password is never offered. Nothing is saved without the person's choice, private
/// windows never offer, and an identical saved login is recognized by its fingerprint without Touch ID.
@MainActor
enum PasswordSaving {
    private static var preferences: BrowserPreferences { BrowserSecurity.shared.preferences }

    /// Settings ▸ Passwords ▸ Offer to save passwords (unset: on), only while Ikago's vault fills passwords.
    static var isEnabled: Bool {
        (preferences.passwordAutoFill ?? true) && (preferences.passwordOfferSave ?? true)
    }

    /// Whether a page's sign-ins may be watched: HTTPS (or local development), not a site the person said never to.
    static func watches(_ url: URL?, onChromium: Bool) -> Bool {
        guard isEnabled, onChromium || PasswordSource.current == .ikago, let url, let host = url.host else { return false }
        let secure = BrowserPreferences.isSecurePage(url)
        return secure && !(preferences.passwordNeverSave ?? []).contains(PublicSuffix.registrableDomain(PasswordVault.site(host)))
    }

    /// A confirmed sign-in from a frame whose host is `host`, shown in `view`'s window. Private windows never offer
    /// (asked of the window, since checks also keep website data in memory).
    static func submitted(username: String, password: String, host: String, pageURL: URL?, isPrivate: Bool, in view: NSView) {
        guard !isPrivate, watches(pageURL, onChromium: true), !password.isEmpty, password.count <= 1024, username.count <= 512,
              let window = view.window, let controller = window.windowController as? BrowserWindowController,
              !controller.state.isPrivate else { return }
        let username = username.trimmingCharacters(in: .whitespacesAndNewlines)
        let site = PasswordVault.site(host)
        guard !site.isEmpty else { return }
        let strong = PasswordChooser.isStrong(password, site: site)
        switch PasswordVault.shared.submission(host: site, username: username, password: password) {
        case .same: return
        case .new: PasswordSavePresenter.shared.offer(site: site, username: username, password: password, update: false, strong: strong, in: controller)
        case .changed(let login):
            PasswordSavePresenter.shared.offer(site: login.site, username: username, password: password, update: true, strong: strong, in: controller)
        }
    }

    static func never(_ site: String) {
        guard let state = BrowserWindows.frontmost?.state else { return }
        let domain = PublicSuffix.registrableDomain(site)
        var list = state.browserPreferences.passwordNeverSave ?? []
        if !list.contains(domain) { list.append(domain) }
        state.browserPreferences.passwordNeverSave = list
    }
}

/// What the save card shows; the password itself stays with the presenter, outside observed state.
struct PasswordSaveOffer: Equatable {
    let id = UUID()
    let site: String
    var username: String
    let update: Bool
    /// A strong password Ikago suggested: the card stays until answered, so it isn't lost.
    var strong = false
}

@MainActor
final class PasswordSavePresenter {
    static let shared = PasswordSavePresenter()
    private var password: String?
    private weak var chrome: ChromeModel?
    private var expiry: Task<Void, Never>?

    func offer(site: String, username: String, password: String, update: Bool, strong: Bool = false, in controller: BrowserWindowController) {
        dismiss()
        self.password = password
        chrome = controller.chrome
        controller.chrome.passwordSave = PasswordSaveOffer(site: site, username: username, update: update, strong: strong)
        // Like a notification: it goes away on its own if left alone, unless it holds a new strong password.
        if strong { return }
        expiry = Task { [weak self] in
            try? await Task.sleep(for: .seconds(45))
            if !Task.isCancelled { self?.dismiss() }
        }
    }

    func setUsername(_ name: String) { chrome?.passwordSave?.username = name }

    /// Saves (or updates) the offered login, then closes the card. Returns an error to show, if any.
    func save() -> String? {
        guard let offer = chrome?.passwordSave, let password else { return nil }
        do {
            let username = offer.username.trimmingCharacters(in: .whitespacesAndNewlines)
            try PasswordVault.shared.add([.init(url: "https://" + offer.site, title: nil, username: username,
                                               password: password, savedHere: true)])
            if offer.strong { PasswordChooser.forgetStrong(site: offer.site) }
            dismiss()
            return nil
        } catch {
            return (error as? LocalizedError)?.errorDescription ?? "The password couldn’t be saved."
        }
    }

    func never() {
        if let site = chrome?.passwordSave?.site { PasswordSaving.never(site) }
        dismiss()
    }

    func dismiss() {
        expiry?.cancel()
        expiry = nil
        password = nil
        chrome?.passwordSave = nil
    }
}
