import Foundation
import WebKit

/// A site's camera/microphone request. Fail-closed: `resolve` runs once, and a request
/// that is dropped unresolved (tab closed, window gone) is denied.
@MainActor
final class PermissionRequest {
    struct Kinds: OptionSet, Sendable {
        let rawValue: Int
        static let camera = Kinds(rawValue: 1 << 0)
        static let microphone = Kinds(rawValue: 1 << 1)
    }

    enum Decision { case allow, deny }

    let origin: String
    let kinds: Kinds
    private let once: OneShot
    var onInvalidated: (() -> Void)?

    init(origin: String, kinds: Kinds, handler: @escaping @MainActor @Sendable (WKPermissionDecision) -> Void) {
        self.origin = origin
        self.kinds = kinds
        once = OneShot(handler)
    }

    var isResolved: Bool { once.isFired }

    func resolve(_ decision: Decision) { once.fire(decision == .allow ? .grant : .deny) }

    func invalidate() {
        resolve(.deny)
        let handler = onInvalidated
        onInvalidated = nil
        handler?()
    }

    deinit {
        let once = once
        Task { @MainActor in once.fire(.deny) }
    }

    static func kinds(for type: WKMediaCaptureType) -> Kinds {
        switch type {
        case .camera: .camera
        case .microphone: .microphone
        case .cameraAndMicrophone: [.camera, .microphone]
        @unknown default: [.camera, .microphone]
        }
    }
}

/// Holds WebKit's decision handler and calls it at most once (WebKit requires exactly once).
private final class OneShot: @unchecked Sendable {
    private var handler: (@MainActor @Sendable (WKPermissionDecision) -> Void)?

    init(_ handler: @escaping @MainActor @Sendable (WKPermissionDecision) -> Void) { self.handler = handler }

    @MainActor var isFired: Bool { handler == nil }

    @MainActor func fire(_ decision: WKPermissionDecision) {
        guard let handler else { return }
        self.handler = nil
        handler(decision)
    }
}
