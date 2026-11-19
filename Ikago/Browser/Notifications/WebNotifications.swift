import AppKit
import UserNotifications
import WebKit

/// Website notifications. A page's `Notification` (`NotificationShim`) asks; the site's saved choice decides (Ask,
/// Allow or Block, in the site card and Settings). Allowed ones are delivered by macOS under the site's name, and
/// clicking one brings its tab forward. Private windows never get any; Settings ▸ Notifications turns all of it off.
@MainActor
final class WebNotifications: NSObject, UNUserNotificationCenterDelegate {
    static let shared = WebNotifications()
    private let center = UNUserNotificationCenter.current()
    private var authorization: Bool?
    #if DEBUG
    /// Checks: titles that would have been delivered (test mode never posts to macOS).
    private(set) var testDelivered: [String] = []
    #endif

    func activate() { center.delegate = self }

    static func value(_ permission: SitePermission) -> String {
        switch permission { case .allow: "granted"; case .block: "denied"; case .ask: "default" }
    }

    /// A message from a page's shim, as the JSON it sent.
    func receive(_ json: String, from controller: TabController) {
        guard json.utf8.count <= 16_384, let data = json.data(using: .utf8),
              let message = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any], let type = message["t"] as? String,
              let state = controller.browserState, let page = controller.page,
              let url = URL(string: page.currentURL), let host = url.host?.lowercased(),
              url.scheme == "https" || ["localhost", "127.0.0.1"].contains(host) else { return }
        let enabled = state.browserPreferences.websiteNotifications ?? true
        let permission: SitePermission = state.isPrivate || !enabled ? .block
            : state.permission(.notifications, host: host, tabID: controller.tab.id)
        let id = message["id"] as? Int ?? 0
        func answer(_ value: [String: Any]) { page.sendNotificationMessage(value) }
        switch type {
        case "permission": answer(["t": "permission", "value": Self.value(permission)])
        case "request":
            guard permission == .ask else { return answer(["t": "request", "id": id, "value": Self.value(permission)]) }
            ask(controller, state: state, host: host, origin: "\(url.scheme ?? "https")://\(host)") { granted in
                answer(["t": "request", "id": id, "value": granted ? "granted" : "denied"])
            }
        case "show" where permission == .allow:
            deliver(message, id: id, host: host, controller: controller)
        case "close":
            let identifier = Self.identifier(tab: controller.tab.id, id: id, tag: nil)
            center.removeDeliveredNotifications(withIdentifiers: [identifier])
        default: break
        }
    }

    /// The window's permission prompt (`PermissionPrompt`), then macOS's own authorization the first time.
    private func ask(_ controller: TabController, state: BrowserState, host: String, origin: String,
                     completion: @escaping @MainActor (Bool) -> Void) {
        guard let window = controller.host else { return completion(false) }
        let request = PermissionRequest(origin: origin, kinds: .notifications) { [weak self] decision in
            Task { @MainActor [weak self] in
                // The prompt records the choice and how long it lasts; macOS's own authorization comes the first time.
                guard decision == .grant else { return completion(false) }
                completion(await self?.authorize() ?? false)
            }
        }
        window.tabController(controller, requestsPermission: request)
    }

    private func authorize() async -> Bool {
        if let authorization { return authorization }
        let granted = (try? await center.requestAuthorization(options: [.alert, .sound])) ?? false
        authorization = granted
        return granted
    }

    private static func identifier(tab: String, id: Int, tag: String?) -> String {
        tag.flatMap { $0.isEmpty ? nil : "\(tab)|tag:\($0)" } ?? "\(tab)|\(id)"
    }

    private func deliver(_ message: [String: Any], id: Int, host: String, controller: TabController) {
        let title = String((message["title"] as? String ?? "").prefix(256))
        guard !title.isEmpty || message["body"] != nil else { return }
        let content = UNMutableNotificationContent()
        content.title = title.isEmpty ? host : title
        content.subtitle = title.isEmpty ? "" : host
        content.body = String((message["body"] as? String ?? "").prefix(2000))
        content.threadIdentifier = host
        content.sound = message["silent"] as? Bool == true ? nil : .default
        #if DEBUG
        if WebProfiles.isTestMode {
            testDelivered.append(content.title + "|" + content.subtitle + "|" + content.body)
            controller.page?.sendNotificationMessage(["t": "event", "id": id, "name": "show"])
            return
        }
        #endif
        let tab = controller.tab.id
        content.userInfo = ["tab": tab, "id": id]
        let request = UNNotificationRequest(identifier: Self.identifier(tab: tab, id: id, tag: message["tag"] as? String),
                                            content: content, trigger: nil)
        Task { @MainActor [weak self, weak controller] in
            guard let self, await self.authorize() else { return }
            do {
                try await self.center.add(request)
                controller?.page?.sendNotificationMessage(["t": "event", "id": id, "name": "show"])
            } catch {
                controller?.page?.sendNotificationMessage(["t": "event", "id": id, "name": "error"])
            }
        }
    }

    // MARK: UNUserNotificationCenterDelegate

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification) async
        -> UNNotificationPresentationOptions { [.banner, .list, .sound] }

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse) async {
        guard let tab = response.notification.request.content.userInfo["tab"] as? String,
              let id = response.notification.request.content.userInfo["id"] as? Int else { return }
        await MainActor.run {
            guard let owner = BrowserWindows.owner(of: tab) else { return }
            owner.state.select(tab)
            owner.window?.makeKeyAndOrderFront(nil)
            NSApp.activate()
            owner.content.controller(for: tab)?.page?.sendNotificationMessage(["t": "event", "id": id, "name": "click"])
        }
    }
}
