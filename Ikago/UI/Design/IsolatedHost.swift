import AppKit
import SwiftUI

/// Runs a part of the window (the sidebar, the top bars) in its own `NSHostingView` with its own view graph.
///
/// The window is otherwise one SwiftUI tree, so a change anywhere made SwiftUI walk everything: measured, a third of
/// the main thread went to that bookkeeping while browsing. A separate host keeps sidebar updates in the sidebar and
/// the rest of the window's updates out of it. The parent still sizes and animates the host like any view, and glass
/// inside it samples the window behind it as before.
///
/// Preferences can't cross hosts, so the ones the shell needs, the Downloads button's and the address field's frames,
/// are passed through `ChromeModel.downloadsButtonFrame` and `addressFieldFrame` in the shell's coordinates.
struct IsolatedHost<Content: View>: FillingViewRepresentable {
    let chrome: ChromeModel
    @ViewBuilder let content: Content
    @Environment(\.self) private var environment

    @MainActor final class Coordinator {
        let chrome: ChromeModel
        weak var host: NSView?
        init(chrome: ChromeModel) { self.chrome = chrome }

        /// `rect` is in the host's own (flipped) coordinates; the shell's root host is flipped too.
        func shellFrame(_ rect: CGRect?) -> CGRect? {
            guard let host, let rect else { return nil }
            let shell = sequence(first: host.superview, next: { $0?.superview }).compactMap { $0 }
                .first { String(describing: type(of: $0)).hasPrefix("NSHostingView") }
            return shell.map { host.convert(rect, to: $0) }
        }
        /// The last frames in the host's coordinates, reported again whenever the host moves or lays out.
        private var downloads: CGRect?
        private var address: CGRect?

        private var publishQueued = false

        func reportDownloads(_ rect: CGRect?) { downloads = rect; schedulePublish() }
        func reportAddress(_ rect: CGRect?) { address = rect; schedulePublish() }

        /// After the current layout or render pass: changing `ChromeModel` inside one makes the shell lay out again
        /// from within layout, and AppKit aborts a window that keeps asking for more passes.
        func schedulePublish() {
            guard !publishQueued else { return }
            publishQueued = true
            DispatchQueue.main.async { [weak self] in
                MainActor.assumeIsolated {
                    self?.publishQueued = false
                    self?.publish()
                }
            }
        }

        private func publish() {
            let downloadsFrame = shellFrame(downloads), addressFrame = shellFrame(address)
            if chrome.downloadsButtonFrame != downloadsFrame { chrome.downloadsButtonFrame = downloadsFrame }
            if chrome.addressFieldFrame != addressFrame { chrome.addressFieldFrame = addressFrame }
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator(chrome: chrome) }

    func makeNSView(context: Context) -> NSView {
        let host = IsolatedHostingView(rootView: root(context))
        host.didLayout = { [weak coordinator = context.coordinator] in coordinator?.schedulePublish() }
        host.sizingOptions = []
        host.safeAreaRegions = []
        context.coordinator.host = host
        return host
    }

    func updateNSView(_ view: NSView, context: Context) {
        // Carry the update's transaction (its animation) into this host's own view graph.
        let host = view as? IsolatedHostingView<IsolatedRoot<Content>>
        withTransaction(context.transaction) { host?.rootView = root(context) }
    }

    static func dismantleNSView(_ view: NSView, coordinator: Coordinator) {
        coordinator.reportDownloads(nil)
        coordinator.reportAddress(nil)
    }

    private func root(_ context: Context) -> IsolatedRoot<Content> {
        let coordinator = context.coordinator
        return IsolatedRoot(content: content, environment: environment,
                            reportDownloads: { coordinator.reportDownloads($0) }, reportAddress: { coordinator.reportAddress($0) })
    }
}

struct IsolatedRoot<Content: View>: View {
    let content: Content
    let environment: EnvironmentValues
    let reportDownloads: (CGRect?) -> Void
    let reportAddress: (CGRect?) -> Void

    var body: some View {
        content
            .environment(\.self, environment)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .overlayPreferenceValue(DownloadsAnchorKey.self) { anchors in
                GeometryReader { geometry in
                    Color.clear.onChange(of: anchors.toolbar.map { geometry[$0] }, initial: true) { _, rect in reportDownloads(rect) }
                }
                .allowsHitTesting(false)
            }
            .overlayPreferenceValue(AddressAnchorKey.self) { anchor in
                GeometryReader { geometry in
                    Color.clear.onChange(of: anchor.map { geometry[$0] }, initial: true) { _, rect in reportAddress(rect) }
                }
                .allowsHitTesting(false)
            }
    }
}

/// Reports when it lays out or joins a window, so frames measured before it was placed are published again.
final class IsolatedHostingView<Content: View>: NSHostingView<Content> {
    var didLayout: (() -> Void)?
    override func layout() {
        super.layout()
        didLayout?()
    }
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        didLayout?()
    }
}
