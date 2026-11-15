import AppKit
import SwiftUI

/// The choices for one extension on one website, shared by the site card, the first-visit card and Settings.
@MainActor
enum ExtensionAccessMenu {
    static func label(_ status: ExtensionAccess.Status) -> String {
        switch status {
        case .everySite: "All websites"
        case .always: "Allowed"
        case .oneDay: "Allowed today"
        case .never: "Not allowed"
        case .ask: "Ask"
        }
    }

    static func detail(_ status: ExtensionAccess.Status, site: String) -> String {
        switch status {
        case .everySite: "Can read and change every website"
        case .always: "Can read and change \(site)"
        case .oneDay(let date): "Allowed on \(site) until \(date.formatted(date: .omitted, time: .shortened)) tomorrow"
        case .never: "Kept off \(site)"
        case .ask: "Asks before it reads \(site)"
        }
    }

    /// `then` runs after a choice (the page reloads so the change takes effect).
    static func choices(_ ext: ExtensionDescriptor, site: String, then: @escaping (ExtensionAccess.Choice) -> Void = { _ in }) -> [MenuChoice] {
        let access = ExtensionAccess.shared
        let status = access.status(ext.key, site: site)
        let oneDay: Bool = { if case .oneDay = status { return true } else { return false } }()
        func pick(_ choice: ExtensionAccess.Choice) { access.choose(choice, key: ext.key, site: site); then(choice) }
        var list = [
            MenuChoice(title: "Always Allow on This Website", isOn: status == .always, symbol: "checkmark.shield") { pick(.always) },
            MenuChoice(title: "Allow for One Day", isOn: oneDay, symbol: "clock") { pick(.oneDay) },
            MenuChoice(title: "Don’t Allow on This Website", isOn: status == .never, symbol: "nosign") { pick(.never) },
            MenuChoice(title: "Allow on Every Website", isOn: status == .everySite, separatorBefore: true, symbol: "globe") { pick(.everySite) },
        ]
        if status != .everySite, status != .ask {
            list.append(MenuChoice(title: "Ask Next Time", separatorBefore: true, symbol: "questionmark.circle") {
                access.forget(site: site, key: ext.key)
            })
        }
        return list
    }
}

/// An extension's icon, or a puzzle piece.
struct ExtensionIcon: View {
    let image: NSImage?
    var size: CGFloat = 20
    var body: some View {
        if let image {
            Image(nsImage: image).resizable().interpolation(.high).frame(width: size, height: size)
        } else {
            Image(systemName: "puzzlepiece.extension.fill").font(.system(size: size * 0.7)).foregroundStyle(.secondary)
                .frame(width: size, height: size)
        }
    }
}
