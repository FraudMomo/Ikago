import Foundation

/// Every permission a site can ask for, in one catalog: its saved key, its name, how the prompt says it, its symbol, and
/// the Chromium permission bits it stands for. Sites start at Ask for all of them; the site card lists only the ones a
/// site has asked for or that were changed for it, so new kinds never lengthen it for sites that don't use them.
extension PermissionRequest.Kinds {
    static let location = Self(rawValue: 1 << 3)
    static let clipboard = Self(rawValue: 1 << 4)
    static let midi = Self(rawValue: 1 << 5)
    static let storageAccess = Self(rawValue: 1 << 6)
    static let localFonts = Self(rawValue: 1 << 7)
    static let idleDetection = Self(rawValue: 1 << 8)
    static let windowManagement = Self(rawValue: 1 << 9)
    static let keyboardLock = Self(rawValue: 1 << 10)
    static let pointerLock = Self(rawValue: 1 << 11)
    static let protocolHandlers = Self(rawValue: 1 << 12)
    static let fileEditing = Self(rawValue: 1 << 13)
    static let downloads = Self(rawValue: 1 << 14)
    static let protectedMedia = Self(rawValue: 1 << 15)
    static let sensors = Self(rawValue: 1 << 16)
    static let localNetwork = Self(rawValue: 1 << 17)
    static let virtualReality = Self(rawValue: 1 << 18)
    static let signIn = Self(rawValue: 1 << 19)
    static let tabControl = Self(rawValue: 1 << 20)
    static let appInstall = Self(rawValue: 1 << 21)

    struct Info: Sendable {
        let kind: PermissionRequest.Kinds
        /// Saved under this name (`SitePermissions`); never change one.
        let key: String
        let title: String
        /// "wants to …".
        let phrase: String
        let symbol: String
        /// The `cef_permission_request_types_t` bits it covers.
        let cef: UInt32
    }

    /// The catalog, in the order the prompt and site card list them.
    static let catalog: [Info] = [
        Info(kind: .camera, key: "camera", title: "Camera", phrase: "use your camera", symbol: "video.fill", cef: 1 << 2 | 1 << 1),
        Info(kind: .microphone, key: "microphone", title: "Microphone", phrase: "use your microphone", symbol: "mic.fill", cef: 1 << 12),
        Info(kind: .location, key: "location", title: "Location", phrase: "know your location", symbol: "location.fill", cef: 1 << 8),
        Info(kind: .notifications, key: "notifications", title: "Notifications", phrase: "send you notifications",
             symbol: "bell.fill", cef: 1 << 15),
        Info(kind: .clipboard, key: "clipboard", title: "Clipboard", phrase: "see what you copy", symbol: "doc.on.clipboard.fill",
             cef: 1 << 4),
        Info(kind: .fileEditing, key: "files", title: "Files", phrase: "edit files and folders you choose", symbol: "folder.fill",
             cef: 1 << 24),
        Info(kind: .downloads, key: "downloads", title: "Automatic downloads", phrase: "download several files",
             symbol: "arrow.down.circle.fill", cef: 1 << 14),
        Info(kind: .midi, key: "midi", title: "MIDI devices", phrase: "control your MIDI devices", symbol: "pianokeys", cef: 1 << 13),
        Info(kind: .localNetwork, key: "localNetwork", title: "Local network", phrase: "connect to devices on your network",
             symbol: "network", cef: 1 << 25 | 1 << 26 | 1 << 27),
        Info(kind: .windowManagement, key: "windows", title: "Window management", phrase: "open and place windows on your displays",
             symbol: "macwindow.on.rectangle", cef: 1 << 23),
        Info(kind: .keyboardLock, key: "keyboard", title: "Keyboard", phrase: "use your keyboard shortcuts", symbol: "keyboard.fill",
             cef: 1 << 16),
        Info(kind: .pointerLock, key: "pointer", title: "Pointer", phrase: "hide and lock your pointer", symbol: "cursorarrow.rays",
             cef: 1 << 17),
        Info(kind: .localFonts, key: "fonts", title: "Fonts", phrase: "use the fonts on your Mac", symbol: "textformat", cef: 1 << 7),
        Info(kind: .idleDetection, key: "idle", title: "Idle detection", phrase: "know when you're away from your Mac",
             symbol: "moon.zzz.fill", cef: 1 << 11),
        Info(kind: .sensors, key: "sensors", title: "Motion sensors", phrase: "use motion sensors", symbol: "gyroscope", cef: 1 << 28),
        Info(kind: .protocolHandlers, key: "links", title: "Link handling", phrase: "open a kind of link for you", symbol: "link",
             cef: 1 << 19),
        Info(kind: .storageAccess, key: "storage", title: "Storage access", phrase: "use its data while inside other sites",
             symbol: "externaldrive.fill", cef: 1 << 20 | 1 << 5 | 1 << 6),
        Info(kind: .protectedMedia, key: "protectedMedia", title: "Protected content", phrase: "play protected content",
             symbol: "play.rectangle.fill", cef: 1 << 18),
        Info(kind: .virtualReality, key: "xr", title: "Virtual reality", phrase: "use virtual and augmented reality",
             symbol: "visionpro", cef: 1 << 0 | 1 << 21 | 1 << 9),
        Info(kind: .signIn, key: "signIn", title: "Sign-in", phrase: "sign you in with your accounts", symbol: "person.badge.key.fill",
             cef: 1 << 10 | 1 << 29),
        Info(kind: .tabControl, key: "tabControl", title: "Shared tab control", phrase: "scroll and zoom a tab you share",
             symbol: "rectangle.on.rectangle", cef: 1 << 3),
        Info(kind: .appInstall, key: "appInstall", title: "App installation", phrase: "install itself as an app",
             symbol: "square.and.arrow.down.fill", cef: 1 << 22),
    ]

    /// The single kinds, one at a time, in the catalog's order.
    static var each: [PermissionRequest.Kinds] { catalog.map(\.kind) }

    /// This single kind's entry.
    var info: Info? { Self.catalog.first { $0.kind == self } }
    var key: String { info?.key ?? "unknown" }
    var title: String { info?.title ?? "Permission" }

    /// The single kinds in this set, in the catalog's order.
    var parts: [PermissionRequest.Kinds] { Self.catalog.map(\.kind).filter { contains($0) } }

    /// Chromium's permission bits as kinds, or nil when any bit is one Ikago doesn't know (so it is denied, fail-closed).
    static func chromium(_ bits: UInt32) -> PermissionRequest.Kinds? {
        var kinds: PermissionRequest.Kinds = []
        var covered: UInt32 = 0
        for info in catalog where bits & info.cef != 0 {
            kinds.insert(info.kind)
            covered |= info.cef
        }
        return bits & ~covered == 0 && !kinds.isEmpty ? kinds : nil
    }

    /// "use your camera, know your location and send you notifications".
    var phrase: String {
        let phrases = parts.compactMap(\.info?.phrase)
        guard phrases.count > 1 else { return phrases.first ?? "use a permission" }
        return phrases.dropLast().joined(separator: ", ") + " and " + phrases[phrases.count - 1]
    }
}
