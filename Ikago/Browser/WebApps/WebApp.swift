import Foundation

/// A site kept as an app: its own window without sidebar or tabs, and a launcher in ~/Applications that can sit in
/// the Dock or Launchpad. The app opens and runs inside Ikago, so it shares the Space's logins and settings.
struct WebApp: Codable, Identifiable, Equatable, Hashable {
    var id = UUID().uuidString.lowercased()
    var name: String
    var url: String
    /// The Space it was installed from: its website data is the app's.
    var spaceID: UUID

    static let scheme = "ikago-app"
    var launchURL: String { "\(Self.scheme)://\(id)" }
    var host: String { URL(string: url)?.host?.lowercased() ?? "" }

    /// Whether `address` belongs to the app: the same site as its start page.
    func contains(_ address: String) -> Bool {
        guard let other = URL(string: address)?.host?.lowercased(), !host.isEmpty else { return false }
        return PublicSuffix.registrableDomain(other) == PublicSuffix.registrableDomain(host)
    }
}
