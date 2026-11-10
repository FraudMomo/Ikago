import SwiftUI

/// How safely the tab's page was loaded, for the address bar's padlock.
enum PageSecurity {
    case secure      // HTTPS, every resource too
    case mixed       // HTTPS page that also loaded insecure content
    case insecure    // plain HTTP
    case none        // Ikago and extension pages, blank tabs

    @MainActor init(_ tab: TabItem) {
        if tab.url.hasPrefix("https://") { self = tab.hasOnlySecureContent ? .secure : .mixed }
        else if tab.url.hasPrefix("http://") { self = .insecure }
        else { self = .none }
    }

    var label: String {
        switch self {
        case .secure: "Secure connection"
        case .mixed: "Partly insecure: this page also loaded content over HTTP"
        case .insecure: "Not secure: this connection is not encrypted"
        case .none: ""
        }
    }
}

/// The padlock beside the address: a quiet lock when secure, an orange warning otherwise.
struct SecurityBadge: View {
    let tab: TabItem
    let colors: Palette
    var size: CGFloat = 9

    var body: some View {
        let security = PageSecurity(tab)
        switch security {
        case .secure:
            symbol("lock.fill").foregroundStyle(colors.tertiary).help(security.label)
        case .mixed:
            symbol("lock.trianglebadge.exclamationmark.fill").foregroundStyle(.orange).help(security.label)
        case .insecure:
            symbol("lock.open.fill").foregroundStyle(.orange).help(security.label)
        case .none:
            EmptyView()
        }
    }

    private func symbol(_ name: String) -> some View {
        Image(systemName: name).font(.system(size: size, weight: .semibold)).accessibilityLabel(PageSecurity(tab).label)
    }
}
